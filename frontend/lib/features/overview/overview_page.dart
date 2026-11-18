import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../app/shell.dart';
import '../../core/format.dart';
import '../../core/severity.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../widgets/assessment_dialog.dart';
import '../../widgets/common.dart';
import '../../widgets/wbgt_chart.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final nav = context.read<NavController>();
    final c = s.counts;
    final attention = s.assessments.where((a) => Sev.of(a.category).needsAttention).toList()
      ..sort((a, b) => _rank(b).compareTo(_rank(a)));
    final ok = s.assessments.length - attention.length;
    final ws = s.selectedWorksite;
    final sensorsOk = s.worksites.every((w) => w.sensorStatus == 'ok');

    return PageBody(children: [
      _StatusHero(attention: attention, okCount: ok, onReview: () => nav.go(Nav.alerts)),
      ResponsiveGrid(minItemWidth: 200, children: [
        StatCard(label: 'Unacknowledged alerts', value: '${c['unacknowledged_alerts'] ?? 0}',
            color: ((c['unacknowledged_alerts'] as num?) ?? 0) > 0 ? HG.high : null, footnote: '${c['active_alerts'] ?? 0} active in total',
            onTap: () => nav.go(Nav.alerts)),
        StatCard(label: 'Interventions in progress', value: '${c['active_interventions'] ?? 0}',
            footnote: '${c['completed_interventions'] ?? 0} completed', onTap: () => nav.go(Nav.interventions)),
        StatCard(label: 'Crews monitored', value: '${c['active_crews'] ?? 0}',
            footnote: '${c['workers'] ?? 0} workers · ${c['worksites'] ?? 0} sites', onTap: () => nav.go(Nav.crews)),
        StatCard(label: 'Sensors', value: sensorsOk ? 'Normal' : 'Check',
            color: sensorsOk ? HG.routine : HG.high,
            footnote: sensorsOk ? 'All stations reporting' : s.worksites.where((w) => w.sensorStatus != 'ok').map((w) => '${w.name.split(' ').first}: ${w.sensorStatus}').join(', '),
            onTap: () => nav.go(Nav.monitoring)),
      ]),
      TwoColumn(
        leftFlex: 3,
        rightFlex: 2,
        left: SectionCard(
          title: 'Heat stress (WBGT)',
          subtitle: '${ws?.name ?? ''} · last ${s.readings.length} simulated minutes',
          trailing: Text(s.readings.isEmpty || s.readings.last.wbgt == null ? '' : '${fmtNum(s.readings.last.wbgt)} °C',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          child: WbgtChart(readings: s.readings, height: 220),
        ),
        right: SectionCard(
          title: 'All crews',
          trailing: TextButton(onPressed: () => nav.go(Nav.monitoring), child: const Text('Details')),
          child: s.assessments.isEmpty
              ? const EmptyState(icon: Icons.groups_outlined, title: 'No assessments yet')
              : Column(children: [
                  for (final a in s.assessments)
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => showCrewAssessment(context, a.crewId),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(a.crewName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              Text(s.worksiteById(a.worksiteId)?.name.split(' - ').first ?? '', style: Theme.of(context).textTheme.bodySmall),
                            ]),
                          ),
                          SevChip(a.category, short: true),
                        ]),
                      ),
                    ),
                ]),
        ),
      ),
    ]);
  }

  static int _rank(Assessment a) => a.level < 0 ? 25 : a.level * 10; // data unavailable ranks between high and critical
}

class _StatusHero extends StatelessWidget {
  const _StatusHero({required this.attention, required this.okCount, required this.onReview});
  final List<Assessment> attention;
  final int okCount;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final allGood = attention.isEmpty;
    final top = allGood ? Sev.routine : Sev.of(attention.first.category);
    final title = allGood
        ? 'All crews are within heat-stress guidance'
        : '${attention.length} ${attention.length == 1 ? 'crew needs' : 'crews need'} attention';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(border: Border(left: BorderSide(color: top.color, width: 5))),
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(allGood ? Icons.check_circle_outline : Icons.priority_high_rounded, color: top.color, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: t.headlineSmall)),
            if (!allGood) FilledButton(onPressed: onReview, child: const Text('Review alerts')),
          ]),
          Padding(
            padding: const EdgeInsets.only(left: 40, top: 4),
            child: Text(
              allGood
                  ? 'Continue routine monitoring. Keep water and shade available.'
                  : okCount == 0
                      ? 'No crew is currently within guidance.'
                      : '$okCount other ${okCount == 1 ? 'crew is' : 'crews are'} within guidance.',
              style: t.bodyMedium?.copyWith(color: HG.muted),
            ),
          ),
          if (!allGood) ...[
            const SizedBox(height: 16),
            for (final a in attention.take(5))
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => showCrewAssessment(context, a.crewId),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(40, 10, 4, 10),
                  child: Row(children: [
                    SizedBox(width: 150, child: Align(alignment: Alignment.centerLeft, child: SevChip(a.category, short: true))),
                    SizedBox(width: 180, child: Text(a.crewName, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600))),
                    Expanded(child: Text(_reason(a), style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    const Icon(Icons.chevron_right, color: HG.muted),
                  ]),
                ),
              ),
          ],
        ]),
      ),
    );
  }

  String _reason(Assessment a) {
    if (a.level < 0) return 'Data missing or stale - conditions cannot be confirmed';
    final l = a.limit;
    if (l == null) return '';
    final key = a.actions.where((r) => r['priority'] == 'urgent').firstOrNull ??
        a.actions.where((r) => '${r['action']}'.contains('rotation')).firstOrNull ??
        a.actions.firstOrNull;
    final first = key == null ? '' : ' · ${key['action']}';
    return '${fmtNum(a.effectiveWbgt)} °C vs ${l['limit_type']} limit ${fmtNum(l['limit_at_current_regime'])} °C$first';
  }
}
