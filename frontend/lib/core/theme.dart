import 'package:material_ui/material_ui.dart';

class HG {
  // Brand / surfaces
  static const navy = Color(0xFF0F1B2D);
  static const navy2 = Color(0xFF16263D);
  static const navyLine = Color(0xFF243650);
  static const bg = Color(0xFFF4F6F9);
  static const surface = Colors.white;
  static const border = Color(0xFFE3E7ED);
  static const text = Color(0xFF16202E);
  static const muted = Color(0xFF5B6778);
  static const primary = Color(0xFF1F5FBF);
  static const accent = Color(0xFFE8590C);

  // Severity scale (used consistently everywhere)
  static const routine = Color(0xFF2E9E5B);
  static const caution = Color(0xFFE0B000);
  static const elevated = Color(0xFFF07C1C);
  static const high = Color(0xFFD93025);
  static const critical = Color(0xFF8B0F0F);
  static const unavailable = Color(0xFF6B4FA8); // data unavailable: deliberately NOT green or grey
  static const simulated = Color(0xFF7A5AF8);

  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(seedColor: primary, surface: surface).copyWith(primary: primary);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      fontFamily: 'Roboto',
      textTheme: const TextTheme(
        headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: text, letterSpacing: -0.2),
        titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: text),
        titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: text),
        titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: text),
        bodyMedium: TextStyle(fontSize: 13.5, color: text, height: 1.4),
        bodySmall: TextStyle(fontSize: 12, color: muted, height: 1.35),
        labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: muted, letterSpacing: 0.4),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: border)),
      ),
      dividerTheme: const DividerThemeData(color: border, space: 1, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: border)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
