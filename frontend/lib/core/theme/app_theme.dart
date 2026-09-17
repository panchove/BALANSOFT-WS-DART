import 'package:flutter/material.dart';

/// Tokens de identidad visual BALANSOFT (design system compartido SG/WS).
abstract final class SwsColors {
  static const primary = Color(0xFF1a3a5c);
  static const secondary = Color(0xFF2d6a9f);
  static const accent = Color(0xFF4a90d9);
  static const accentLight = Color(0xFF6aafff);
  static const gradientStart = Color(0xFF0a1e3a);
  static const gradientEnd = Color(0xFF1a3a6a);

  static const success = Color(0xFF28a745);
  static const warning = Color(0xFFFFc107);
  static const danger = Color(0xFFdc3545);
  static const info = Color(0xFF17a2b8);

  static const white = Color(0xFFffffff);
  static const light = Color(0xFFf8f9fa);
  static const dark = Color(0xFF212529);
  static const darkBg = Color(0xFF12121e);
  static const darkCard = Color(0xFF1a1a2e);
  static const darkBorder = Color(0xFF2a2a3e);
  static const darkText = Color(0xFFe8e8f0);
  static const blue100 = Color(0xFFe7eef5);
  static const gray200 = Color(0xFFdce3ea);
  static const gray400 = Color(0xFF9ca3af);
  static const gray500 = Color(0xFF6b7886);
  static const gray600 = Color(0xFF4a5568);
  static const gray700 = Color(0xFF44505c);
}

ThemeData buildLightTheme() {
  final base = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: SwsColors.accent,
      primary: SwsColors.primary,
      secondary: SwsColors.secondary,
      surface: Colors.white,
      error: SwsColors.danger,
    ),
    scaffoldBackgroundColor: SwsColors.light,
    appBarTheme: const AppBarTheme(
      backgroundColor: SwsColors.light,
      foregroundColor: SwsColors.dark,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white70,
      indicatorColor: Colors.white,
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: SwsColors.gray200),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: SwsColors.accent,
      foregroundColor: Colors.white,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      labelStyle: TextStyle(color: SwsColors.dark, fontWeight: FontWeight.w500),
      floatingLabelStyle: TextStyle(
        color: SwsColors.accent,
        fontWeight: FontWeight.w600,
      ),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      prefixIconColor: SwsColors.accent,
      suffixIconColor: SwsColors.gray500,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: SwsColors.gray200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: SwsColors.gray200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: SwsColors.accent, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: SwsColors.danger, width: 2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: SwsColors.danger, width: 2),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: SwsColors.dark, displayColor: SwsColors.dark),
  );
}

ThemeData buildDarkTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: SwsColors.accent,
      primary: SwsColors.accent,
      secondary: SwsColors.accentLight,
      surface: SwsColors.darkCard,
      brightness: Brightness.dark,
      error: SwsColors.danger,
    ),
    scaffoldBackgroundColor: SwsColors.darkBg,
    appBarTheme: const AppBarTheme(
      backgroundColor: SwsColors.darkBg,
      foregroundColor: SwsColors.darkText,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: SwsColors.darkText,
      unselectedLabelColor: SwsColors.gray400,
      indicatorColor: SwsColors.darkText,
    ),
    cardTheme: const CardThemeData(
      color: SwsColors.darkCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: SwsColors.darkBorder),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: SwsColors.accent,
      foregroundColor: Colors.white,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      labelStyle: TextStyle(
        color: SwsColors.darkText,
        fontWeight: FontWeight.w500,
      ),
      floatingLabelStyle: TextStyle(
        color: SwsColors.accentLight,
        fontWeight: FontWeight.w600,
      ),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      prefixIconColor: SwsColors.accent,
      suffixIconColor: SwsColors.darkText,
      filled: true,
      fillColor: SwsColors.darkCard,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: SwsColors.darkBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: SwsColors.darkBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: SwsColors.accentLight, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: SwsColors.danger, width: 2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: SwsColors.danger, width: 2),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: SwsColors.darkText, displayColor: SwsColors.darkText),
  );
}
