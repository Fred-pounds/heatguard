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
    final noAction = s.activeAlerts.where((a) => a.type == 'heat_risk' && a.interventionIds.isEmpty).length;
    return DefaultTabController(
      length: 2,
      child: PageBody(children: [
        Row(children: [
          Expanded(
            child: Text(
              noAction == 0 ? 'Every active heat alert has a recorded action.' : '$noAction active heat alert(s) have no recorded action yet.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: noAction == 0 ? HG.muted : const Color(0xFF991B1B)),
            ),
          ),
          FilledButton.icon(
            onPressed: s.dataIsLive ? () => showInterventionForm(context) : null,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Record intervention'),
          ),
        ]),
        Card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TabBar(isScrollable: true, padding: const EdgeInsets.symmetric(horizontal: 8), tabs: [
              Tab(text: 'In progress (${active.length})'),
              Tab(text: 'Completed (${done.length})'),
            ]),
            SizedBox(
              height: 640,
              child: TabBarView(children: [_List(items: active, empty: 'No interventions in progress'), _List(items: done, empty: 'No completed interventions yet')]),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.items, required this.empty});
  final List<Intervention> items;
  final String empty;
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return EmptyState(icon: Icons.healing_outlined, title: empty, message: 'Record one from an alert or with the button above.');
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (_, i) => _Row(i: items[i]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.i});
  final Intervention i;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = Theme.of(context).textTheme;
    final base = i.baseline;
    final latest = i.followUps.isEmpty ? null : i.followUps.last;
    final changes = i.contextChanges.entries
        .map((e) => '${humanize(e.key)}: ${_v(jMap(e.value)['from'])} → ${_v(jMap(e.value)['to'])}')
        .join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${i.actionLabel} · ${i.crewName}', style: t.titleSmall?.copyWith(fontSize: 15)),
            const SizedBox(height: 4),
            Text('Started ${fmtDateTime(i.start)}${i.end == null ? '' : ' · ended ${fmtDateTime(i.end)}'} · ${i.supervisor}', style: t.bodySmall),
            if (changes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(changes, style: t.bodySmall)),
            if (i.notes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(i.notes, style: t.bodyMedium)),
            const SizedBox(height: 10),
            Row(children: [
              Text('Before', style: t.labelSmall),
              const SizedBox(width: 8),
              SevChip(base?['risk_category'], short: true),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Icon(Icons.arrow_forward, size: 16, color: HG.muted)),
              Text(i.active ? 'Now' : 'After', style: t.labelSmall),
              const SizedBox(width: 8),
              SevChip(latest?['risk_category'] ?? s.assessmentFor(i.crewId)?.category, short: true),
            ]),
          ]),
        ),
        if (i.active)
          OutlinedButton(onPressed: s.dataIsLive ? () => _complete(context, s) : null, child: const Text('Mark completed'))
        else if (i.outcome != null)
          Text(humanize(i.outcome!.split(':').first),
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: i.outcome!.startsWith('improved') ? const Color(0xFF166534) : (i.outcome!.startsWith('worsened') ? HG.high : HG.muted))),
      ]),
    );
  }

  String _v(dynamic v) => v == null ? '-' : (regimeLabels[v] ?? humanize('$v'));

  Future<void> _complete(BuildContext context, AppState s) async {
    final notes = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Complete ${i.actionLabel.toLowerCase()}?'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('A follow-up assessment is recorded now. This does not resolve the alert or clear anyone to resume work.'),
            const SizedBox(height: 16),
            TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes (optional)')),
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
    if (context.mounted) showResult(context, err, 'Intervention completed');
  }
}
