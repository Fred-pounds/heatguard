import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/config.dart';
import '../models/models.dart';
import '../services/api_client.dart';

/// Central app state: polls the backend and exposes typed data to the UI.
/// Nothing on the dashboard is hard-coded: every figure comes from the API.
class AppState extends ChangeNotifier {
  AppState({ApiClient? api}) : api = api ?? ApiClient();
  final ApiClient api;

  Timer? _timer;
  bool _busy = false;

  // ---- connectivity
  bool initialised = false;
  bool backendOnline = false;
  DateTime? lastSuccess;
  String? lastError;

  // ---- data
  J meta = {};
  J overview = {};
  J simulation = {};
  List<Worksite> worksites = [];
  List<Crew> crews = [];
  List<Assessment> assessments = [];
  List<Alert> alerts = [];
  List<Intervention> interventions = [];
  List<Reading> readings = [];
  List<J> scenarios = [];
  J workersSummary = {}; // crew_id -> crew-level counts (no individual values)
  List<J> escalations = []; // redacted for supervisors, full for OHS
  List<J> workers = []; // OHS only: individual signals
  J workerCatalog = {};

  /// Demo role. Supervisors see crew-level information; the OHS role sees individual health data.
  String role = 'supervisor';
  bool get isOhs => role == 'ohs';

  // ---- UI selections
  String? selectedWorksiteId;
  int timeRangeMinutes = 120;
  String? zoneFilter;
  String? crewFilter;

  /// Data are "live" only if the last successful poll was recent.
  bool get dataIsLive =>
      backendOnline && lastSuccess != null && DateTime.now().difference(lastSuccess!) < AppConfig.pollInterval * 4;

  Worksite? get selectedWorksite {
    for (final w in worksites) {
      if (w.id == selectedWorksiteId) return w;
    }
    return worksites.isEmpty ? null : worksites.first;
  }

  J get counts => jMap(overview['counts']);
  J get health => jMap(overview['health']);

  Crew? crewById(String id) {
    for (final c in crews) {
      if (c.id == id) return c;
    }
    return null;
  }

  Assessment? assessmentFor(String crewId) {
    for (final a in assessments) {
      if (a.crewId == crewId) return a;
    }
    return null;
  }

  Worksite? worksiteById(String id) {
    for (final w in worksites) {
      if (w.id == id) return w;
    }
    return null;
  }

  J? stationStatus(String worksiteId) {
    final st = jMap(simulation['stations'])[worksiteId];
    return st == null ? null : jMap(st);
  }

  List<Alert> get activeAlerts => alerts.where((a) => !a.resolved).toList();

  void start() {
    refresh();
    _timer?.cancel();
    _timer = Timer.periodic(AppConfig.pollInterval, (_) => refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      if (meta.isEmpty) {
        meta = jMap(await api.get('/meta'));
        scenarios = jList(meta['scenarios']);
        workerCatalog = jMap(await api.get('/workers/catalog'));
      }
      final results = await Future.wait([
        api.get('/overview'),
        api.get('/crews'),
        api.get('/assessments/latest'),
        api.get('/alerts'),
        api.get('/interventions'),
        api.get('/workers/summary'),
        api.get('/escalations'),
      ]);
      overview = jMap(results[0]);
      simulation = jMap(overview['simulation']);
      worksites = jList(overview['worksites']).map(Worksite.new).toList();
      selectedWorksiteId ??= worksites.isEmpty ? null : worksites.first.id;
      crews = jList(results[1]).map(Crew.new).toList();
      assessments = jList(results[2]).map(Assessment.new).toList();
      alerts = jList(results[3]).map(Alert.new).toList();
      interventions = jList(results[4]).map(Intervention.new).toList();
      workersSummary = jMap(results[5]);
      escalations = jList(results[6]);
      workers = isOhs ? jList(await api.get('/workers')) : [];
      if (selectedWorksiteId != null) {
        readings = jList(await api.get('/sensors/readings', {
          'worksite_id': selectedWorksiteId,
          'limit': '$timeRangeMinutes',
        })).map(Reading.new).toList();
      }
      backendOnline = true;
      lastSuccess = DateTime.now();
      lastError = null;
    } on ApiException catch (e) {
      backendOnline = false;
      lastError = e.message;
    } catch (e) {
      backendOnline = false;
      lastError = 'Unexpected error: $e';
    } finally {
      initialised = true;
      _busy = false;
      notifyListeners();
    }
  }

  void setRole(String r) {
    role = r;
    api.role = r;
    workers = [];
    escalations = [];
    notifyListeners();
    _busy = false;
    refresh();
  }

  List<J> get openEscalations => escalations.where((e) => e['status'] != 'closed').toList();

  void selectWorksite(String? id) {
    selectedWorksiteId = id;
    zoneFilter = null;
    crewFilter = null;
    readings = [];
    notifyListeners();
    refresh();
  }

  void setTimeRange(int minutes) {
    timeRangeMinutes = minutes;
    notifyListeners();
    refresh();
  }

  void setFilters({String? zone, String? crew, bool clearZone = false, bool clearCrew = false}) {
    if (clearZone) zoneFilter = null;
    if (clearCrew) crewFilter = null;
    if (zone != null) zoneFilter = zone;
    if (crew != null) crewFilter = crew;
    notifyListeners();
  }

  /// Runs an action against the API. Returns an error message, or null on success.
  Future<String?> run(Future<dynamic> Function(ApiClient api) action) async {
    try {
      await action(api);
      _busy = false;
      await refresh();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return 'Unexpected error: $e';
    }
  }
}
