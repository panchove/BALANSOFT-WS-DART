import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:balansoft_ws/core/theme/app_theme.dart';
import 'package:balansoft_ws/core/theme/theme_controller.dart';

void main() {
  group('AppTheme Tests', () {
    test('buildLightTheme se construye sin excepciones con propiedades válidas', () {
      final theme = buildLightTheme();

      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, SwsColors.light);
      expect(theme.colorScheme.surface, Colors.white);
      expect(theme.colorScheme.primary, SwsColors.primary);
      expect(theme.colorScheme.error, SwsColors.danger);
      expect(theme.cardTheme.elevation, 0);
      expect(theme.appBarTheme.elevation, 0);
      expect(theme.inputDecorationTheme.filled, isTrue);
      expect(theme.floatingActionButtonTheme.backgroundColor, SwsColors.accent);
    });

    test('buildDarkTheme se construye sin excepciones con propiedades válidas', () {
      final theme = buildDarkTheme();

      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, SwsColors.darkBg);
      expect(theme.colorScheme.surface, SwsColors.darkCard);
      expect(theme.colorScheme.primary, SwsColors.accent);
      expect(theme.colorScheme.error, SwsColors.danger);
      expect(theme.cardTheme.color, SwsColors.darkCard);
      expect(theme.appBarTheme.backgroundColor, SwsColors.darkBg);
      expect(theme.inputDecorationTheme.fillColor, SwsColors.darkCard);
      expect(theme.floatingActionButtonTheme.backgroundColor, SwsColors.accent);
    });

    testWidgets('colorDeEstadoLegible ajusta luminosidad según el brillo del tema', (tester) async {
      late BuildContext lightContext;
      late BuildContext darkContext;

      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          themeMode: ThemeMode.light,
          home: Builder(builder: (ctx) {
            lightContext = ctx;
            return const SizedBox();
          }),
        ),
      );
      await tester.pumpAndSettle();

      final estadoClaro = colorDeEstadoLegible(lightContext, SwsColors.warning);
      final hslClaro = HSLColor.fromColor(estadoClaro);
      expect(hslClaro.lightness, closeTo(0.32, 0.01));

      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          themeMode: ThemeMode.dark,
          home: Builder(builder: (ctx) {
            darkContext = ctx;
            return const SizedBox();
          }),
        ),
      );
      await tester.pumpAndSettle();

      final estadoOscuro = colorDeEstadoLegible(darkContext, SwsColors.warning);
      final hslOscuro = HSLColor.fromColor(estadoOscuro);
      expect(hslOscuro.lightness, closeTo(0.78, 0.01));
    });

    test('ThemeController cambia y persiste el tema correctamente', () async {
      SharedPreferences.setMockInitialValues({});
      final controller = ThemeController();
      await controller.load();

      expect(controller.tema, TemaApp.sistema);
      expect(controller.themeMode, ThemeMode.system);

      await controller.setTema(TemaApp.oscuro);
      expect(controller.tema, TemaApp.oscuro);
      expect(controller.themeMode, ThemeMode.dark);

      await controller.setTema(TemaApp.claro);
      expect(controller.tema, TemaApp.claro);
      expect(controller.themeMode, ThemeMode.light);
    });
  });
}
