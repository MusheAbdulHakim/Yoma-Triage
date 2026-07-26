import 'package:flutter/material.dart';

/// Yoma Triage brand palette — clinical teal, not purple AI aesthetic.
abstract final class YomaColors {
  static const brand = Color(0xFF1A5F7A);
  static const danger = Color(0xFFC62828);
  static const safe = Color(0xFF2E7D32);
  static const caution = Color(0xFFF9A825);
  static const surface = Color(0xFFF5F7FA);
}

ThemeData buildYomaTheme() {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: YomaColors.brand,
      brightness: Brightness.light,
      primary: YomaColors.brand,
      error: YomaColors.danger,
    ),
    scaffoldBackgroundColor: YomaColors.surface,
    appBarTheme: const AppBarTheme(
      backgroundColor: YomaColors.brand,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: YomaColors.brand,
        foregroundColor: Colors.white,
      ),
    ),
    useMaterial3: true,
  );
}
