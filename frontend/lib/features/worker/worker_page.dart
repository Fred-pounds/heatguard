import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/format.dart';
import '../../core/l10n/strings.dart';
import '../../core/severity.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/api_client.dart';
import '../../widgets/common.dart';

/// Worker-facing, mobile-friendly notice. Shows only the selected crew's
/// crew-level information in plain language. No tracking, no individual data.
class WorkerPage extends StatefulWidget {
  const WorkerPage({super.key});
  @override
  State<WorkerPage> createState() => _WorkerPageState();
}

class _WorkerPageState extends State<WorkerPage> {
  final api = ApiClient(role: 'worker');
  List<J> crews = [];
  String? crewId;
  J? notice;
  String lang = 'en';
  bool offline = false;
  DateTime? lastOk;
  Timer? timer;

  L10n get l => L10n(lang);

  @override
  void initState() {
    super.initState();
    _loadCrews();
    timer = Timer.periodic(const Duration(seconds: 3), (_) => _loadNotice());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _loadCrews() async {
    try {
      crews = jList(await api.get('/worker/crews'));
      offline = false;
    } catch (_) {
      offline = true;
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadNotice() async {
    if (crewId == null) {
      if (crews.isEmpty) await _loadCrews();
      return;
    }
    try {
      notice = jMap(await api.get('/worker/$crewId'));
      offline = false;
      lastOk = DateTime.now();
    } catch (_) {
      offline = true;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      appBar: AppBar(
        backgroundColor: HG.navy,
        foregroundColor: Colors.white,
        title: Row(children: [
          const Icon(Icons.shield_outlined, size: 20),
          const SizedBox(width: 8),
          Text('HeatGuard · ${l.t('title')}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ]),
        actions: [
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
            const Center(child: SimulatedBadge(text: 'SIMULATED DATA - DEMONSTRATION ONLY')),
            const SizedBox(height: 12),
            if (offline) _banner(l.t('offline'), HG.high, Icons.cloud_off),
            DropdownButtonFormField<String>(
              initialValue: crewId,
              isExpanded: true,
              decoration: InputDecoration(labelText: l.t('select_crew')),
              items: [for (final c in crews) DropdownMenuItem(value: c['crew_id'] as String, child: Text('${c['name']} - ${c['worksite_name']}', overflow: TextOverflow.ellipsis))],
              onChanged: (v) {
                setState(() {
                  crewId = v;
                  notice = null;
                });
                _loadNotice();
              },
            ),
            const SizedBox(height: 16),
            if (crewId == null)
              const EmptyState(icon: Icons.groups, title: 'Choose your crew to see heat safety information')
            else if (notice == null)
              const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()))
            else
              ..._content(notice!),
            const SizedBox(height: 18),
            Text(l.t('privacy'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, color: HG.muted)),
            if (lang != 'en')
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Translations pending review by qualified native speakers - English shown.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: HG.elevated)),
              ),
          ]),
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
    final stale = offline;
    return [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: stale ? Colors.grey.shade600 : sev.color, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(sev.icon, color: sev.onColor, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${n['crew_name']}', style: TextStyle(color: sev.onColor.withValues(alpha: 0.85), fontSize: 13)),
                Text(l.t('level.$cat').toUpperCase(), style: TextStyle(color: sev.onColor, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Text(l.t('${n['message_key']}'), style: TextStyle(color: sev.onColor, fontSize: 18, fontWeight: FontWeight.w600, height: 1.35)),
          const SizedBox(height: 10),
          Text('${l.t('updated')}: ${fmtTime(n['updated_at'])}${n['sim_clock'] == null ? '' : ' (site time ${n['sim_clock']})'}',
              style: TextStyle(color: sev.onColor.withValues(alpha: 0.85), fontSize: 12)),
        ]),
      ),
      const SizedBox(height: 14),
      if (n['water_reminder'] == true || cat == 'routine')
        _tile(Icons.water_drop, const Color(0xFF1C7ED6), l.t('water')),
      if (n['work_rest'] != null) _tile(Icons.schedule, HG.elevated, '${l.t('work_rest')}: ${n['work_rest']}'),
      if (jList(n['active_protective_actions']).isNotEmpty)
        _card(l.t('protective_actions'), [
          for (final a in jList(n['active_protective_actions'])) Text('• ${a['action_label']} (since ${fmtTime(a['start_time'])})', style: const TextStyle(fontSize: 15)),
        ]),
      if (jList(n['actions']).isNotEmpty)
        _card(l.t('what_to_do'), [
          for (final a in jList(n['actions']))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.chevron_right, size: 20),
                Expanded(child: Text(l.t('${a['key']}') == a['key'] ? '${a['action']}' : l.t('${a['key']}'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
              ]),
            ),
        ]),
      Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFFFFF0F0), border: Border.all(color: HG.high), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.emergency, color: HG.high),
            const SizedBox(width: 8),
            Text(l.t('emergency'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: HG.high)),
          ]),
          const SizedBox(height: 8),
          for (final e in (n['emergency'] as List? ?? []))
            Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('• $e', style: const TextStyle(fontSize: 14.5, height: 1.35))),
        ]),
      ),
    ];
  }

  Widget _tile(IconData icon, Color c, String text) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.withValues(alpha: 0.4))),
        child: Row(children: [
          Icon(icon, color: c, size: 28),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _card(String title, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: HG.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 10),
          ...children,
        ]),
      );
}
