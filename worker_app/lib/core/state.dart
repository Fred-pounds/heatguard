import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/strings.dart';
import 'api.dart';
import 'notify.dart';
import 'theme.dart';

/// App state for one worker's device. Choices (language, crew, badge, server) are remembered on the
/// device so the app opens straight to their crew's notice. Nothing is tracked about the worker.
class WorkerState extends ChangeNotifier {
  late SharedPreferences _prefs;
  late Api api;
  Timer? _timer;

  bool ready = false;
  String lang = 'en';
  String? serverUrl;
  String? crewId;
  String crewName = '';
  String siteName = '';
  String? workerId;
  String? badge;
  bool alertsOn = false;

  List<J> crews = [];
  List<J> badges = [];
  J catalog = {};
  J? notice;
  J? me;
  bool online = true;
  bool loadingCrews = false;
  DateTime? lastOk;

  /// Called when something the worker must notice happens (level rises, midday break, own strain).
  void Function(String title, String body)? onAlert;

  String? _lastCategory;
  bool _lastMidday = false;
  String? _lastMyStatus;

  L10n get l => L10n(lang);
  bool get onboarded => crewId != null;
  Level get level => Level.of(notice?['category'] as String?);

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    lang = _prefs.getString('lang') ?? _deviceLanguage();
    serverUrl = _prefs.getString('server');
    crewId = _prefs.getString('crew_id');
    crewName = _prefs.getString('crew_name') ?? '';
    siteName = _prefs.getString('site_name') ?? '';
    workerId = _prefs.getString('worker_id');
    badge = _prefs.getString('badge');
    alertsOn = (_prefs.getBool('alerts') ?? false) && (DeviceNotify.granted || !DeviceNotify.supported);
    api = Api(ApiConfig.resolve(serverUrl));
    ready = true;
    notifyListeners();
    loadCatalog();
    if (crewId != null) loadBadges();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => refresh());
    refresh();
  }

  String _deviceLanguage() {
    final code = PlatformDispatcher.instance.locale.languageCode;
    return L10n.supported.containsKey(code) ? code : 'en';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------- settings
  Future<void> setLang(String v) async {
    lang = v;
    await _prefs.setString('lang', v);
    notifyListeners();
  }

  Future<void> setServer(String? v) async {
    serverUrl = (v == null || v.trim().isEmpty) ? null : ApiConfig.normalise(v);
    serverUrl == null ? await _prefs.remove('server') : await _prefs.setString('server', serverUrl!);
    api = Api(ApiConfig.resolve(serverUrl));
    crews = [];
    notifyListeners();
    await loadCatalog();
    await refresh();
  }

  Future<void> setCrew(J crew) async {
    crewId = crew['crew_id'] as String;
    crewName = '${crew['name']}';
    siteName = '${crew['worksite_name'] ?? ''}';
    workerId = null;
    badge = null;
    notice = null;
    me = null;
    _lastCategory = null;
    await _prefs.setString('crew_id', crewId!);
    await _prefs.setString('crew_name', crewName);
    await _prefs.setString('site_name', siteName);
    await _prefs.remove('worker_id');
    await _prefs.remove('badge');
    notifyListeners();
    await loadBadges();
    await refresh();
  }

  Future<void> setBadge(String? id) async {
    workerId = id;
    badge = id == null ? null : '${badges.firstWhere((b) => b['worker_id'] == id, orElse: () => {'badge': id})['badge']}';
    me = null;
    id == null ? await _prefs.remove('worker_id') : await _prefs.setString('worker_id', id);
    badge == null ? await _prefs.remove('badge') : await _prefs.setString('badge', badge!);
    notifyListeners();
    await refresh();
  }

  /// Leave the crew and go back to onboarding (used by "Change crew").
  Future<void> resetCrew() async {
    crewId = null;
    workerId = null;
    badge = null;
    notice = null;
    me = null;
    for (final k in ['crew_id', 'crew_name', 'site_name', 'worker_id', 'badge']) {
      await _prefs.remove(k);
    }
    notifyListeners();
    loadCatalog();
  }

  Future<bool> setAlerts(bool on) async {
    if (on && DeviceNotify.supported && !DeviceNotify.granted) {
      on = await DeviceNotify.request();
    }
    alertsOn = on;
    await _prefs.setBool('alerts', on);
    notifyListeners();
    return on;
  }

  // ---------------------------------------------------------------- data
  Future<void> loadCatalog() async {
    loadingCrews = true;
    notifyListeners();
    try {
      crews = jList(await api.get('/worker/crews'));
      catalog = jMap(await api.get('/workers/catalog'));
      online = true;
    } catch (_) {
      online = false;
    }
    loadingCrews = false;
    notifyListeners();
  }

  Future<void> loadBadges() async {
    if (crewId == null) return;
    try {
      badges = jList(await api.get('/worker/badges/$crewId'));
    } catch (_) {}
    notifyListeners();
  }

  Future<void> refresh() async {
    if (crewId == null) return;
    try {
      notice = jMap(await api.get('/worker/$crewId'));
      me = workerId == null ? null : jMap(await api.get('/worker/me/$workerId'));
      if (catalog.isEmpty) catalog = jMap(await api.get('/workers/catalog'));
      online = true;
      lastOk = DateTime.now();
      _checkAlerts();
    } catch (_) {
      online = false;
    }
    notifyListeners();
  }

  void _checkAlerts() {
    final n = notice;
    if (n == null) return;
    final cat = '${n['category']}';
    final rose = _lastCategory != null && Level.of(cat).rank > Level.of(_lastCategory).rank && Level.of(cat).rank >= 2;
    if (rose) _alert(l.t('heat_rising'), '${l.t('level.$cat')}. ${l.t('notice.$cat')}');
    final midday = n['midday_break'] == true;
    if (midday && !_lastMidday && _lastCategory != null) _alert(l.t('app_name'), l.t('midday_break'));
    final my = jMap(me?['signal'])['status'] as String?;
    if (my == 'check' && _lastMyStatus != 'check') _alert(l.t('app_name'), l.t('my_status_check'));
    _lastCategory = cat;
    _lastMidday = midday;
    _lastMyStatus = my;
  }

  void _alert(String title, String body) {
    onAlert?.call(title, body);
    if (alertsOn) DeviceNotify.show(title, body);
  }

  // ---------------------------------------------------------------- actions
  /// Returns the escalation level: 'first_aid' or 'emergency'.
  Future<String> reportSymptoms({required bool self, required List<String> symptoms}) async {
    final r = jMap(await api.post('/symptoms', {
      'crew_id': crewId,
      'worker_id': self ? workerId : null,
      'reported_by': self ? 'self' : 'coworker',
      'symptoms': symptoms,
    }));
    return '${r['level']}';
  }

  Future<void> setConsent(bool granted, {String? ageBand}) async {
    await api.post('/worker/me/$workerId/consent', {'granted': granted, 'age_band': ?ageBand});
    await refresh();
  }
}
