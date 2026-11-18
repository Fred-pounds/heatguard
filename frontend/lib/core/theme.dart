import 'package:material_ui/material_ui.dart';

/// Design tokens. Calm, high-contrast, low-noise: colour is reserved for risk status.
class HG {
  // Surfaces & text
  static const navy = Color(0xFF0F172A);
  static const navy2 = Color(0xFF1E293B);
  static const navyLine = Color(0xFF243044);
  static const bg = Color(0xFFF6F7F9);
  static const surface = Colors.white;
  static const subtle = Color(0xFFF3F4F6);
  static const border = Color(0xFFE5E7EB);
  static const text = Color(0xFF111827);
  static const muted = Color(0xFF6B7280);
  static const primary = Color(0xFF2563EB);
  static const accent = Color(0xFFEA580C);

  // Severity scale (used consistently everywhere)
  static const routine = Color(0xFF16A34A);
  static const caution = Color(0xFFEAB308);
  static const elevated = Color(0xFFF97316);
  static const high = Color(0xFFDC2626);
  static const critical = Color(0xFF7F1D1D);
  static const unavailable = Color(0xFF7C3AED); // data unavailable: never green or grey
  static const simulated = Color(0xFF7C3AED);

  // Spacing scale
  static const s1 = 4.0, s2 = 8.0, s3 = 12.0, s4 = 16.0, s5 = 24.0, s6 = 32.0;

  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(seedColor: primary, surface: surface).copyWith(primary: primary);
    const border8 = BorderRadius.all(Radius.circular(8));
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      fontFamily: 'Roboto',
      textTheme: const TextTheme(
        headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: text, height: 1.2),
        headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: text, height: 1.25),
        titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: text, height: 1.3),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: text, height: 1.35),
        titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: text, height: 1.4),
        bodyLarge: TextStyle(fontSize: 15, color: text, height: 1.55),
        bodyMedium: TextStyle(fontSize: 14, color: text, height: 1.5),
        bodySmall: TextStyle(fontSize: 13, color: muted, height: 1.45),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        labelMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: muted),
        labelSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: muted, letterSpacing: 0.1),
      ),
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12)), side: BorderSide(color: border)),
      ),
      dividerTheme: const DividerThemeData(color: border, space: 1, thickness: 1),
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: border8, borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: border8, borderSide: BorderSide(color: border)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: const RoundedRectangleBorder(borderRadius: border8),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: const BorderSide(color: border),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: const RoundedRectangleBorder(borderRadius: border8),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: const RoundedRectangleBorder(borderRadius: border8))),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          foregroundColor: muted,
          selectedBackgroundColor: const Color(0xFFE0E9FF),
          selectedForegroundColor: primary,
          side: const BorderSide(color: border),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: text,
        unselectedLabelColor: muted,
        indicatorColor: primary,
        dividerColor: border,
        labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        tabAlignment: TabAlignment.start,
      ),
      expansionTileTheme: const ExpansionTileThemeData(shape: Border(), collapsedShape: Border()),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, width: 440),
      tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 400)),
    );
  }
}
