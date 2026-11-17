import 'package:material_ui/material_ui.dart';

import 'theme.dart';

class Sev {
  final String id;
  final String label;
  final Color color;
  final IconData icon;
  final int level;
  const Sev(this.id, this.label, this.color, this.icon, this.level);

  static const routine = Sev('routine', 'Routine monitoring', HG.routine, Icons.check_circle, 0);
  static const caution = Sev('caution', 'Caution', HG.caution, Icons.info, 1);
  static const elevated = Sev('elevated', 'Elevated', HG.elevated, Icons.warning_amber_rounded, 2);
  static const high = Sev('high', 'High', HG.high, Icons.warning_rounded, 3);
  static const critical = Sev('critical', 'Critical', HG.critical, Icons.dangerous, 4);
  static const unavailable = Sev('unavailable', 'Assessment unavailable', HG.unavailable, Icons.sensors_off, -1);

  static const all = [routine, caution, elevated, high, critical];

  static Sev of(String? id) {
    switch (id) {
      case 'routine':
        return routine;
      case 'caution':
        return caution;
      case 'elevated':
        return elevated;
      case 'high':
        return high;
      case 'critical':
        return critical;
      default:
        return unavailable; // includes 'unavailable' and 'data_unavailable'
    }
  }

  /// Text colour with accessible contrast on top of [color].
  Color get onColor => (this == caution) ? const Color(0xFF2B2100) : Colors.white;
  Color get tint => color.withValues(alpha: 0.10);
}
