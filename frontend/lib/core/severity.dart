import 'package:material_ui/material_ui.dart';

import 'theme.dart';

class Sev {
  final String id;
  final String label;
  final String short;
  final Color color;
  final Color ink; // readable text colour on a light tint
  final IconData icon;
  final int level;
  const Sev(this.id, this.label, this.short, this.color, this.ink, this.icon, this.level);

  static const routine = Sev('routine', 'Routine monitoring', 'Routine', HG.routine, Color(0xFF166534), Icons.check_circle_outline, 0);
  static const caution = Sev('caution', 'Caution', 'Caution', HG.caution, Color(0xFF854D0E), Icons.info_outline, 1);
  static const elevated = Sev('elevated', 'Elevated', 'Elevated', HG.elevated, Color(0xFF9A3412), Icons.warning_amber_rounded, 2);
  static const high = Sev('high', 'High', 'High', HG.high, Color(0xFF991B1B), Icons.warning_amber_rounded, 3);
  static const critical = Sev('critical', 'Critical', 'Critical', HG.critical, Color(0xFF7F1D1D), Icons.report_outlined, 4);
  static const unavailable = Sev('unavailable', 'Assessment unavailable', 'No data', HG.unavailable, Color(0xFF5B21B6), Icons.sensors_off_outlined, -1);

  static const all = [routine, caution, elevated, high, critical];

  static Sev of(String? id) => switch (id) {
        'routine' => routine,
        'caution' => caution,
        'elevated' => elevated,
        'high' => high,
        'critical' => critical,
        _ => unavailable, // 'unavailable' and 'data_unavailable'
      };

  bool get needsAttention => level != 0;
  Color get onColor => this == caution ? const Color(0xFF422006) : Colors.white;
  Color get tint => color.withValues(alpha: 0.10);
}
