import 'package:flutter/material.dart';

/// Calm, neutral design: white surfaces, one navy accent, and colour only in small level indicators.
class T {
  static const bg = Color(0xFFF5F6F8);
  static const surface = Colors.white;
  static const border = Color(0xFFE4E7EC);
  static const text = Color(0xFF101828);
  static const muted = Color(0xFF667085);
  static const subtle = Color(0xFFF2F4F7);
  static const navy = Color(0xFF14284B);
  static const navySoft = Color(0xFFEAEFF7);
  static const ok = Color(0xFF12805C);
  static const warn = Color(0xFFB54708);

  static const fonts = ['NotoSansArabic', 'NotoSansDevanagari', 'NotoSansMalayalam', 'NotoSansBengali'];

  static ThemeData theme() {
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      fontFamilyFallback: fonts,
      colorScheme: ColorScheme.fromSeed(seedColor: navy, primary: navy, surface: surface),
      scaffoldBackgroundColor: bg,
    );
    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      dividerTheme: const DividerThemeData(color: border, space: 1, thickness: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: navy,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          minimumSize: const Size.fromHeight(48),
          side: const BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: navySoft,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontSize: 12.5,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? navy : muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? navy : muted)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: navy),
    );
  }
}

/// Heat level presentation. The order matches the HeatGuard assessment categories.
class Level {
  const Level(this.id, this.rank, this.color, this.tint, this.icon);
  final String id;
  final int rank; // 0..4, -1 for unavailable
  final Color color;
  final Color tint;
  final IconData icon;

  static const scale = ['routine', 'caution', 'elevated', 'high', 'critical'];

  static const _all = {
    'routine': Level('routine', 0, Color(0xFF12805C), Color(0xFFE7F6EF), Icons.check_circle_outline),
    'caution': Level('caution', 1, Color(0xFFB88A00), Color(0xFFFDF6DC), Icons.info_outline),
    'elevated': Level('elevated', 2, Color(0xFFC4620A), Color(0xFFFDEFE3), Icons.thermostat),
    'high': Level('high', 3, Color(0xFFC2410C), Color(0xFFFDEBE4), Icons.warning_amber_rounded),
    'critical': Level('critical', 4, Color(0xFFB42318), Color(0xFFFCE9E7), Icons.report_outlined),
    'unavailable': Level('unavailable', -1, Color(0xFF6941C6), Color(0xFFF1ECFB), Icons.cloud_off_outlined),
  };

  static Level of(String? id) => _all[id] ?? _all['unavailable']!;
}
