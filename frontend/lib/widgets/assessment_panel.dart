import 'package:material_ui/material_ui.dart';

import '../core/format.dart';
import '../core/severity.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'common.dart';

/// Full explainability view of one assessment: why, what to do, data used,
/// data quality, method, guideline and limitations.
class AssessmentPanel extends StatelessWidget {
  const AssessmentPanel(this.a, {super.key, this.compact = false});
  final Assessment a;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final sev = Sev.of(a.category);
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sev.tint,
          border: Border(left: BorderSide(color: sev.color, width: 4)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SevChip(a.category, large: true),
            if (a.effectiveWbgt != null) Pill('Effective WBGT ${fmtNum(a.effectiveWbgt)} °C', color: HG.text),
            if (a.status != 'valid') Pill(a.status.toUpperCase(), color: HG.unavailable, icon: Icons.report_gmailerrorred),
            if (a.origin == 'SIMULATED') const SimulatedBadge(),
          ]),
          const SizedBox(height: 10),
          Text(a.explanation, style: const TextStyle(fontSize: 14, height: 1.45, color: HG.text)),
        ]),
      ),
      const SizedBox(height: 14),
      _twoCol(context, [
        _block(context, 'Contributing factors', Icons.account_tree_outlined, [
          if (a.factors.isEmpty) Text('None recorded', style: t.bodySmall),
          for (final f in a.factors) _factor(f),
        ]),
        _block(context, 'Recommended protective actions', Icons.health_and_safety_outlined, [
          for (final r in a.actions) _action(r),
        ]),
      ]),
      const SizedBox(height: 14),
      _twoCol(context, [
        _block(context, 'Data quality & confidence', Icons.fact_check_outlined, _quality(context)),
        if (a.limit != null)
          _block(context, 'Limit calculation', Icons.functions, _limit(context))
        else
          _block(context, 'Limit calculation', Icons.functions, [Text('Not performed - required inputs missing.', style: t.bodySmall)]),
      ]),
      if (!compact) ...[
        const SizedBox(height: 14),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Data used, method, guideline & limitations', style: t.titleSmall),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            children: [_details(context)],
          ),
        ),
      ],
    ]);
  }

  Widget _twoCol(BuildContext context, List<Widget> children) => LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 720) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 14), children[i]],
          ]);
        }
        return IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 14), Expanded(child: children[i])],
          ]),
        );
      });

  Widget _block(BuildContext context, String title, IconData icon, List<Widget> children) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border.all(color: HG.border), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 16, color: HG.muted),
            const SizedBox(width: 6),
            Text(title, style: Theme.of(context).textTheme.titleSmall),
          ]),
          const SizedBox(height: 8),
          ...children,
        ]),
      );

  Widget _factor(J f) {
    final dir = f['direction'] as String? ?? 'neutral';
    final (IconData icon, Color color) = switch (dir) {
      'increases_concern' => (Icons.arrow_upward, HG.high),
      'reduces_concern' => (Icons.arrow_downward, HG.routine),
      'uncertainty' => (Icons.help_outline, HG.unavailable),
      _ => (Icons.remove, HG.muted),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Tooltip(message: humanize(dir), child: Icon(icon, size: 15, color: color)),
        const SizedBox(width: 6),
        Expanded(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '${f['factor']}: ', style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: '${f['detail']}'),
          ]), style: const TextStyle(fontSize: 12.5, height: 1.35)),
        ),
      ]),
    );
  }

  Widget _action(J r) {
    final p = r['priority'] as String? ?? 'advised';
    final color = switch (p) { 'urgent' => HG.critical, 'required' => HG.high, 'advised' => HG.elevated, _ => HG.routine };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          margin: const EdgeInsets.only(top: 1),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(3)),
          child: Text(p.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${r['action']}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            Text('${r['detail']}', style: const TextStyle(fontSize: 12, color: HG.muted, height: 1.35)),
            if ((r['source'] ?? '').toString().isNotEmpty)
              Text('Source: ${r['source']}', style: const TextStyle(fontSize: 10.5, color: HG.muted, fontStyle: FontStyle.italic)),
          ]),
        ),
      ]),
    );
  }

  List<Widget> _quality(BuildContext context) {
    final dq = a.dataQuality;
    final conf = dq['assessment_confidence'] as String? ?? '-';
    final confColor = switch (conf) { 'standard' => HG.routine, 'reduced' => HG.elevated, _ => HG.unavailable };
    return [
      KV('Measurement validity', humanize(dq['measurement_validity']), width: 140),
      KV('Data completeness', '', width: 140,
          valueWidget: Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                    value: a.completeness, minHeight: 7, backgroundColor: HG.border,
                    color: a.completeness >= 1 ? HG.routine : (a.completeness >= 0.6 ? HG.elevated : HG.high)),
              ),
            ),
            const SizedBox(width: 8),
            Text(pct(a.completeness), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ])),
      KV('Assessment confidence', '', width: 140, valueWidget: Align(alignment: Alignment.centerLeft, child: Pill(humanize(conf), color: confColor))),
      KV('Reading age', dq['reading_age_seconds'] == null ? 'no reading' : fmtDuration(dq['reading_age_seconds'] as num), width: 140),
      if ((dq['missing_inputs'] as List? ?? []).isNotEmpty)
        KV('Missing', (dq['missing_inputs'] as List).join('; '), width: 140),
      if ((dq['unknown_inputs'] as List? ?? []).isNotEmpty) KV('Unknown', (dq['unknown_inputs'] as List).join('; '), width: 140),
      for (final r in (dq['confidence_reasons'] as List? ?? []))
        Padding(padding: const EdgeInsets.only(top: 3), child: Text('• $r', style: const TextStyle(fontSize: 11.5, color: HG.muted))),
      const SizedBox(height: 4),
      const Text('Confidence is a qualitative data-quality rating, not a probability.',
          style: TextStyle(fontSize: 10.5, color: HG.muted, fontStyle: FontStyle.italic)),
    ];
  }

  List<Widget> _limit(BuildContext context) {
    final l = a.limit!;
    final regimes = jMap(l['regime_limits']);
    final eff = jNum(l['effective_wbgt']) ?? 0;
    return [
      KV('Limit applied', '${l['limit_type']}', width: 140),
      Text('${l['limit_reason']}', style: const TextStyle(fontSize: 11.5, color: HG.muted)),
      const SizedBox(height: 4),
      KV('Metabolic rate', '${fmtNum(l['metabolic_rate_w'], digits: 0)} W (1-h TWA ${fmtNum(l['twa_metabolic_rate_w'], digits: 0)} W)', width: 140),
      KV('WBGT measured', '${fmtNum(l['measured_wbgt'], digits: 2)} °C', width: 140),
      if (l['rolling_mean_wbgt'] != null) KV('60-min mean', '${fmtNum(l['rolling_mean_wbgt'], digits: 2)} °C', width: 140),
      KV('Clothing adj.', '+${fmtNum(l['clothing_adjustment'])} °C', width: 140),
      KV('Effective WBGT', '${fmtNum(eff, digits: 2)} °C', width: 140),
      const SizedBox(height: 6),
      Table(
        columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1.2)},
        children: [
          const TableRow(children: [
            Text('Work/rest regime', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: HG.muted)),
            Text('Limit °C', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: HG.muted)),
            Text('Status', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: HG.muted)),
          ]),
          for (final e in regimes.entries)
            TableRow(
              decoration: BoxDecoration(color: e.key == l['current_regime'] ? HG.primary.withValues(alpha: 0.06) : null),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text('${regimeLabels[e.key] ?? e.key}${e.key == l['current_regime'] ? '  (current)' : ''}',
                      style: TextStyle(fontSize: 12, fontWeight: e.key == l['current_regime'] ? FontWeight.w700 : FontWeight.w400)),
                ),
                Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(fmtNum(e.value), style: const TextStyle(fontSize: 12))),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(eff <= (e.value as num) ? 'within' : 'exceeded',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: eff <= (e.value as num) ? HG.routine : HG.high)),
                ),
              ],
            ),
        ],
      ),
    ];
  }

  Widget _details(BuildContext context) {
    final i = a.inputs;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 24, runSpacing: 2, children: [
        for (final e in {
          'Environment': humanize(i['environment']),
          'Direct solar load': '${i['direct_solar_load']}',
          'Dry-bulb (Tdb)': fmtNum(i['dry_bulb'], digits: 2, suffix: ' °C'),
          'Natural wet-bulb (Tnwb)': fmtNum(i['natural_wet_bulb'], digits: 2, suffix: ' °C'),
          'Globe (Tg)': fmtNum(i['globe_temperature'], digits: 2, suffix: ' °C'),
          'Relative humidity': fmtNum(i['relative_humidity'], digits: 0, suffix: ' %'),
          'Workload': humanize(i['workload']),
          'Clothing': humanize(i['clothing']),
          'Acclimatization': humanize(i['acclimatization']),
          'Work/rest regime': regimeLabels[i['work_rest_regime']] ?? '-',
          'Shift': '${i['shift_start']} for ${i['shift_duration_hours']} h',
          'Simulated clock': '${i['sim_clock'] ?? '-'}',
          'Manual overrides': ((i['manual_override'] as List?) ?? []).isEmpty ? 'none' : (i['manual_override'] as List).join(', '),
        }.entries)
          SizedBox(width: 280, child: KV(e.key, e.value, width: 150)),
      ]),
      if (i['wbgt_formula'] != null) ...[
        const SizedBox(height: 8),
        Text('Formula: ${i['wbgt_formula']}', style: const TextStyle(fontFamily: 'Roboto', fontFeatures: [FontFeature.tabularFigures()], fontSize: 12)),
      ],
      const SizedBox(height: 8),
      Text('Method: ${a.method}', style: const TextStyle(fontSize: 12.5)),
      const SizedBox(height: 4),
      Text('Guideline: ${a.reference}', style: const TextStyle(fontSize: 12.5)),
      const SizedBox(height: 8),
      const Text('Limitations', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
      for (final l in a.limitations) Text('• $l', style: const TextStyle(fontSize: 12, color: HG.muted)),
      const SizedBox(height: 6),
      Text('Assessment ${a.id} · ${fmtDateTime(a.timestamp)}', style: const TextStyle(fontSize: 11, color: HG.muted)),
    ]);
  }
}
