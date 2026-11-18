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
  String? _deviceToken;
  bool alertsOn = false;

  /// True after the server said this phone is no longer paired (e.g. the OHS officer issued a new code).
  bool unpaired = false;

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
    _deviceToken = _prefs.getString('device_token');
    if (_deviceToken == null) {
      workerId = null;
      badge = null;
    }
    alertsOn = (_prefs.getBool('alerts') ?? false) && (DeviceNotify.granted || !DeviceNotify.supported);
    api = Api(ApiConfig.resolve(serverUrl), deviceToken: _deviceToken);
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
    api = Api(ApiConfig.resolve(serverUrl), deviceToken: _deviceToken);
    crews = [];
    notifyListeners();
    await loadCatalog();
    await refresh();
  }

  Future<void> setCrew(J crew, {bool keepBadge = false}) async {
    crewId = crew['crew_id'] as String;
    crewName = '${crew['name']}';
    siteName = '${crew['worksite_name'] ?? ''}';
    if (!keepBadge) await unlinkBadge(notify: false);
    notice = null;
    me = null;
    _lastCategory = null;
    await _prefs.setString('crew_id', crewId!);
    await _prefs.setString('crew_name', crewName);
    await _prefs.setString('site_name', siteName);
    notifyListeners();
    await loadBadges();
    await refresh();
  }

  /// Pair this phone with a badge using its code. Returns an error string key, or null on success.
  Future<String?> pairBadge(String id, String code) async {
    try {
      final r = jMap(await api.post('/worker/pair', {'worker_id': id, 'code': code.trim()}));
      _deviceToken = '${r['device_token']}';
      api.deviceToken = _deviceToken;
      workerId = id;
      badge = '${r['badge']}';
      unpaired = false;
      me = null;
      await _prefs.setString('worker_id', id);
      await _prefs.setString('badge', badge!);
      await _prefs.setString('device_token', _deviceToken!);
      notifyListeners();
      refresh();
      return null;
    } on ApiError catch (e) {
      return switch (e.status) {
        403 || 422 => 'pair_wrong',
        429 => 'pair_locked',
        404 => 'pair_wrong',
        _ => 'cant_connect',
      };
    }
  }

  /// Unlink the badge from this phone (the server-side pairing is replaced when a phone pairs again).
  Future<void> unlinkBadge({bool notify = true}) async {
    workerId = null;
    badge = null;
    me = null;
    _deviceToken = null;
    api.deviceToken = null;
    for (final k in ['worker_id', 'badge', 'device_token']) {
      await _prefs.remove(k);
    }
    if (notify) notifyListeners();
  }

  /// Leave the crew and go back to onboarding (used by "Change crew").
  Future<void> resetCrew() async {
    crewId = null;
    notice = null;
    await unlinkBadge(notify: false);
    for (final k in ['crew_id', 'crew_name', 'site_name']) {
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
      if (workerId != null) {
        try {
          me = jMap(await api.get('/worker/me/$workerId'));
        } on ApiError catch (e) {
          if (e.status == 401 || e.status == 404) {
            await unlinkBadge(notify: false);
            unpaired = true;
          } else {
            rethrow;
          }
        }
      }
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
    final r = jMap(
      await api.post('/symptoms', {
        'crew_id': crewId,
        'worker_id': self ? workerId : null,
        'reported_by': self ? 'self' : 'coworker',
        'symptoms': symptoms,
      }),
    );
    return '${r['level']}';
  }

  Future<void> setConsent(bool granted, {String? ageBand}) async {
    await api.post('/worker/me/$workerId/consent', {'granted': granted, 'age_band': ?ageBand});
    await refresh();
  }
}
