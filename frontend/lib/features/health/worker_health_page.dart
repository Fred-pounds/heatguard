import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../widgets/common.dart';

/// Consented wearable signals and clinical escalations.
/// Supervisors see crew-level counts and what to act on; individual values and symptoms are OHS-only.
class WorkerHealthPage extends StatelessWidget {
  const WorkerHealthPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = Theme.of(context).textTheme;
    return PageBody(children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Icon(s.isOhs ? Icons.verified_user_outlined : Icons.lock_outline, color: HG.muted),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                s.isOhs
                    ? 'OHS view: individual signals and symptoms of consenting workers. Use only for health and safety. '
                        'Raw signals are kept for 2 hours; withdrawing consent deletes them.'
                    : 'Supervisor view: crew-level information only. Individual signals and symptoms are visible to the OHS role '
                        '(occupational health officer / first aider).',
                style: t.bodyMedium,
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: () => s.setRole(s.isOhs ? 'supervisor' : 'ohs'),
              child: Text(s.isOhs ? 'Switch to supervisor' : 'Switch to OHS role (demo)'),
            ),
          ]),
        ),
      ),
      _Escalations(),
      SectionCard(
        title: 'Wearable programme by crew',
        subtitle: 'Optional, consent-based. Workers can stop sharing at any time from their phone.',
        child: ResponsiveGrid(minItemWidth: 260, children: [
          for (final e in s.workersSummary.entries.map((e) => MapEntry(e.key, jMap(e.value))).where((e) => (e.value['enrolled'] as num? ?? 0) > 0))
            _CrewProgramme(name: '${e.value['crew_name']}', m: e.value),
        ]),
      ),
      if (s.isOhs) _WorkersTable(),
    ]);
  }
}

class _CrewProgramme extends StatelessWidget {
  const _CrewProgramme({required this.name, required this.m});
  final String name;
  final J m;
  @override
  Widget build(BuildContext context) {
    final checks = (m['checks_needed'] as num?)?.toInt() ?? 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: HG.subtle, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(name, style: Theme.of(context).textTheme.titleSmall)),
          if (checks > 0) SevChip('high', short: true, label: '$checks to check') else const SevChip('routine', short: true, label: 'No strain'),
        ]),
        const SizedBox(height: 10),
        Text('${m['consented']} of ${m['enrolled']} enrolled consented · ${m['sharing']} sharing now'
            '${(m['unavailable'] as num? ?? 0) > 0 ? ' · ${m['unavailable']} no signal' : ''}',
            style: Theme.of(context).textTheme.bodySmall),
        if (checks > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Check on badge ${(m['check_badges'] as List).join(', ')} now', style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF991B1B))),
          ),
      ]),
    );
  }
}

class _Escalations extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = Theme.of(context).textTheme;
    final open = s.escalations.where((e) => e['status'] != 'closed').toList();
    final closed = s.escalations.where((e) => e['status'] == 'closed').take(5).toList();
    return SectionCard(
      title: 'Symptom reports and escalations',
      subtitle: 'Raised from the worker app ("I feel unwell") or by a co-worker. HeatGuard never clears anyone to resume work.',
      child: s.escalations.isEmpty
          ? const EmptyState(icon: Icons.health_and_safety_outlined, title: 'No symptom reports')
          : Column(children: [
              for (final e in [...open, ...closed]) ...[
                _EscalationRow(e: e),
                const Divider(),
              ],
              if (closed.isNotEmpty) Align(alignment: Alignment.centerLeft, child: Text('Showing the 5 most recent closed cases', style: t.bodySmall)),
            ]),
    );
  }
}

class _EscalationRow extends StatelessWidget {
  const _EscalationRow({required this.e});
  final J e;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = Theme.of(context).textTheme;
    final emergency = e['level'] == 'emergency';
    final status = '${e['status']}';
    final symptoms = jList(e['symptoms']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 120, child: SevChip(emergency ? 'critical' : 'high', short: true, label: emergency ? 'Emergency' : 'First aid')),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${e['crew_name']}${e['badge'] == null ? '' : ' · badge ${e['badge']}'}', style: t.titleSmall),
            const SizedBox(height: 2),
            Text('${humanize(status)} · reported ${fmtTime(e['created_at'])}${e['outcome'] != null ? ' · ${jMap(s.workerCatalog['outcomes'])[e['outcome']] ?? humanize(e['outcome'])}' : ''}',
                style: t.bodySmall),
            if (s.isOhs && symptoms.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Symptoms: ${symptoms.map((x) => x['label']).join(', ')}${(e['note'] ?? '').toString().isEmpty ? '' : ' · "${e['note']}"'}',
                    style: t.bodyMedium),
              )
            else if (e['summary'] != null)
              Padding(padding: const EdgeInsets.only(top: 6), child: Text('${e['summary']}', style: t.bodyMedium)),
          ]),
        ),
        if (status != 'closed')
          Wrap(spacing: 8, children: [
            if (status == 'open')
              OutlinedButton(onPressed: () => _act(context, s, 'acknowledge'), child: const Text('Acknowledge')),
            if (status != 'responding')
              OutlinedButton(onPressed: () => _act(context, s, 'responding'), child: const Text('First aider on the way')),
            if (s.isOhs) FilledButton(onPressed: () => _close(context, s), child: const Text('Record outcome')),
          ]),
      ]),
    );
  }

  Future<void> _act(BuildContext context, AppState s, String action) async {
    final err = await s.run((api) => api.post('/escalations/${e['escalation_id']}', {'action': action}));
    if (context.mounted) showResult(context, err, action == 'acknowledge' ? 'Escalation acknowledged' : 'Marked as responding');
  }

  Future<void> _close(BuildContext context, AppState s) async {
    final outcomes = jMap(s.workerCatalog['outcomes']);
    String? outcome;
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Record the outcome'),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Recorded by the OHS officer or first aider. There is no "cleared to work" option: return to work is a clinical decision outside HeatGuard.'),
              const SizedBox(height: 12),
              RadioGroup<String>(
                groupValue: outcome,
                onChanged: (v) => setD(() => outcome = v),
                child: Column(children: [
                  for (final o in outcomes.entries) RadioListTile<String>(value: o.key, contentPadding: EdgeInsets.zero, title: Text('${o.value}', style: const TextStyle(fontSize: 14))),
                ]),
              ),
              TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (optional)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: outcome == null ? null : () => Navigator.pop(ctx, true), child: const Text('Close escalation')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final err = await s.run((api) => api.post('/escalations/${e['escalation_id']}', {'action': 'close', 'outcome': outcome, 'note': note.text.trim(), 'responder_id': 'ohs-demo'}));
    if (context.mounted) showResult(context, err, 'Outcome recorded');
  }
}

class _WorkersTable extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = Theme.of(context).textTheme;
    String sevFor(String st) => switch (st) { 'ok' => 'routine', 'check' => 'high', 'unavailable' => 'unavailable', _ => 'maintenance' };
    String labelFor(String st) => switch (st) { 'ok' => 'Normal', 'check' => 'Check now', 'unavailable' => 'No signal', _ => 'Not sharing' };
    return SectionCard(
      title: 'Individual signals (OHS only)',
      subtitle: 'Pseudonymous badges. Thresholds: NIOSH 2016 physiological monitoring (heart rate above 180 - age sustained; core temperature 38.5 / 38.0 °C). Core temperature is a device estimate.',
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            SizedBox(width: 90, child: Text('Badge', style: t.labelMedium)),
            Expanded(flex: 2, child: Text('Crew', style: t.labelMedium)),
            Expanded(child: Text('Heart rate', style: t.labelMedium)),
            Expanded(child: Text('Core (est.)', style: t.labelMedium)),
            Expanded(child: Text('Device battery', style: t.labelMedium)),
            SizedBox(width: 120, child: Text('Status', style: t.labelMedium)),
          ]),
        ),
        for (final w in s.workers) ...[
          const Divider(),
          Builder(builder: (context) {
            final sig = jMap(w['signal']);
            final st = '${sig['status']}';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                SizedBox(width: 90, child: Text('${w['badge']}', style: const TextStyle(fontWeight: FontWeight.w600))),
                Expanded(flex: 2, child: Text('${w['crew_name']}', style: t.bodyMedium)),
                Expanded(child: Text(sig['heart_rate'] == null ? '-' : '${sig['heart_rate']} bpm (limit ${sig['hr_limit']})', style: t.bodyMedium)),
                Expanded(child: Text(sig['core_temp_est'] == null ? '-' : '${fmtNum(sig['core_temp_est'])} °C', style: t.bodyMedium)),
                Expanded(child: Text(sig['battery_pct'] == null ? '-' : '${fmtNum(sig['battery_pct'], digits: 0)}%', style: t.bodyMedium)),
                SizedBox(width: 120, child: Align(alignment: Alignment.centerLeft, child: SevChip(sevFor(st), short: true, label: labelFor(st)))),
              ]),
            );
          }),
        ],
      ]),
    );
  }
}
