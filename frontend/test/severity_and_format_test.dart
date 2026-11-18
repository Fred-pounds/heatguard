import 'package:flutter_test/flutter_test.dart';
import 'package:heatguard/core/format.dart';
import 'package:heatguard/core/severity.dart';
import 'package:heatguard/core/theme.dart';
import 'package:heatguard/widgets/common.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('Severity mapping', () {
    test('known categories map to their level', () {
      expect(Sev.of('routine').level, 0);
      expect(Sev.of('caution').level, 1);
      expect(Sev.of('elevated').level, 2);
      expect(Sev.of('high').level, 3);
      expect(Sev.of('critical').level, 4);
    });

    test('missing or unknown data is never shown as routine (green)', () {
      for (final id in ['unavailable', 'data_unavailable', null, '', 'garbage']) {
        final s = Sev.of(id);
        expect(s, Sev.unavailable, reason: 'id=$id');
        expect(s.color, isNot(HG.routine));
        expect(s.needsAttention, isTrue);
      }
    });
  });

  group('Formatting', () {
    test('numbers', () {
      expect(fmtNum(28.456), '28.5');
      expect(fmtNum(null), '-');
      expect(fmtNum(3, digits: 0, suffix: ' W'), '3 W');
    });
    test('durations and percentages', () {
      expect(fmtDuration(42), '42s');
      expect(fmtDuration(125), '2m 5s');
      expect(pct(0.5), '50.0%');
      expect(pct(null), '-');
    });
    test('humanize', () {
      expect(humanize('not_acclimatized'), 'Not acclimatized');
      expect(humanize(null), '-');
    });
  });

  testWidgets('SevChip renders the "no data" label for unavailable assessments', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: SevChip('unavailable', short: true)))));
    expect(find.text('No data'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: SevChip('critical')))));
    expect(find.text('Critical'), findsOneWidget);
  });
}
