import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../app/shell.dart';
import '../../core/format.dart';
import '../../core/severity.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/wbgt_chart.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final nav = context.read<NavController>();
    final c = s.counts;
    final worst = s.overview['highest_concern'] == null ? null : Assessment(jMap(s.overview['highest_concern']));
    final ws = s.selectedWorksite;
    final latestAt = s.worksites.map((w) => w.status['last_reading_at'] as String?).whereType<String>().fold<String?>(
        null, (a, b) => a == null || b.compareTo(a) > 0 ? b : a);
    final siteStatuses = s.worksites.map((w) => w.sensorStatus).toList();
    final connectivity = !s.dataIsLive
        ? 'offline'
        : siteStatuses.every((x) => x == 'ok')
            ? 'ok'
            : siteStatuses.any((x) => x == 'stale' || x == 'offline')
                ? 'stale'
                : 'degraded';

    return PageBody(children: [
      ResponsiveGrid(minItemWidth: 230, children: [
        StatCard(label: 'Active worksites', value: '${c['worksites'] ?? 0}', icon: Icons.location_city, footnote: 'Each with one virtual station'),
        StatCard(label: 'Active crews', value: '${c['active_crews'] ?? 0}', icon: Icons.groups, footnote: '${c['workers'] ?? 0} workers (crew-level only)', onTap: () => nav.go(2)),
        StatCard(
          label: 'Highest current concern',
          value: worst == null ? '-' : Sev.of(worst.category).label,
          icon: Sev.of(worst?.category).icon,
          color: Sev.of(worst?.category).color,
          footnote: worst == null ? 'No assessments yet' : '${worst.crewName} · ${worst.effectiveWbgt == null ? 'data unavailable' : 'eff. WBGT ${fmtNum(worst.effectiveWbgt)} °C'}',
          onTap: () => nav.go(1),
        ),
        StatCard(label: 'Active alerts', value: '${c['active_alerts'] ?? 0}', icon: Icons.notifications_active, color: HG.elevated,
            footnote: '${c['escalated_alerts'] ?? 0} escalated', onTap: () => nav.go(3)),
        StatCard(label: 'Unacknowledged', value: '${c['unacknowledged_alerts'] ?? 0}', icon: Icons.mark_email_unread_outlined,
            color: ((c['unacknowledged_alerts'] as num?) ?? 0) > 0 ? HG.high : HG.routine, footnote: 'Require supervisor action', onTap: () => nav.go(3)),
        StatCard(label: 'Interventions', value: '${c['completed_interventions'] ?? 0} done', icon: Icons.healing, color: HG.routine,
            footnote: '${c['active_interventions'] ?? 0} in progress', onTap: () => nav.go(4)),
        StatCard(label: 'Latest sensor update', value: ago(latestAt), icon: Icons.sensors, color: HG.simulated, footnote: fmtDateTime(latestAt)),
        StatCard(
          label: 'Connectivity',
          value: humanize(connectivity),
          icon: connectivity == 'ok' ? Icons.wifi : Icons.wifi_off,
          color: StatusDot.colorFor(connectivity),
          footnote: s.worksites.map((w) => '${w.name.split(' ').first}: ${w.sensorStatus}').join(' · '),
        ),
      ]),
      LayoutBuilder(builder: (context, box) {
        final chart = SectionCard(
          title: 'WBGT trend - ${ws?.name ?? ''}',
          subtitle: 'Last ${s.readings.length} simulated minutes · 60-min mean ${fmtNum(ws?.rollingMean)} °C',
          trailing: const SimulatedBadge(),
          child: WbgtChart(readings: s.readings, height: 240),
        );
        final dist = SectionCard(title: 'Alert distribution', subtitle: 'All alerts by peak severity', child: _AlertBars(dist: jMap(s.overview['alert_distribution'])));
        if (box.maxWidth < 980) return Column(children: [chart, const SizedBox(height: 16), dist]);
        return IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(flex: 2, child: chart),
            const SizedBox(width: 16),
            Expanded(child: dist),
          ]),
        );
      }),
      LayoutBuilder(builder: (context, box) {
        final crews = SectionCard(title: 'Crew status summary', subtitle: 'Latest assessment per crew', child: _CrewTable(s: s));
        final recent = SectionCard(
          title: 'Recent alerts',
          trailing: TextButton(onPressed: () => nav.go(3), child: const Text('View all')),
          child: _RecentAlerts(alerts: jList(s.overview['recent_alerts']).map(Alert.new).toList()),
        );
        if (box.maxWidth < 980) return Column(children: [crews, const SizedBox(height: 16), recent]);
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3, child: crews),
          const SizedBox(width: 16),
          Expanded(flex: 2, child: recent),
        ]);
      }),
      SectionCard(
        title: 'Environmental monitoring history',
        subtitle: 'Sensor, connectivity and simulation events detected by the backend',
        child: _Events(events: jList(s.overview['recent_events'])),
      ),
    ]);
  }
}

class _AlertBars extends StatelessWidget {
  const _AlertBars({required this.dist});
  final J dist;
  @override
  Widget build(BuildContext context) {
    final keys = ['caution', 'elevated', 'high', 'critical', 'data_unavailable'];
    final labels = ['Caution', 'Elevated', 'High', 'Critical', 'No data'];
    final values = [for (final k in keys) ((dist[k] as num?) ?? 0).toDouble()];
    final maxV = values.fold<double>(0, (a, b) => a > b ? a : b);
    if (maxV == 0) return const EmptyState(icon: Icons.notifications_none, title: 'No alerts yet');
    return SizedBox(
      height: 240,
      child: BarChart(
        BarChartData(
          maxY: maxV + 1,
          gridData: FlGridData(drawVerticalLine: false, getDrawingHorizontalLine: (_) => const FlLine(color: HG.border, strokeWidth: 1)),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
                sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: (maxV / 4).ceilToDouble().clamp(1, 1000),
                    getTitlesWidget: (v, m) => Text(v.toInt().toString(), style: const TextStyle(fontSize: 11, color: HG.muted)))),
            bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, m) => Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(labels[v.toInt()], style: const TextStyle(fontSize: 10.5, color: HG.muted))))),
          ),
          barGroups: [
            for (var i = 0; i < keys.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(toY: values[i], width: 22, color: Sev.of(keys[i]).color, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
              ]),
          ],
        ),
        duration: Duration.zero,
      ),
    );
  }
}

class _CrewTable extends StatelessWidget {
  const _CrewTable({required this.s});
  final AppState s;
  @override
  Widget build(BuildContext context) {
    if (s.assessments.isEmpty) return const EmptyState(icon: Icons.groups_outlined, title: 'No crew assessments yet');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 36,
        dataRowMinHeight: 40,
        dataRowMaxHeight: 48,
        columnSpacing: 22,
        headingTextStyle: Theme.of(context).textTheme.labelSmall,
        columns: const [
          DataColumn(label: Text('CREW')),
          DataColumn(label: Text('SITE / ZONE')),
          DataColumn(label: Text('STATUS')),
          DataColumn(label: Text('EFF. WBGT'), numeric: true),
          DataColumn(label: Text('LIMIT'), numeric: true),
          DataColumn(label: Text('WORKLOAD')),
          DataColumn(label: Text('ACCLIMATIZATION')),
        ],
        rows: [
          for (final a in s.assessments)
            DataRow(cells: [
              DataCell(Text(a.crewName, style: const TextStyle(fontWeight: FontWeight.w600))),
              DataCell(Text('${s.worksiteById(a.worksiteId)?.name.split(' ').take(2).join(' ') ?? ''} · ${a.crew?.zone ?? ''}')),
              DataCell(SevChip(a.category)),
              DataCell(Text(fmtNum(a.effectiveWbgt))),
              DataCell(Text(a.limit == null ? '-' : '${a.limit!['limit_type']} ${fmtNum(a.limit!['limit_at_current_regime'])}')),
              DataCell(Text(humanize(a.crew?.workload))),
              DataCell(Text(humanize(a.crew?.acclimatization),
                  style: TextStyle(color: a.crew?.acclimatization == 'acclimatized' ? HG.text : HG.elevated, fontWeight: FontWeight.w600))),
            ]),
        ],
      ),
    );
  }
}

class _RecentAlerts extends StatelessWidget {
  const _RecentAlerts({required this.alerts});
  final List<Alert> alerts;
  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) return const EmptyState(icon: Icons.notifications_none, title: 'No alerts', message: 'Alerts appear when an assessment reaches Caution or data become unavailable.');
    return Column(children: [
      for (final a in alerts)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: Sev.of(a.severity).color, width: 3)),
            color: HG.bg,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              SevChip(a.severity),
              const SizedBox(width: 8),
              Expanded(child: Text(a.crewName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13), overflow: TextOverflow.ellipsis)),
              Text(ago(a.updatedAt), style: Theme.of(context).textTheme.bodySmall),
            ]),
            const SizedBox(height: 5),
            Text(a.explanation, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: HG.muted)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, children: [
              Pill(a.acknowledged ? 'Acknowledged' : 'Unacknowledged', color: a.acknowledged ? HG.routine : HG.high),
              Pill(humanize(a.resolution), color: a.resolved ? HG.routine : HG.muted),
              if (a.escalation > 0) Pill('Escalated L${a.escalation}', color: HG.critical, icon: Icons.priority_high),
            ]),
          ]),
        ),
    ]);
  }
}

class _Events extends StatelessWidget {
  const _Events({required this.events});
  final List<J> events;
  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const EmptyState(icon: Icons.history, title: 'No events recorded yet');
    IconData icon(String t) => t.contains('fault') || t.contains('failure')
        ? Icons.sensors_off
        : t.contains('stale') || t.contains('outage')
            ? Icons.cloud_off
            : t.contains('restored') || t.contains('restore')
                ? Icons.check_circle_outline
                : Icons.info_outline;
    Color color(String t) => t.contains('fault') || t.contains('failure') || t.contains('stale') || t.contains('outage')
        ? HG.high
        : t.contains('restor')
            ? HG.routine
            : HG.muted;
    return Column(children: [
      for (final e in events)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon(e['type']), size: 16, color: color(e['type'])),
            const SizedBox(width: 10),
            SizedBox(width: 74, child: Text(fmtTime(e['timestamp']), style: Theme.of(context).textTheme.bodySmall)),
            SizedBox(width: 190, child: Text(humanize(e['type']), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5))),
            Expanded(child: Text('${e['detail']}', style: const TextStyle(fontSize: 12.5))),
          ]),
        ),
    ]);
  }
}
