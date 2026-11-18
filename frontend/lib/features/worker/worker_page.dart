import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/format.dart';
import '../../core/l10n/strings.dart';
import '../../core/severity.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/api_client.dart';
import '../../services/notify.dart';
import '../../widgets/common.dart';

/// Worker-facing app: crew notice in plain language (English, Arabic, Urdu, Hindi), optional consented
/// wearable sharing, "I feel unwell" escalation and phone notifications. No tracking, crew-level only.
class WorkerPage extends StatefulWidget {
  const WorkerPage({super.key});
  @override
  State<WorkerPage> createState() => _WorkerPageState();
}

class _WorkerPageState extends State<WorkerPage> {
  final api = ApiClient(role: 'worker');
  List<J> crews = [];
  List<J> badges = [];
  J catalog = {};
  String? crewId;
  String? workerId;
  J? notice;
  J? me;
  String lang = 'en';
  bool offline = false;
  bool notify = false;
  String? reportResult; // 'first_aid' | 'emergency'
  String? _lastCategory;
  bool _lastMidday = false;
  String? _lastMyStatus;
  Timer? timer;

  L10n get l => L10n(lang);

  @override
  void initState() {
    super.initState();
    _loadCrews();
    notify = BrowserNotify.granted;
    timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _loadCrews() async {
    try {
      crews = jList(await api.get('/worker/crews'));
      catalog = jMap(await api.get('/workers/catalog'));
      offline = false;
    } catch (_) {
      offline = true;
    }
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    if (crewId == null) {
      if (crews.isEmpty) await _loadCrews();
      return;
    }
    try {
      notice = jMap(await api.get('/worker/$crewId'));
      me = workerId == null ? null : jMap(await api.get('/worker/me/$workerId'));
      offline = false;
      _maybeNotify();
    } catch (_) {
      offline = true;
    }
    if (mounted) setState(() {});
  }

  void _maybeNotify() {
    final n = notice;
    if (n == null) return;
    final cat = '${n['category']}';
    final worse = _lastCategory != null && Sev.of(cat).level > Sev.of(_lastCategory).level && Sev.of(cat).level >= 2;
    if (notify && worse) BrowserNotify.show('HeatGuard: ${l.t('level.$cat')}', l.t('notice.$cat'));
    final midday = n['midday_break'] == true;
    if (notify && midday && !_lastMidday) BrowserNotify.show('HeatGuard', l.t('midday_break'));
    final myStatus = jMap(me?['signal'])['status'] as String?;
    if (notify && myStatus == 'check' && _lastMyStatus != 'check') BrowserNotify.show('HeatGuard', l.t('my_status_check'));
    _lastCategory = cat;
    _lastMidday = midday;
    _lastMyStatus = myStatus;
  }

  Future<void> _selectCrew(String? v) async {
    setState(() {
      crewId = v;
      workerId = null;
      notice = null;
      me = null;
      badges = [];
      reportResult = null;
      _lastCategory = null;
    });
    if (v != null) {
      try {
        badges = jList(await api.get('/worker/badges/$v'));
      } catch (_) {}
    }
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: l.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F4F7),
        appBar: AppBar(
          backgroundColor: HG.navy,
          foregroundColor: Colors.white,
          title: Text('HeatGuard · ${l.t('title')}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          actions: [
            IconButton(
              tooltip: l.t('notify_on'),
              icon: Icon(notify ? Icons.notifications_active : Icons.notifications_off_outlined),
              onPressed: () async {
                final ok = notify ? false : await BrowserNotify.request();
                setState(() => notify = ok);
              },
            ),
            PopupMenuButton<String>(
              tooltip: 'Language',
              icon: const Icon(Icons.translate),
              onSelected: (v) => setState(() => lang = v),
              itemBuilder: (_) => [for (final e in L10n.supported.entries) CheckedPopupMenuItem(value: e.key, checked: lang == e.key, child: Text(e.value))],
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Center(child: SimulatedBadge(text: l.t('simulated'))),
              if (l.isDraft) Padding(padding: const EdgeInsets.only(top: 8), child: Text(l.t('draft'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: Color(0xFF9A3412)))),
              const SizedBox(height: 12),
              if (offline) _banner(l.t('offline'), HG.high, Icons.cloud_off),
              DropdownButtonFormField<String>(
                initialValue: crewId,
                isExpanded: true,
                decoration: InputDecoration(labelText: l.t('select_crew')),
                items: [for (final c in crews) DropdownMenuItem(value: c['crew_id'] as String, child: Text('${c['name']} - ${c['worksite_name']}', overflow: TextOverflow.ellipsis))],
                onChanged: _selectCrew,
              ),
              if (badges.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  key: ValueKey('badge-$crewId'),
                  initialValue: workerId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l.t('select_badge')),
                  items: [
                    DropdownMenuItem(value: null, child: Text(l.t('no_badge'))),
                    for (final b in badges) DropdownMenuItem(value: b['worker_id'] as String, child: Text('${b['badge']}')),
                  ],
                  onChanged: (v) {
                    setState(() => workerId = v);
                    _refresh();
                  },
                ),
              ],
              const SizedBox(height: 16),
              if (crewId == null)
                const EmptyState(icon: Icons.groups, title: 'Choose your crew to see heat safety information')
              else if (notice == null)
                const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()))
              else
                ..._content(notice!),
              const SizedBox(height: 18),
              Text(l.t('privacy'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: HG.muted)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _banner(String text, Color c, IconData icon) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
        ]),
      );

  List<Widget> _content(J n) {
    final cat = '${n['category']}';
    final sev = Sev.of(cat);
    return [
      if (reportResult != null) _reportResultCard(),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: offline ? Colors.grey.shade600 : sev.color, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(sev.icon, color: sev.onColor, size: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${n['crew_name']}', style: TextStyle(color: sev.onColor.withValues(alpha: 0.85), fontSize: 13)),
                Text(l.t('level.$cat'), style: TextStyle(color: sev.onColor, fontSize: 28, fontWeight: FontWeight.w800)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Text(l.t('${n['message_key']}'), style: TextStyle(color: sev.onColor, fontSize: 18, fontWeight: FontWeight.w600, height: 1.4)),
          const SizedBox(height: 10),
          Text('${l.t('updated')}: ${fmtTime(n['updated_at'])}${n['sim_clock'] == null ? '' : ' (${n['sim_clock']} GST)'}',
              style: TextStyle(color: sev.onColor.withValues(alpha: 0.85), fontSize: 12)),
        ]),
      ),
      const SizedBox(height: 14),
      if (n['midday_break'] == true) _tile(Icons.wb_sunny_outlined, const Color(0xFF1D4ED8), l.t('midday_break')),
      if (n['water_reminder'] == true || cat == 'routine') _tile(Icons.water_drop, const Color(0xFF1C7ED6), l.t('water')),
      if (n['work_rest'] != null) _tile(Icons.schedule, HG.elevated, '${l.t('work_rest')}: ${l.or('regime.${n['work_rest_id']}', '${n['work_rest']}')}'),
      _unwellButton(),
      if (workerId != null && me != null) _consentCard(me!),
      if (jList(n['active_protective_actions']).isNotEmpty)
        _card(l.t('protective_actions'), [
          for (final a in jList(n['active_protective_actions'])) Text('• ${l.or('action.${a['action']}', '${a['action_label']}')} (${fmtTime(a['start_time'])})', style: const TextStyle(fontSize: 15)),
        ]),
      if (jList(n['actions']).isNotEmpty)
        _card(l.t('what_to_do'), [
          for (final a in jList(n['actions']))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.check_circle_outline, size: 18, color: HG.muted)),
                const SizedBox(width: 8),
                Expanded(child: Text(l.or('${a['key']}', '${a['action']}'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
              ]),
            ),
        ]),
      _card(l.t('emergency'), [
        for (final k in ['emergency.1', 'emergency.2', 'emergency.3'])
          Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• ${l.t(k)}', style: const TextStyle(fontSize: 14.5, height: 1.4))),
      ], icon: Icons.emergency_outlined),
    ];
  }

  Widget _reportResultCard() {
    final emergency = reportResult == 'emergency';
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: emergency ? HG.critical : HG.navy, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Icon(emergency ? Icons.call : Icons.medical_services_outlined, color: Colors.white, size: 30),
        const SizedBox(width: 12),
        Expanded(child: Text(l.t(emergency ? 'unwell_sent_emergency' : 'unwell_sent_first_aid'), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, height: 1.35))),
      ]),
    );
  }

  Widget _unwellButton() => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SizedBox(
          height: 54,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: HG.navy, textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            onPressed: _reportSymptoms,
            icon: const Icon(Icons.medical_services_outlined),
            label: Text(l.t('unwell_button')),
          ),
        ),
      );

  Future<void> _reportSymptoms() async {
    final red = jMap(catalog['symptoms_red_flag']).keys.toList();
    final fa = jMap(catalog['symptoms_first_aid']).keys.toList();
    final chosen = <String>{};
    String who = 'self';
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Directionality(
        textDirection: l.isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: StatefulBuilder(
          builder: (ctx, setS) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(l.t('unwell_title'), style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'self', label: Text(l.t('unwell_who_self'))),
                    ButtonSegment(value: 'coworker', label: Text(l.t('unwell_who_coworker'))),
                  ],
                  selected: {who},
                  onSelectionChanged: (v) => setS(() => who = v.first),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(shrinkWrap: true, children: [
                    for (final code in [...red, ...fa])
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: chosen.contains(code),
                        onChanged: (v) => setS(() => v == true ? chosen.add(code) : chosen.remove(code)),
                        title: Text(l.t('symptom.$code'), style: TextStyle(fontSize: 15, fontWeight: red.contains(code) ? FontWeight.w700 : FontWeight.w400)),
                      ),
                  ]),
                ),
                const SizedBox(height: 8),
                FilledButton(onPressed: chosen.isEmpty ? null : () => Navigator.pop(ctx, true), child: Text(l.t('unwell_send'))),
              ]),
            ),
          ),
        ),
      ),
    );
    if (ok != true || crewId == null) return;
    try {
      final r = jMap(await api.post('/symptoms', {
        'crew_id': crewId,
        'worker_id': who == 'self' ? workerId : null,
        'reported_by': who,
        'symptoms': chosen.toList(),
      }));
      setState(() => reportResult = '${r['level']}');
    } catch (e) {
      if (mounted) showResult(context, '$e', '');
    }
  }

  Widget _consentCard(J me) {
    final consent = jMap(me['consent']);
    final granted = consent['status'] == 'granted';
    final sig = jMap(me['signal']);
    String? band = me['age_band'] as String?;
    return StatefulBuilder(
      builder: (context, setC) => _card(l.t('consent_title'), [
        Text(granted ? l.t('consent_on') : l.t('consent_off'), style: TextStyle(fontWeight: FontWeight.w700, color: granted ? const Color(0xFF166534) : HG.muted)),
        const SizedBox(height: 8),
        Text(l.t('consent_body'), style: const TextStyle(fontSize: 13.5, color: HG.muted, height: 1.45)),
        const SizedBox(height: 12),
        if (granted) ...[
          if (sig['heart_rate'] != null)
            Text('${l.t('my_heart_rate')}: ${sig['heart_rate']} bpm', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(sig['status'] == 'check' ? l.t('my_status_check') : l.t('my_status_ok'),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: sig['status'] == 'check' ? HG.high : const Color(0xFF166534))),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: () => _setConsent(false, null), child: Text(l.t('consent_stop'))),
        ] else ...[
          DropdownButtonFormField<String>(
            initialValue: band,
            decoration: InputDecoration(labelText: l.t('consent_age')),
            items: [for (final b in (catalog['age_bands'] as List? ?? [])) DropdownMenuItem(value: '$b', child: Text('$b'))],
            onChanged: (v) => setC(() => band = v),
          ),
          const SizedBox(height: 10),
          FilledButton(onPressed: () => _setConsent(true, band), child: Text(l.t('consent_share'))),
        ],
      ], icon: Icons.watch_outlined),
    );
  }

  Future<void> _setConsent(bool granted, String? band) async {
    try {
      await api.post('/worker/me/$workerId/consent', {'granted': granted, 'age_band': ?band});
      await _refresh();
    } catch (e) {
      if (mounted) showResult(context, '$e', '');
    }
  }

  Widget _tile(IconData icon, Color c, String text) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.withValues(alpha: 0.35))),
        child: Row(children: [
          Icon(icon, color: c, size: 28),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.35))),
        ]),
      );

  Widget _card(String title, List<Widget> children, {IconData? icon}) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: HG.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (icon != null) ...[Icon(icon, size: 20, color: HG.text), const SizedBox(width: 8)],
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          ]),
          const SizedBox(height: 10),
          ...children,
        ]),
      );
}
