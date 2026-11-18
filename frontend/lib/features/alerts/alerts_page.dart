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
  String? selectedId;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final list = s.alerts.where((a) => switch (filter) {
          'active' => !a.resolved,
          'unacknowledged' => !a.resolved && !a.acknowledged,
          'resolved' => a.resolved,
          _ => true,
        }).toList()
      ..sort((a, b) {
        if (a.acknowledged != b.acknowledged) return a.acknowledged ? 1 : -1;
        if (a.severityLevel != b.severityLevel) return b.severityLevel.compareTo(a.severityLevel);
        return b.timestamp.compareTo(a.timestamp);
      });
    final wide = MediaQuery.sizeOf(context).width >= 1240;
    final selected = s.alerts.where((a) => a.id == selectedId).firstOrNull ?? (wide && list.isNotEmpty ? list.first : null);

    final listCard = Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 'active', label: Text('Active (${s.alerts.where((a) => !a.resolved).length})')),
              ButtonSegment(value: 'unacknowledged', label: Text('To acknowledge (${s.alerts.where((a) => !a.resolved && !a.acknowledged).length})')),
              const ButtonSegment(value: 'resolved', label: Text('Resolved')),
            ],
            selected: {filter},
            onSelectionChanged: (v) => setState(() => filter = v.first),
          ),
        ),
        const Divider(),
        if (list.isEmpty)
          const EmptyState(icon: Icons.notifications_off_outlined, title: 'Nothing here', message: 'Alerts appear when a crew reaches Caution or data become unavailable.')
        else
          for (var i = 0; i < list.length; i++) ...[
            if (i > 0) const Divider(indent: 16, endIndent: 16),
            _AlertRow(
              a: list[i],
              selected: list[i].id == selected?.id,
              onTap: () {
                setState(() => selectedId = list[i].id);
                if (!wide) _openDialog(context, s, list[i].id);
              },
            ),
          ],
        const SizedBox(height: 8),
      ]),
    );

    if (!wide) return PageBody(children: [listCard]);
    return PageBody(maxWidth: 1400, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 5, child: listCard),
        const SizedBox(width: 24),
        Expanded(
          flex: 6,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: selected == null
                  ? const EmptyState(icon: Icons.touch_app_outlined, title: 'Select an alert')
                  : AlertDetail(alertId: selected.id),
            ),
          ),
        ),
      ]),
    ]);
  }

  void _openDialog(BuildContext context, AppState s, String id) => showDialog(
        context: context,
        builder: (_) => ChangeNotifierProvider.value(
          value: s,
          child: Dialog(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680, maxHeight: 820),
              child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: AlertDetail(alertId: id)),
            ),
          ),
        ),
      );
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.a, required this.selected, required this.onTap});
  final Alert a;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final status = a.resolved
        ? 'Resolved'
        : !a.acknowledged
            ? 'Needs acknowledgement'
            : a.resolution == 'conditions_improving'
                ? 'Improving - ready to review'
                : a.interventionIds.isEmpty
                    ? 'Acknowledged - no action recorded'
                    : 'Action in progress';
    return Material(
      color: selected ? const Color(0xFFF5F8FF) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: Sev.of(a.severity).color, shape: BoxShape.circle)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(a.crewName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  Text(alertTypeLabel(a.type) ?? Sev.of(a.severity).short,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Sev.of(a.severity).ink)),
                ]),
                const SizedBox(height: 2),
                Text('${a.worksiteName.split(' - ').first} · $status', style: t.bodySmall, overflow: TextOverflow.ellipsis),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(fmtTime(a.timestamp).substring(0, 5), style: t.bodySmall),
              if (a.escalation > 0) const Padding(padding: EdgeInsets.only(top: 4), child: Pill('Escalated', color: HG.high)),
            ]),
          ]),
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
    final alert = s.alerts.where((x) => x.id == alertId).firstOrNull;
    if (alert == null) return const EmptyState(icon: Icons.search_off, title: 'Alert not found');
    final t = Theme.of(context).textTheme;
    final ivs = s.interventions.where((i) => alert.interventionIds.contains(i.id)).toList();
    final current = alert.crewId == '__site__' ? null : s.assessmentFor(alert.crewId);
    final recs = alert.recommendations.where((r) => r['priority'] == 'urgent' || r['priority'] == 'required').take(4).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(alert.crewName, style: t.headlineSmall),
      const SizedBox(height: 4),
      Text('${alert.worksiteName} · raised ${fmtDateTime(alert.timestamp)}', style: t.bodySmall),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SevChip(alert.severity, large: true, label: alertTypeLabel(alert.type)),
        if (current != null && current.category != alert.severity) ...[
          Text('now', style: t.bodySmall),
          SevChip(current.category),
        ],
      ]),
      const SizedBox(height: 16),
      Text(alert.explanation, style: t.bodyLarge),
      const SizedBox(height: 20),
      if (!alert.resolved)
        Wrap(spacing: 10, runSpacing: 10, children: [
          if (!alert.acknowledged)
            FilledButton(onPressed: s.dataIsLive ? () => _ack(context, s, alert) : null, child: const Text('Acknowledge')),
          if ((alert.type == 'heat_risk' || alert.type == 'regulatory') && alert.acknowledged)
            FilledButton(
              onPressed: s.dataIsLive ? () => showInterventionForm(context, alert: alert) : null,
              child: const Text('Record intervention'),
            )
          else if (alert.type == 'heat_risk' || alert.type == 'regulatory')
            OutlinedButton(
              onPressed: s.dataIsLive ? () => showInterventionForm(context, alert: alert) : null,
              child: const Text('Record intervention'),
            ),
          if (alert.acknowledged)
            OutlinedButton(onPressed: s.dataIsLive ? () => _resolve(context, s, alert) : null, child: const Text('Resolve')),
        ]),
      if (alert.type == 'escalation')
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text('Handled in Worker health. The clinical outcome is recorded by the OHS role and closes this alert.',
              style: t.bodySmall),
        ),
      if (alert.resolution == 'conditions_improving' && !alert.resolved)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text('Conditions have improved for a sustained period. Review and resolve when appropriate.',
              style: t.bodySmall?.copyWith(color: const Color(0xFF166534))),
        ),
      if (recs.isNotEmpty) ...[
        const SizedBox(height: 24),
        Text('Recommended actions', style: t.titleSmall),
        const SizedBox(height: 8),
        for (var i = 0; i < recs.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 22, child: Text('${i + 1}.', style: const TextStyle(fontWeight: FontWeight.w600))),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '${recs[i]['action']}. ', style: const TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(text: '${recs[i]['detail']}', style: const TextStyle(color: HG.muted)),
                ]), style: const TextStyle(fontSize: 14, height: 1.45)),
              ),
            ]),
          ),
      ],
      const SizedBox(height: 12),
      const Divider(),
      Details(title: 'Why this alert', children: [
        for (final f in alert.factors)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '${f['factor']}: ', style: const TextStyle(fontWeight: FontWeight.w600)),
              TextSpan(text: '${f['detail']}'),
            ]), style: const TextStyle(fontSize: 13.5)),
          ),
      ]),
      Details(title: 'Interventions (${ivs.length})', children: [
        if (ivs.isEmpty) Text('No intervention recorded yet.', style: t.bodySmall),
        for (final i in ivs)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('${i.actionLabel} · ${i.active ? 'in progress' : 'completed'} · started ${fmtTime(i.start)}${i.outcome == null ? '' : ' · ${i.outcome}'}',
                style: const TextStyle(fontSize: 13.5)),
          ),
      ]),
      Details(title: 'History', children: [
        for (final h in alert.history.reversed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 80, child: Text(fmtTime(h['timestamp']), style: t.bodySmall)),
              Expanded(child: Text('${humanize(h['event'])}${'${h['detail']}'.isEmpty ? '' : ' - ${h['detail']}'}', style: const TextStyle(fontSize: 13.5))),
            ]),
          ),
      ]),
      if (alert.resolved) Details(title: 'Resolution', initiallyExpanded: true, children: [Text('${fmtDateTime(alert.resolvedAt)} - ${alert.resolutionNote ?? ''}')]),
    ]);
  }

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
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(improving
                  ? 'Conditions have improved for a sustained period. Briefly describe how this was resolved.'
                  : 'Conditions have not yet improved for long enough. Only resolve if protective measures are in place, and describe them.'),
              const SizedBox(height: 16),
              TextField(controller: note, maxLines: 3, decoration: const InputDecoration(labelText: 'Resolution note')),
              if (!improving)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: override,
                  onChanged: (v) => setD(() => override = v ?? false),
                  title: const Text('Protective measures are in place', style: TextStyle(fontSize: 14)),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: (improving || override) ? () => Navigator.pop(ctx, true) : null, child: const Text('Resolve')),
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
