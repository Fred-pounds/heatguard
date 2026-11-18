import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../app/shell.dart';
import '../../core/format.dart';
import '../../core/severity.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/app_state.dart';
import '../../services/file_download.dart';
import '../../widgets/common.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  J? summary;
  J? evaluation;
  String? error;
  bool loading = false;
  bool evaluating = false;
  DateTime? fetchedAt;
  int tab = 0;

  Future<void> _load() async {
    if (loading) return;
    setState(() => loading = true);
    final api = context.read<AppState>().api;
    try {
      final r = await Future.wait([api.get('/reports/summary'), api.get('/evaluation')]);
      summary = jMap(r[0]);
      final ev = jMap(r[1]);
      evaluation = ev['summary'] == null ? null : ev;
      error = null;
      fetchedAt = DateTime.now();
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _runEvaluation() async {
    setState(() => evaluating = true);
    try {
      evaluation = jMap(await context.read<AppState>().api.post('/evaluation/run'));
      if (mounted) showResult(context, null, 'Scenario evaluation completed');
      await _load();
    } catch (e) {
      if (mounted) showResult(context, '$e', '');
    }
    if (mounted) setState(() => evaluating = false);
  }

  Future<void> _export(String kind) async {
    try {
      final text = await context.read<AppState>().api.getText('/reports/export', {'kind': kind});
      downloadTextFile('heatguard_$kind.csv', text);
      if (mounted) showResult(context, null, 'Exported heatguard_$kind.csv');
    } catch (e) {
      if (mounted) showResult(context, '$e', '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavController>();
    if (nav.index == 6 && (fetchedAt == null || DateTime.now().difference(fetchedAt!) > const Duration(seconds: 8)) && !loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    final s = summary;
    final t = Theme.of(context).textTheme;
    return PageBody(children: [
      Row(children: [
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 0, label: Text('Operations')),
            ButtonSegment(value: 1, label: Text('Evaluation')),
            ButtonSegment(value: 2, label: Text('Export')),
          ],
          selected: {tab},
          onSelectionChanged: (v) => setState(() => tab = v.first),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Refresh',
          onPressed: _load,
          icon: loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
        ),
      ]),
      Text('All figures come from simulated data and demo operations. They are not field measurements and do not show real-world prevention outcomes.',
          style: t.bodySmall),
      if (tab == 0) ...[
        if (error != null && s == null) SectionCard(child: EmptyState(icon: Icons.cloud_off, title: 'Report unavailable', message: error)),
        if (s == null && error == null) const SizedBox(height: 200, child: LoadingState(message: 'Loading report...')),
        if (s != null) ..._metrics(s),
      ],
      if (tab == 1) _evaluationSection(),
      if (tab == 2)
        SectionCard(
          title: 'Download CSV',
          subtitle: 'Every file is labelled as simulated data in its header and data_origin column.',
          child: Column(children: [
            for (final k in const {
              'summary': 'Key metrics',
              'readings': 'Sensor readings',
              'assessments': 'Assessments',
              'alerts': 'Alerts',
              'interventions': 'Interventions',
              'evaluation': 'Evaluation results',
            }.entries) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(k.value, style: t.titleSmall),
                subtitle: Text('heatguard_${k.key}.csv', style: t.bodySmall),
                trailing: OutlinedButton.icon(onPressed: () => _export(k.key), icon: const Icon(Icons.download, size: 18), label: const Text('Download')),
              ),
              if (k.key != 'evaluation') const Divider(),
            ],
          ]),
        ),
    ]);
  }

  List<Widget> _metrics(J s) {
    final al = jMap(s['alerts']);
    final iv = jMap(s['interventions']);
    final asm = jMap(s['assessments']);
    final con = jMap(s['connectivity']);
    final env = jMap(s['environment']);
    final ack = jMap(al['acknowledgement_time_seconds']);
    final rec = jMap(con['recovery_time_seconds']);
    return [
      ResponsiveGrid(minItemWidth: 300, children: [
        StatCard(label: 'Alerts raised', value: '${al['total'] ?? 0}', footnote: '${al['duplicates_suppressed']} duplicate repeats suppressed'),
        StatCard(label: 'Median ack. time', value: fmtDuration(ack['median'] as num?), 
            footnote: '${ack['count']} acknowledged · max ${fmtDuration(ack['max'] as num?)}'),
        StatCard(label: 'Unresolved alerts', value: '${al['unresolved'] ?? 0}', color: ((al['unresolved'] as num?) ?? 0) > 0 ? HG.high : null,
            footnote: '${al['unacknowledged']} unacknowledged · ${al['escalated']} escalated'),
        StatCard(label: 'Intervention completion', value: pct(iv['completion_rate']), 
            footnote: '${iv['completed']}/${iv['total']} · coverage of heat alerts ${pct(iv['heat_alert_intervention_coverage'])}'),
        StatCard(label: 'Assessment completeness', value: pct(asm['completeness']), footnote: '${asm['stored']} stored assessments'),
        StatCard(label: 'Connectivity recovery', value: fmtDuration(rec['median'] as num?), 
            footnote: '${con['data_flow_recoveries']} recoveries · ${con['pending_database_writes']} writes pending'),
      ]),
      SectionCard(
        title: 'Environmental trends & sensor data quality',
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingTextStyle: Theme.of(context).textTheme.labelSmall,
            columns: const [
              DataColumn(label: Text('WORKSITE')),
              DataColumn(label: Text('READINGS'), numeric: true),
              DataColumn(label: Text('WBGT MIN / MEAN / MAX')),
              DataColumn(label: Text('SENSOR AVAILABILITY'), numeric: true),
              DataColumn(label: Text('DELIVERY RATIO'), numeric: true),
              DataColumn(label: Text('MISSING-DATA FREQ.'), numeric: true),
              DataColumn(label: Text('LATE-SYNCED'), numeric: true),
              DataColumn(label: Text('ISSUES BY FIELD')),
            ],
            rows: [
              for (final e in env.values.map(jMap))
                DataRow(cells: [
                  DataCell(Text('${e['worksite_name']}')),
                  DataCell(Text('${e['readings']}')),
                  DataCell(Text('${fmtNum(jMap(e['wbgt'])['min'])} / ${fmtNum(jMap(e['wbgt'])['mean'])} / ${fmtNum(jMap(e['wbgt'])['max'])} °C')),
                  DataCell(Text(pct(e['sensor_availability']))),
                  DataCell(Text(pct(e['delivery_ratio']))),
                  DataCell(Text(pct(e['missing_data_frequency']))),
                  DataCell(Text('${e['late_synchronised_readings']}')),
                  DataCell(Text(jMap(e['field_issue_counts']).entries.map((x) => '${humanize(x.key)}: ${x.value}').join(', ').ifEmpty('none'))),
                ]),
            ],
          ),
        ),
      ),
      LayoutBuilder(builder: (context, box) {
        final a = SectionCard(title: 'Alerts by peak severity', child: _bars(jMap(al['by_peak_severity'])));
        final b = SectionCard(
          title: 'Interventions',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('By type', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
            if (jMap(iv['by_type']).isEmpty) const Text('None yet', style: TextStyle(color: HG.muted)),
            for (final e in jMap(iv['by_type']).entries) KV(e.key, '${e.value}', width: 220),
            const SizedBox(height: 10),
            const Text('Outcomes (category at completion vs. start)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
            if (jMap(iv['outcomes']).isEmpty) const Text('No completed interventions', style: TextStyle(color: HG.muted)),
            for (final e in jMap(iv['outcomes']).entries) KV(humanize(e.key), '${e.value}', width: 220),
            const SizedBox(height: 6),
            const Text('Outcomes reflect simulated conditions and context changes, not health outcomes.', style: TextStyle(fontSize: 11, color: HG.muted)),
          ]),
        );
        if (box.maxWidth < 900) return Column(children: [a, const SizedBox(height: 16), b]);
        return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: a), const SizedBox(width: 16), Expanded(child: b)]));
      }),
    ];
  }

  Widget _bars(J m) {
    final keys = ['caution', 'elevated', 'high', 'critical', 'data_unavailable'];
    final vals = [for (final k in keys) ((m[k] as num?) ?? 0).toDouble()];
    final maxV = vals.fold<double>(0, (a, b) => a > b ? a : b);
    if (maxV == 0) return const EmptyState(icon: Icons.bar_chart, title: 'No alerts yet');
    return SizedBox(
      height: 200,
      child: BarChart(BarChartData(
        maxY: maxV + 1,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(drawVerticalLine: false, getDrawingHorizontalLine: (_) => const FlLine(color: HG.border, strokeWidth: 1)),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 26, interval: (maxV / 4).ceilToDouble().clamp(1, 1e6),
              getTitlesWidget: (v, _) => Text('${v.toInt()}', style: const TextStyle(fontSize: 11, color: HG.muted)))),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true,
              getTitlesWidget: (v, _) => Text(['Caution', 'Elevated', 'High', 'Critical', 'No data'][v.toInt()], style: const TextStyle(fontSize: 10.5, color: HG.muted)))),
        ),
        barGroups: [
          for (var i = 0; i < keys.length; i++)
            BarChartGroupData(x: i, barRods: [BarChartRodData(toY: vals[i], width: 22, color: Sev.of(keys[i]).color, borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))]),
        ],
      ), duration: Duration.zero),
    );
  }

  Widget _evaluationSection() {
    final ev = evaluation;
    final sum = ev == null ? null : jMap(ev['summary']);
    return SectionCard(
      title: 'Scenario-based evaluation',
      subtitle: 'Repeatable synthetic test cases run through the live pipeline and compared with the configured rules applied to noise-free ground truth.',
      trailing: FilledButton.icon(
        onPressed: evaluating ? null : _runEvaluation,
        icon: evaluating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.play_circle_outline, size: 18),
        label: Text(evaluating ? 'Running...' : 'Run evaluation'),
      ),
      child: ev == null
          ? const EmptyState(icon: Icons.science_outlined, title: 'No evaluation run yet', message: 'Run the 8 predefined synthetic cases (about 1 second).')
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ResponsiveGrid(minItemWidth: 190, children: [
                StatCard(label: 'Cases passed', value: '${sum!['cases_passed']}/${sum['cases']}', 
                    color: sum['cases_passed'] == sum['cases'] ? HG.routine : HG.high),
                StatCard(label: 'Checks passed', value: '${sum['checks_passed']}/${sum['checks']}'),
                StatCard(label: 'Mean alert lead time', value: '${sum['mean_alert_lead_time_min'] ?? '-'} min', footnote: 'before the limit was exceeded'),
                StatCard(label: 'False-alarm rate', value: pct(sum['mean_false_alarm_rate']), color: ((sum['mean_false_alarm_rate'] as num?) ?? 0) > 0 ? HG.elevated : null),
                StatCard(label: 'Missed-alert rate', value: pct(sum['mean_missed_alert_rate']), color: ((sum['mean_missed_alert_rate'] as num?) ?? 0) > 0 ? HG.high : null),
                StatCard(label: '"False safe" minutes', value: '${sum['total_false_safe_minutes']}', 
                    color: sum['total_false_safe_minutes'] == 0 ? HG.routine : HG.critical, footnote: 'Routine shown while data missing'),
              ]),
              const SizedBox(height: 10),
              Text('${ev['method']}', style: const TextStyle(fontSize: 13, color: HG.muted)),
              const SizedBox(height: 4),
              Text('${ev['disclaimer']}', style: const TextStyle(fontSize: 13, color: HG.muted)),
              Text('Generated ${fmtDateTime(ev['generated_at'])}', style: const TextStyle(fontSize: 11, color: HG.muted)),
              const SizedBox(height: 12),
              for (final c in jList(ev['cases'])) _case(c),
            ]),
    );
  }

  Widget _case(J c) {
    final m = jMap(c['metrics']);
    final passed = c['passed'] == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(passed ? Icons.check_circle : Icons.cancel, color: passed ? HG.routine : HG.high),
          title: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
          subtitle: Text('${c['purpose']} · scenario ${c['scenario_name']}', style: const TextStyle(fontSize: 12)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Wrap(spacing: 22, runSpacing: 8, children: [
              for (final e in {
                'Reference peak': humanize(m['reference_peak_category']),
                'System peak': humanize(m['system_peak_category']),
                'Lead time': m['alert_lead_time_min'] == null ? '-' : '${m['alert_lead_time_min']} min',
                'False alarms': pct(m['false_alarm_rate']),
                'Missed alerts': pct(m['missed_alert_rate']),
                'False-safe min': '${m['false_safe_minutes']}',
                'Completeness': pct(m['assessment_completeness']),
                'Sensor availability': pct(m['sensor_data_availability']),
                'Stale detection': m['stale_detection_seconds'] == null ? '-' : '${m['stale_detection_seconds']} s',
                'Recovery': m['connectivity_recovery_seconds'] == null ? '-' : '${m['connectivity_recovery_seconds']} s',
                'Backfilled': '${m['backfilled_readings']}',
                'Crew': '${humanize(jMap(c['crew'])['workload'])} / ${humanize(jMap(c['crew'])['acclimatization'])}',
              }.entries)
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.key.toUpperCase(), style: const TextStyle(fontSize: 10, color: HG.muted, fontWeight: FontWeight.w700)),
                  Text(e.value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ]),
            ]),
            const SizedBox(height: 12),
            _levels(jList(c['series'])),
            const SizedBox(height: 10),
            for (final ch in jList(c['checks']))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(ch['passed'] == true ? Icons.check : Icons.close, size: 16, color: ch['passed'] == true ? HG.routine : HG.high),
                  const SizedBox(width: 6),
                  Expanded(child: Text('${ch['description']} - expected ${ch['expected']}, observed ${ch['observed']}', style: const TextStyle(fontSize: 12.5))),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _levels(List<J> series) {
    if (series.isEmpty) return const SizedBox.shrink();
    List<FlSpot> spots(String k) => [for (final p in series) FlSpot((p['minute'] as num).toDouble(), (p[k] as num).toDouble())];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 150,
        child: LineChart(LineChartData(
          minY: -1,
          maxY: 4,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(drawVerticalLine: false, horizontalInterval: 1, getDrawingHorizontalLine: (_) => const FlLine(color: HG.border, strokeWidth: 1)),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 64, interval: 1,
                getTitlesWidget: (v, _) => Text(['No data', 'Routine', 'Caution', 'Elevated', 'High', 'Critical'][v.toInt() + 1], style: const TextStyle(fontSize: 10, color: HG.muted)))),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 20,
                getTitlesWidget: (v, _) => Text('${v.toInt()}m', style: const TextStyle(fontSize: 10, color: HG.muted)))),
          ),
          lineBarsData: [
            LineChartBarData(spots: spots('reference'), isStepLineChart: true, color: HG.muted, barWidth: 2, dashArray: [5, 3], dotData: const FlDotData(show: false)),
            LineChartBarData(spots: spots('system'), isStepLineChart: true, color: HG.primary, barWidth: 2.2, dotData: const FlDotData(show: false)),
          ],
        ), duration: Duration.zero),
      ),
      const Row(children: [
        SizedBox(width: 14, child: Divider(color: HG.muted, thickness: 2)),
        SizedBox(width: 4),
        Text('Reference (ground truth)  ', style: TextStyle(fontSize: 11)),
        SizedBox(width: 14, child: Divider(color: HG.primary, thickness: 2)),
        SizedBox(width: 4),
        Text('System output (noisy / faulty data)', style: TextStyle(fontSize: 11)),
      ]),
    ]);
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
