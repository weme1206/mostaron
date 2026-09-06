import 'package:flutter/material.dart';
import '../utils/colors.dart';

class AppTheme {
  static const Map<String, Color> accents = {
    'blue': Color(0xFF1E88E5),
    'purple': Color(0xFF7B1FA2),
    'teal': Color(0xFF00897B),
    'red': Color(0xFFD32F2F),
    'green': Color(0xFF388E3C),
  };

  /// 支持预设键或任意 hex 颜色
  static Color accent(String key) {
    final c = parseHexColor(key);
    if (c != null) return c;
    return accents[key] ?? accents['blue']!;
  }

  static const Color darkBg = Color(0xFF0A1A2F);

  static ThemeData light(String accentKey) {
    final seed = accent(accentKey);
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
    return _base(scheme, const Color(0xFFF4F7FB), seed);
  }

  static ThemeData dark(String accentKey) {
    final seed = accent(accentKey);
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
    return _base(scheme, darkBg, seed);
  }

  static ThemeData _base(ColorScheme scheme, Color scaffoldBg, Color seed) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBg,
      appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(backgroundColor: seed),
    );
  }
}
