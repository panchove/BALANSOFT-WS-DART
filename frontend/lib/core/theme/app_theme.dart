import 'package:flutter/material.dart';

/// Tokens de identidad visual BALANSOFT (design system compartido SG/WS).
abstract final class SwsColors {
  // ─── Marca ─────────────────────────────────────────────────────────────
  static const primary      = Color(0xFF1a3a5c);
  static const secondary    = Color(0xFF2d6a9f);
  static const accent       = Color(0xFF4a90d9);
  static const accentLight  = Color(0xFF6aafff);

  // ─── Gradiente principal (login / setup / mode selection) ──────────────
  static const gradientStart = Color(0xFF0a1e3a);
  static const gradientEnd   = Color(0xFF1a3a6a);

  /// Gradiente compartido por TODAS las pantallas de setup/login.
  /// Úsalo en un `Container(decoration: BoxDecoration(gradient: ...))`.
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gradientStart, gradientEnd],
    stops: const [0.0, 1.0],
  );

  // ─── Estados ───────────────────────────────────────────────────────────
  static const success = Color(0xFF28a745);
  static const warning = Color(0xFFFFc107);
  static const danger  = Color(0xFFdc3545);
  static const info    = Color(0xFF17a2b8);

  // ─── Neutros claros ────────────────────────────────────────────────────
  static const white = Color(0xFFffffff);
  static const light = Color(0xFFf8f9fa);
  static const dark  = Color(0xFF212529);

  // ─── Superficies oscuras (tema oscuro neutro) ──────────────────────────
  static const darkBg     = Color(0xFF12121e);
  static const darkCard   = Color(0xFF1a1a2e);
  static const darkBorder = Color(0xFF2a2a3e);
  static const darkText   = Color(0xFFe8e8f0);

  // ─── Azules / grises de apoyo ──────────────────────────────────────────
  static const blue100 = Color(0xFFe7eef5);
  static const gray200 = Color(0xFFdce3ea);
  static const gray400 = Color(0xFF9ca3af);
  static const gray500 = Color(0xFF6b7886);
  static const gray600 = Color(0xFF4a5568);
  static const gray700 = Color(0xFF44505c);

  // ─── Superficies translúcidas (cards sobre el gradiente oscuro) ────────
  /// Fondo de cards/paneles glass sobre el gradiente azul del login.
  /// No pueden ser `const` porque `withValues` se evalúa en runtime.
  static final Color surfaceGlass       = Colors.white.withValues(alpha: 0.05);
  static final Color surfaceGlassBorder = Colors.white.withValues(alpha: 0.08);
  static final Color inputFill          = Colors.white.withValues(alpha: 0.06);
}

// ═════════════════════════════════════════════════════════════════════════
// TEMA CLARO — Dashboard, pantallas de app
// ═════════════════════════════════════════════════════════════════════════
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
    textTheme: base.textTheme.apply(
      bodyColor: SwsColors.dark,
      displayColor: SwsColors.dark,
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════
// TEMA OSCURO — Login, setup, mode selection
//
// ⚠️ El fondo es oscuro NEUTRO (darkBg), NO el azul.
// El azul hermoso (gradientEnd) se aplica LOCALMENTE en cada pantalla de
// setup/login vía `SetupLayoutWrapper` o `Scaffold(backgroundColor: ...)`.
//
// Esto evita que el dashboard u otras pantallas que usen el tema oscuro
// hereden el azul sin querer.
// ═════════════════════════════════════════════════════════════════════════
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

    // Fondo oscuro neutro. El azul va en cada pantalla de setup.
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
    textTheme: base.textTheme.apply(
      bodyColor: SwsColors.darkText,
      displayColor: SwsColors.darkText,
    ),
  );
}