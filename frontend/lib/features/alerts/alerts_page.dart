import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/severity.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../widgets/common.dart';
import '../interventions/intervention_form.dart';

class AlertsPage extends StatefulWidget {
  const AlertsPage({super.key});
  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  String filter = 'active';
  String? severity;
  String? selectedId;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    var rows = s.alerts.where((a) => switch (filter) {
          'active' => !a.resolved,
          'unacknowledged' => !a.resolved && !a.acknowledged,
          'resolved' => a.resolved,
          _ => true,
        });
    if (severity != null) rows = rows.where((a) => a.severity == severity);
    final list = rows.toList()
      ..sort((a, b) {
        if (a.acknowledged != b.acknowledged) return a.acknowledged ? 1 : -1;
        if (a.severityLevel != b.severityLevel) return b.severityLevel.compareTo(a.severityLevel);
        return b.timestamp.compareTo(a.timestamp);
      });
    Alert? selected;
    for (final a in s.alerts) {
      if (a.id == selectedId) selected = a;
    }
    final wide = MediaQuery.sizeOf(context).width >= 1280;

    final listCard = SectionCard(
      title: 'Alerts (${list.length})',
      subtitle: 'Unacknowledged first, then by severity. Alerts are never cleared automatically.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final f in const ['active', 'unacknowledged', 'resolved', 'all'])
            ChoiceChip(label: Text(humanize(f)), selected: filter == f, onSelected: (_) => setState(() => filter = f)),
          const SizedBox(width: 8),
          DropdownButton<String?>(
            value: severity,
            hint: const Text('All severities'),
            underline: const SizedBox.shrink(),
            items: [
              const DropdownMenuItem(value: null, child: Text('All severities')),
              for (final sv in const ['caution', 'elevated', 'high', 'critical', 'data_unavailable'])
                DropdownMenuItem(value: sv, child: Text(sv == 'data_unavailable' ? 'Data unavailable' : Sev.of(sv).label)),
            ],
            onChanged: (v) => setState(() => severity = v),
          ),
        ]),
        const SizedBox(height: 12),
        if (list.isEmpty)
          const EmptyState(icon: Icons.notifications_off_outlined, title: 'No alerts match this filter')
        else
          for (final a in list)
            _AlertRow(
              a: a,
              selected: a.id == selectedId,
              onTap: () {
                setState(() => selectedId = a.id);
                if (!wide) {
                  showDialog(
                    context: context,
                    builder: (_) => ChangeNotifierProvider.value(
                      value: s,
                      child: Dialog(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 820),
                          child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: AlertDetail(alertId: a.id)),
                        ),
                      ),
                    ),
                  );
                }
              },
            ),
      ]),
    );

    if (!wide) return PageBody(children: [listCard]);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(flex: 5, child: PageBody(children: [listCard])),
      Expanded(
        flex: 6,
        child: ListView(padding: const EdgeInsets.fromLTRB(0, 16, 24, 40), children: [
          SectionCard(
            child: selected == null
                ? const EmptyState(icon: Icons.touch_app_outlined, title: 'Select an alert', message: 'Details, explanation, history and actions appear here.')
                : AlertDetail(alertId: selected.id),
          ),
        ]),
      ),
    ]);
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.a, required this.selected, required this.onTap});
  final Alert a;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final sev = Sev.of(a.severity);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? HG.primary.withValues(alpha: 0.06) : HG.bg,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: sev.color, width: 4)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                SevChip(a.severity, label: a.type == 'data_quality' ? 'Data unavailable' : null),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${a.crewName} · ${a.worksiteName}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13), overflow: TextOverflow.ellipsis),
                ),
                Text(fmtTime(a.timestamp), style: Theme.of(context).textTheme.bodySmall),
              ]),
              const SizedBox(height: 6),
              Text(a.explanation, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: HG.muted)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                Pill(a.acknowledged ? 'Acknowledged' : 'Unacknowledged', color: a.acknowledged ? HG.routine : HG.high,
                    icon: a.acknowledged ? Icons.check : Icons.mark_email_unread_outlined),
                Pill(humanize(a.resolution), color: a.resolution == 'conditions_improving' ? HG.routine : (a.resolved ? HG.muted : HG.elevated)),
                if (a.escalation > 0) Pill('Escalated L${a.escalation}', color: HG.critical, icon: Icons.priority_high),
                if (a.interventionIds.isNotEmpty) Pill('${a.interventionIds.length} intervention(s)', color: HG.primary, icon: Icons.healing),
                if (a.duplicates > 0) Pill('${a.duplicates} repeats suppressed', color: HG.muted),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class AlertDetail extends StatelessWidget {
  const AlertDetail({super.key, required this.alertId});
  final String alertId;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    Alert? a;
    for (final x in s.alerts) {
      if (x.id == alertId) a = x;
    }
    if (a == null) return const EmptyState(icon: Icons.search_off, title: 'Alert not found');
    final alert = a;
    final t = Theme.of(context).textTheme;
    final ivs = s.interventions.where((i) => alert.interventionIds.contains(i.id)).toList();
    final current = alert.crewId == '__site__' ? null : s.assessmentFor(alert.crewId);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        SevChip(alert.severity, large: true, label: alert.type == 'data_quality' ? 'Data unavailable' : null),
        const SizedBox(width: 10),
        Expanded(child: Text(alert.crewName, style: t.titleLarge)),
        const SimulatedBadge(),
      ]),
      const SizedBox(height: 6),
      Text('${alert.worksiteName} · raised ${fmtDateTime(alert.timestamp)} · ${humanize(alert.type)} · ID ${alert.id}', style: t.bodySmall),
      if (current != null) ...[
        const SizedBox(height: 8),
        Row(children: [
          const Text('Current assessment: ', style: TextStyle(fontSize: 12.5)),
          SevChip(current.category),
          if (alert.resolution == 'conditions_improving')
            const Padding(padding: EdgeInsets.only(left: 8), child: Pill('Sustained improvement - ready for review', color: HG.routine)),
        ]),
      ],
      const SizedBox(height: 14),
      Text('Why this alert', style: t.titleSmall),
      const SizedBox(height: 4),
      Text(alert.explanation),
      const SizedBox(height: 14),
      Wrap(spacing: 10, runSpacing: 10, children: [
        if (!alert.acknowledged && !alert.resolved)
          FilledButton.icon(
            onPressed: s.dataIsLive ? () => _ack(context, s, alert) : null,
            icon: const Icon(Icons.done, size: 18),
            label: const Text('Acknowledge'),
          ),
        if (!alert.resolved)
          FilledButton.tonalIcon(
            onPressed: s.dataIsLive ? () => showInterventionForm(context, alert: alert) : null,
            icon: const Icon(Icons.healing, size: 18),
            label: const Text('Record intervention'),
          ),
        if (!alert.resolved)
          OutlinedButton.icon(
            onPressed: s.dataIsLive && alert.acknowledged ? () => _resolve(context, s, alert) : null,
            icon: const Icon(Icons.task_alt, size: 18),
            label: Text(alert.acknowledged ? 'Resolve' : 'Resolve (acknowledge first)'),
          ),
      ]),
      const SizedBox(height: 18),
      _section(context, 'Contributing factors', [
        for (final f in alert.factors) Text('• ${f['factor']}: ${f['detail']}', style: const TextStyle(fontSize: 12.5)),
      ]),
      _section(context, 'Recommended protective actions', [
        for (final r in alert.recommendations)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '[${'${r['priority']}'.toUpperCase()}] ', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11, color: HG.high)),
              TextSpan(text: '${r['action']}: ', style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: '${r['detail']}'),
            ]), style: const TextStyle(fontSize: 12.5)),
          ),
      ]),
      _section(context, 'Interventions', [
        if (ivs.isEmpty) Text('No intervention recorded yet.', style: t.bodySmall),
        for (final i in ivs)
          Text('• ${i.actionLabel} - ${i.status} (started ${fmtTime(i.start)})${i.outcome == null ? '' : ' - ${i.outcome}'}',
              style: const TextStyle(fontSize: 12.5)),
      ]),
      _section(context, 'History', [
        for (final h in alert.history.reversed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 70, child: Text(fmtTime(h['timestamp']), style: t.bodySmall)),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: humanize(h['event']), style: const TextStyle(fontWeight: FontWeight.w700)),
                  if ('${h['detail']}'.isNotEmpty) TextSpan(text: ' - ${h['detail']}'),
                  if (h['actor'] != 'system') TextSpan(text: '  (${h['actor']})', style: const TextStyle(color: HG.muted)),
                ]), style: const TextStyle(fontSize: 12.5)),
              ),
            ]),
          ),
      ]),
      if (alert.resolved) _section(context, 'Resolution', [Text('${fmtDateTime(alert.resolvedAt)}: ${alert.resolutionNote ?? ''}')]),
    ]);
  }

  Widget _section(BuildContext context, String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          ...children,
        ]),
      );

  Future<void> _ack(BuildContext context, AppState s, Alert a) async {
    final err = await s.run((api) => api.post('/alerts/${a.id}/acknowledge', {'supervisor_id': 'supervisor-demo'}));
    if (context.mounted) showResult(context, err, 'Alert acknowledged');
  }

  Future<void> _resolve(BuildContext context, AppState s, Alert a) async {
    final note = TextEditingController();
    final improving = a.resolution == 'conditions_improving';
    bool override = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Resolve alert'),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                improving
                    ? 'Conditions have shown sustained improvement. Record how the situation was resolved.'
                    : 'Conditions have NOT shown sustained improvement. Resolve only if protective measures are in place '
                        '(e.g. work stopped, crew relocated) and explain them below.',
                style: TextStyle(color: improving ? HG.text : HG.high),
              ),
              const SizedBox(height: 12),
              TextField(controller: note, maxLines: 3, decoration: const InputDecoration(labelText: 'Resolution note (required)')),
              if (!improving)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: override,
                  onChanged: (v) => setD(() => override = v ?? false),
                  title: const Text('I confirm protective measures are in place despite current conditions', style: TextStyle(fontSize: 13)),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: (improving || override) ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Resolve alert'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final err = await s.run((api) => api.post('/alerts/${a.id}/resolve', {
          'supervisor_id': 'supervisor-demo',
          'note': note.text.trim().isEmpty ? 'Resolved by supervisor' : note.text.trim(),
          'override_active_conditions': override,
        }));
    if (context.mounted) showResult(context, err, 'Alert resolved');
  }
}
