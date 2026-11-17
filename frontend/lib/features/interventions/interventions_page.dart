import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../widgets/common.dart';
import 'intervention_form.dart';

class InterventionsPage extends StatelessWidget {
  const InterventionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final active = s.interventions.where((i) => i.active).toList();
    final done = s.interventions.where((i) => !i.active).toList();
    final unresolved = s.activeAlerts.where((a) => a.type == 'heat_risk' && a.interventionIds.isEmpty).toList();
    return PageBody(children: [
      ResponsiveGrid(minItemWidth: 220, children: [
        StatCard(label: 'Active interventions', value: '${active.length}', icon: Icons.healing, color: HG.elevated),
        StatCard(label: 'Completed', value: '${done.length}', icon: Icons.task_alt, color: HG.routine),
        StatCard(
          label: 'Completion rate',
          value: s.interventions.isEmpty ? '-' : pct(done.length / s.interventions.length),
          icon: Icons.percent,
        ),
        StatCard(
          label: 'Heat alerts without action',
          value: '${unresolved.length}',
          icon: Icons.report_problem_outlined,
          color: unresolved.isEmpty ? HG.routine : HG.high,
          footnote: 'Unresolved alerts with no intervention',
        ),
      ]),
      SectionCard(
        title: 'Active interventions',
        subtitle: 'Follow-up assessments are logged automatically whenever the crew\'s category changes.',
        trailing: FilledButton.icon(
          onPressed: s.dataIsLive ? () => showInterventionForm(context) : null,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Record intervention'),
        ),
        child: active.isEmpty
            ? const EmptyState(icon: Icons.healing_outlined, title: 'No active interventions', message: 'Record one from an alert or with the button above.')
            : Column(children: [for (final i in active) _InterventionCard(i: i)]),
      ),
      SectionCard(
        title: 'Intervention history',
        child: done.isEmpty
            ? const EmptyState(icon: Icons.history, title: 'No completed interventions yet')
            : Column(children: [for (final i in done) _InterventionCard(i: i)]),
      ),
    ]);
  }
}

class _InterventionCard extends StatelessWidget {
  const _InterventionCard({required this.i});
  final Intervention i;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = Theme.of(context).textTheme;
    final changes = i.contextChanges;
    final base = i.baseline;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border.all(color: HG.border), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(i.active ? Icons.timelapse : Icons.task_alt, color: i.active ? HG.elevated : HG.routine, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('${i.actionLabel} · ${i.crewName}', style: t.titleSmall)),
          if (i.active)
            FilledButton.tonal(
              onPressed: s.dataIsLive ? () => _complete(context, s) : null,
              child: const Text('Mark completed'),
            ),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 16, runSpacing: 4, children: [
          Text('Started ${fmtDateTime(i.start)}', style: t.bodySmall),
          if (i.end != null) Text('Ended ${fmtDateTime(i.end)}', style: t.bodySmall),
          if (i.plannedMinutes != null) Text('Planned ${i.plannedMinutes} min', style: t.bodySmall),
          Text('By ${i.supervisor}', style: t.bodySmall),
          Text(i.alertId == null ? 'No linked alert' : 'Alert ${i.alertId}', style: t.bodySmall),
        ]),
        if (changes.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: [
            for (final e in changes.entries)
              Pill('${humanize(e.key)}: ${_v(jMap(e.value)['from'])} → ${_v(jMap(e.value)['to'])}', color: HG.primary, icon: Icons.tune),
          ]),
        ],
        if (i.notes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Notes: ${i.notes}', style: const TextStyle(fontSize: 12.5))),
        const SizedBox(height: 10),
        Text('Assessment timeline', style: t.labelSmall),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            if (base != null) _step(context, 'Before', base),
            for (final f in i.followUps) ...[
              const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_forward, size: 16, color: HG.muted)),
              _step(context, fmtTime(f['timestamp']), f),
            ],
          ]),
        ),
        if (i.outcome != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Outcome: ${i.outcome}${i.completionNotes.isNotEmpty ? ' - ${i.completionNotes}' : ''}',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: i.outcome!.startsWith('improved') ? HG.routine : (i.outcome!.startsWith('worsened') ? HG.high : HG.text))),
          ),
      ]),
    );
  }

  String _v(dynamic v) => v == null ? '-' : (regimeLabels[v] ?? humanize('$v'));

  Widget _step(BuildContext context, String label, J f) => Tooltip(
        message: '${f['note']}${f['effective_wbgt'] == null ? '' : ' · eff. WBGT ${fmtNum(f['effective_wbgt'])} °C'}',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 10.5, color: HG.muted)),
          const SizedBox(height: 3),
          SevChip(f['risk_category']),
        ]),
      );

  Future<void> _complete(BuildContext context, AppState s) async {
    final notes = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Complete: ${i.actionLabel}'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('A follow-up assessment will be recorded now. Completing an intervention does not resolve the alert '
                'and does not clear any worker to resume work.'),
            const SizedBox(height: 12),
            TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Completion notes')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Complete')),
        ],
      ),
    );
    if (ok != true) return;
    final err = await s.run((api) => api.post('/interventions/${i.id}/complete', {'notes': notes.text.trim(), 'supervisor_id': 'supervisor-demo'}));
    if (context.mounted) showResult(context, err, 'Intervention completed - follow-up assessment recorded');
  }
}
