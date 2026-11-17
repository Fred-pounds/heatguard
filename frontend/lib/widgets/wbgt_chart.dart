import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';
import '../models/models.dart';

/// WBGT trend (and optionally its components) over simulated time.
/// Missing / invalid readings appear as gaps, never as interpolated values.
class WbgtChart extends StatelessWidget {
  const WbgtChart({super.key, required this.readings, this.showComponents = false, this.limits = const {}, this.height = 260});
  final List<Reading> readings;
  final bool showComponents;
  final Map<String, double> limits; // label -> limit line (°C)
  final double height;

  @override
  Widget build(BuildContext context) {
    if (readings.isEmpty) {
      return SizedBox(height: height, child: const Center(child: Text('No readings yet', style: TextStyle(color: HG.muted))));
    }
    final xs = <double>[];
    for (var i = 0; i < readings.length; i++) {
      xs.add(i.toDouble());
    }
    List<FlSpot> series(double? Function(Reading r) f) => [
          for (var i = 0; i < readings.length; i++) f(readings[i]) == null ? FlSpot.nullSpot : FlSpot(xs[i], f(readings[i])!),
        ];

    final wbgt = series((r) => r.wbgt);
    final lines = <LineChartBarData>[
      _line(wbgt, HG.primary, 2.6, area: true),
      if (showComponents) ...[
        _line(series((r) => r.issues.any((i) => i['field'] == 'dry_bulb') ? null : r.tdb), const Color(0xFF8A94A6), 1.4),
        _line(series((r) => r.issues.any((i) => i['field'] == 'natural_wet_bulb') ? null : r.tnwb), const Color(0xFF1AA6B7), 1.4),
        _line(series((r) => r.issues.any((i) => i['field'] == 'globe_temperature') ? null : r.tg), HG.accent, 1.4),
      ],
    ];
    final allY = <double>[
      for (final l in lines)
        for (final s in l.spots)
          if (s != FlSpot.nullSpot) s.y,
      ...limits.values,
    ];
    final minY = allY.isEmpty ? 15.0 : (allY.reduce(math.min) - 1).floorToDouble();
    final maxY = allY.isEmpty ? 40.0 : (allY.reduce(math.max) + 1).ceilToDouble();
    final step = math.max(1, (readings.length / 6).floor());
    final limitColors = [HG.high, HG.elevated, HG.caution, HG.critical];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: height,
        child: LineChart(
          LineChartData(
            minY: minY,
            maxY: maxY,
            minX: 0,
            maxX: math.max(1, readings.length - 1).toDouble(),
            lineBarsData: lines,
            clipData: const FlClipData.all(),
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: math.max(1, ((maxY - minY) / 5).roundToDouble()),
              getDrawingHorizontalLine: (_) => const FlLine(color: HG.border, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            extraLinesData: ExtraLinesData(horizontalLines: [
              for (final (i, e) in limits.entries.indexed)
                HorizontalLine(
                  y: e.value,
                  color: limitColors[i % limitColors.length],
                  strokeWidth: 1.4,
                  dashArray: [6, 4],
                  label: HorizontalLineLabel(
                    show: true,
                    alignment: Alignment.topRight,
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: limitColors[i % limitColors.length]),
                    labelResolver: (l) => '${e.key} ${e.value.toStringAsFixed(1)}',
                  ),
                ),
            ]),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                axisNameWidget: const Text('°C', style: TextStyle(fontSize: 11, color: HG.muted)),
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 34,
                  interval: math.max(1, ((maxY - minY) / 5).roundToDouble()),
                  getTitlesWidget: (v, m) => Text(v.toStringAsFixed(0), style: const TextStyle(fontSize: 11, color: HG.muted)),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  interval: step.toDouble(),
                  getTitlesWidget: (v, m) {
                    final i = v.round();
                    if (i < 0 || i >= readings.length || v != i.toDouble() || i % step != 0) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(readings[i].simClock ?? '', style: const TextStyle(fontSize: 10.5, color: HG.muted)),
                    );
                  },
                ),
              ),
            ),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => HG.navy,
                getTooltipItems: (spots) => spots.map((s) {
                  final names = ['WBGT', 'Tdb', 'Tnwb', 'Tg'];
                  final r = readings[s.x.round()];
                  return LineTooltipItem(
                    '${s.barIndex == 0 ? '${r.simClock ?? ''} ' : ''}${names[s.barIndex]} ${s.y.toStringAsFixed(1)}${r.lateSync && s.barIndex == 0 ? ' (late)' : ''}',
                    const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                  );
                }).toList(),
              ),
            ),
          ),
          duration: Duration.zero,
        ),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 14, runSpacing: 4, children: [
        _legend(HG.primary, 'WBGT'),
        if (showComponents) ...[
          _legend(const Color(0xFF8A94A6), 'Dry-bulb'),
          _legend(const Color(0xFF1AA6B7), 'Nat. wet-bulb'),
          _legend(HG.accent, 'Globe'),
        ],
        const Text('Gaps = missing or invalid data (never interpolated)', style: TextStyle(fontSize: 11, color: HG.muted)),
      ]),
    ]);
  }

  LineChartBarData _line(List<FlSpot> spots, Color color, double width, {bool area = false}) => LineChartBarData(
        spots: spots,
        color: color,
        barWidth: width,
        isCurved: false,
        dotData: const FlDotData(show: false),
        belowBarData: area ? BarAreaData(show: true, color: color.withValues(alpha: 0.07)) : BarAreaData(show: false),
      );

  Widget _legend(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 14, height: 3, color: c),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 11.5, color: HG.text)),
      ]);
}
