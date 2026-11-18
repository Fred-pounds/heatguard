import 'package:material_ui/material_ui.dart';

import '../core/format.dart';
import '../core/severity.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'common.dart';

/// Explainability view of one assessment.
/// Summary and actions first; reasoning, data quality and calculation on demand.
class AssessmentPanel extends StatefulWidget {
  const AssessmentPanel(this.a, {super.key, this.compact = false});
  final Assessment a;
  final bool compact;
  @override
  State<AssessmentPanel> createState() => _AssessmentPanelState();
}

class _AssessmentPanelState extends State<AssessmentPanel> {
  bool showAllActions = false;

  Assessment get a => widget.a;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final sev = Sev.of(a.category);
    final l = a.limit;
    final eff = a.effectiveWbgt;
    final lim = l == null ? null : jNum(l['limit_at_current_regime']);
    final important = a.actions.where((r) => r['priority'] == 'urgent' || r['priority'] == 'required').toList();
    final primary = important.isNotEmpty ? important : a.actions;
    final shown = showAllActions ? a.actions : primary.take(4).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (a.middayBreak) ...[
        _MiddayBanner(flag: a.regulatoryFlags.first),
        const SizedBox(height: 16),
      ],
      // ---- Summary
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        SevChip(a.category, large: true),
        const Spacer(),
        if (eff != null && lim != null)
          Text.rich(TextSpan(children: [
            TextSpan(text: '${fmtNum(eff)} °C', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            TextSpan(text: '  vs limit ${fmtNum(lim)} °C', style: t.bodySmall),
          ])),
      ]),
      if (eff != null && lim != null) ...[
        const SizedBox(height: 12),
        _LimitBar(value: eff, limit: lim, margin: jNum(l!['caution_margin']) ?? 1, color: sev.color),
      ],
      const SizedBox(height: 14),
      Text(_plain(a.explanation), style: t.bodyLarge),
      const SizedBox(height: 20),

      // ---- What to do
      Text('What to do', style: t.titleSmall),
      const SizedBox(height: 8),
      for (var i = 0; i < shown.length; i++) _action(i + 1, shown[i]),
      if (a.actions.length > primary.take(4).length)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => showAllActions = !showAllActions),
            child: Text(showAllActions ? 'Show fewer actions' : 'Show all ${a.actions.length} actions'),
          ),
        ),
      const SizedBox(height: 8),
      const Divider(),

      // ---- Details (collapsed)
      Details(title: 'Why this assessment', icon: Icons.account_tree_outlined, children: [
        for (final f in a.factors) _factor(f),
      ]),
      Details(title: 'Data quality', icon: Icons.fact_check_outlined, children: _quality()),
      if (l != null) Details(title: 'How it was calculated', icon: Icons.functions, children: _limit(l)),
      if (!widget.compact)
        Details(title: 'Inputs, method and limitations', icon: Icons.menu_book_outlined, children: [_details()]),
    ]);
  }

  /// Keep explanation sentences readable (strip the "(continuous work (60/0))" noise).
  String _plain(String s) => s;

  Widget _action(int n, J r) {
    final urgent = r['priority'] == 'urgent';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: urgent ? HG.high : HG.subtle, shape: BoxShape.circle),
          child: Text('$n', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: urgent ? Colors.white : HG.text)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${r['action']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('${r['detail']}', style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ]),
    );
  }

  Widget _factor(J f) {
    final dir = f['direction'] as String? ?? 'neutral';
    final (IconData icon, Color color) = switch (dir) {
      'increases_concern' => (Icons.north_east, HG.high),
      'reduces_concern' => (Icons.south_east, HG.routine),
      'uncertainty' => (Icons.help_outline, HG.unavailable),
      _ => (Icons.remove, HG.muted),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 15, color: color)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${f['factor']}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            Text('${f['detail']}', style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ]),
    );
  }

  List<Widget> _quality() {
    final dq = a.dataQuality;
    final conf = dq['assessment_confidence'] as String? ?? '-';
    return [
      KV('Measurement validity', humanize(dq['measurement_validity'])),
      KV('Data completeness', pct(a.completeness)),
      KV('Confidence', humanize(conf)),
      KV('Reading age', dq['reading_age_seconds'] == null ? 'No reading' : fmtDuration(dq['reading_age_seconds'] as num)),
      if ((dq['missing_inputs'] as List? ?? []).isNotEmpty) KV('Missing', (dq['missing_inputs'] as List).join('; ')),
      if ((dq['unknown_inputs'] as List? ?? []).isNotEmpty) KV('Unknown', (dq['unknown_inputs'] as List).join('; ')),
      for (final r in (dq['confidence_reasons'] as List? ?? [])) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $r', style: Theme.of(context).textTheme.bodySmall)),
      const SizedBox(height: 6),
      Text('Confidence is a qualitative data-quality rating, not a probability.', style: Theme.of(context).textTheme.bodySmall),
    ];
  }

  List<Widget> _limit(J l) {
    final regimes = jMap(l['regime_limits']);
    final eff = jNum(l['effective_wbgt']) ?? 0;
    return [
      KV('Limit applied', '${l['limit_type']} - ${l['limit_reason']}'),
      KV('Metabolic rate', '${fmtNum(l['metabolic_rate_w'], digits: 0)} W  (1-hour average ${fmtNum(l['twa_metabolic_rate_w'], digits: 0)} W)'),
      KV('Effective WBGT',
          '${fmtNum(l['screening_wbgt'], digits: 1)} °C screening + ${fmtNum(l['clothing_adjustment'])} °C clothing = ${fmtNum(eff, digits: 1)} °C'),
      const SizedBox(height: 10),
      Text('Limit for each work/rest schedule', style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 6),
      for (final e in regimes.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(
              child: Text('${regimeLabels[e.key] ?? e.key}${e.key == l['current_regime'] ? '  · current' : ''}',
                  style: TextStyle(fontSize: 13.5, fontWeight: e.key == l['current_regime'] ? FontWeight.w600 : FontWeight.w400)),
            ),
            SizedBox(width: 70, child: Text('${fmtNum(e.value)} °C', style: const TextStyle(fontSize: 13.5))),
            SizedBox(
              width: 80,
              child: Text(eff <= (e.value as num) ? 'Within' : 'Exceeded',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: eff <= (e.value as num) ? HG.routine : HG.high)),
            ),
          ]),
        ),
    ];
  }

  Widget _details() {
    final i = a.inputs;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      KV('Measurements',
          'Tdb ${fmtNum(i['dry_bulb'])} °C · Tnwb ${fmtNum(i['natural_wet_bulb'])} °C · Tg ${fmtNum(i['globe_temperature'])} °C · RH ${fmtNum(i['relative_humidity'], digits: 0)} %'),
      if (i['wbgt_formula'] != null) KV('Formula', '${i['wbgt_formula']}'),
      KV('Crew context',
          '${humanize(i['workload'])} work · ${humanize(i['acclimatization'])} · ${humanize(i['clothing'])} · ${regimeLabels[i['work_rest_regime']] ?? '-'}'),
      if (((i['manual_override'] as List?) ?? []).isNotEmpty) KV('Manual overrides', (i['manual_override'] as List).join(', ')),
      KV('Method', a.method),
      KV('Guideline', a.reference),
      const SizedBox(height: 6),
      for (final l in a.limitations) Text('• $l', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 6),
      Text('${a.origin == 'SIMULATED' ? 'Simulated data · ' : ''}Assessed ${fmtDateTime(a.timestamp)}', style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}

/// Simple horizontal gauge: where the effective WBGT sits relative to the limit.
class _LimitBar extends StatelessWidget {
  const _LimitBar({required this.value, required this.limit, required this.margin, required this.color});
  final double value;
  final double limit;
  final double margin;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final lo = limit - 8, hi = limit + 6;
    double pos(double v) => ((v - lo) / (hi - lo)).clamp(0.0, 1.0);
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      return SizedBox(
        height: 26,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(left: 0, right: 0, top: 9, child: Container(height: 8, decoration: BoxDecoration(color: HG.subtle, borderRadius: BorderRadius.circular(4)))),
          Positioned(left: 0, top: 9, child: Container(width: w * pos(value), height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)))),
          Positioned(left: w * pos(limit) - 1, top: 3, child: Container(width: 2, height: 20, color: HG.text)),
          Positioned(left: (w * pos(limit) + 6).clamp(0, w - 40), top: -12, child: const Text('limit', style: TextStyle(fontSize: 11, color: HG.muted))),
        ]),
      );
    });
  }
}

class _MiddayBanner extends StatelessWidget {
  const _MiddayBanner({required this.flag});
  final J flag;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFFEFF4FF), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFBFD3FE))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.wb_sunny_outlined, color: Color(0xFF1D4ED8)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${flag['title']}', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1E3A8A), fontSize: 14.5)),
              const SizedBox(height: 2),
              Text('${flag['detail']}', style: const TextStyle(color: Color(0xFF1E3A8A), fontSize: 13.5, height: 1.4)),
              const SizedBox(height: 4),
              Text('Source: ${flag['authority']}', style: const TextStyle(color: Color(0xFF3B5BA9), fontSize: 12)),
            ]),
          ),
        ]),
      );
}
