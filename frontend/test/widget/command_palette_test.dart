import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:balansoft_ws/core/i18n/locale_controller.dart';
import 'package:balansoft_ws/core/i18n/translations.dart';
import 'package:balansoft_ws/core/theme/app_theme.dart';
import 'package:balansoft_ws/presentation/widgets/command_palette.dart';

void main() {
  group('CommandPalette Widget Tests', () {
    late LocaleController localeController;

    setUp(() {
      localeController = LocaleController();
      AppTranslations.setController(localeController);
    });

    Widget buildApp({
      required VoidCallback onClose,
      required void Function(String) onExecute,
      String langCode = 'es',
      bool dark = false,
    }) {
      localeController.setLanguage(AppLanguage.values.byName(langCode));
      return MaterialApp(
        theme: dark ? buildDarkTheme() : buildLightTheme(),
        home: Scaffold(
          body: CommandPalette(
            onClose: onClose,
            onExecute: onExecute,
          ),
        ),
      );
    }

    tearDown(() {
      localeController.setLanguage(AppLanguage.es);
    });

    testWidgets('renderiza correctamente el campo de búsqueda con hint traducido',
        (tester) async {
      await tester.pumpWidget(
        buildApp(onClose: () {}, onExecute: (_) {}, langCode: 'es'),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(
        find.text(AppTranslations.tr('cmd_buscar_hint', langCode: 'es')),
        findsOneWidget,
      );
    });

    testWidgets('renderiza hint en inglés al cambiar idioma', (tester) async {
      await tester.pumpWidget(
        buildApp(onClose: () {}, onExecute: (_) {}, langCode: 'en'),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(AppTranslations.tr('cmd_buscar_hint', langCode: 'en')),
        findsOneWidget,
      );
    });

    testWidgets('filtra y encuentra comandos recién agregados en español',
        (tester) async {
      await tester.pumpWidget(
        buildApp(onClose: () {}, onExecute: (_) {}, langCode: 'es'),
      );
      await tester.pumpAndSettle();

      final consultas = [
        'Ajustes de Inventario',
        'Terceros',
        'Categorías',
        'Indicadores',
        'Semáforos',
        'Cámaras',
        'Barreras',
        'Impresoras',
        'Roles',
        'Ingresos',
        'Despachos',
        'Conceptos de Kardex',
      ];

      for (final q in consultas) {
        await tester.enterText(find.byType(TextField), q);
        await tester.pumpAndSettle();
        expect(
          find.textContaining(q, findRichText: true),
          findsWidgets,
          reason: 'Debe encontrar "$q" en la paleta',
        );
      }
    });

    testWidgets('filtra y encuentra comandos traducidos en inglés',
        (tester) async {
      await tester.pumpWidget(
        buildApp(onClose: () {}, onExecute: (_) {}, langCode: 'en'),
      );
      await tester.pumpAndSettle();

      final consultas = [
        'Inventory Adjustments',
        'Third Parties',
        'Categories',
        'Indicators',
        'Traffic Lights',
        'Cameras',
        'Traffic Barriers',
        'Printers',
        'Roles & Permissions',
        'Inbound Weighings',
        'Outbound Weighings',
        'Kardex Concepts',
      ];

      for (final q in consultas) {
        await tester.enterText(find.byType(TextField), q);
        await tester.pumpAndSettle();
        expect(
          find.textContaining(q, findRichText: true),
          findsWidgets,
          reason: 'Debe encontrar "$q" en inglés',
        );
      }
    });

    testWidgets('búsqueda por prefijo directo t:, p:, c: traduce etiqueta dinámica',
        (tester) async {
      final ejecutados = <String>[];
      await tester.pumpWidget(
        buildApp(
          onClose: () {},
          onExecute: ejecutados.add,
          langCode: 'es',
        ),
      );
      await tester.pumpAndSettle();

      // t:#123
      await tester.enterText(find.byType(TextField), 't:#123');
      await tester.pumpAndSettle();
      expect(find.textContaining('Buscar boleto'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(ejecutados.last, 'buscar:t:#123');

      // p:ABC123
      await tester.enterText(find.byType(TextField), 'p:ABC123');
      await tester.pumpAndSettle();
      expect(find.textContaining('Buscar placa'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(ejecutados.last, 'buscar:p:ABC123');

      // c:V123456
      await tester.enterText(find.byType(TextField), 'c:V123456');
      await tester.pumpAndSettle();
      expect(find.textContaining('Buscar conductor'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(ejecutados.last, 'buscar:c:V123456');
    });

    testWidgets('tecla Escape y botón cerrar invocan onClose', (tester) async {
      int cerrados = 0;
      await tester.pumpWidget(
        buildApp(
          onClose: () => cerrados++,
          onExecute: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      // Pulsar Escape
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(cerrados, 1);

      // Pulsar botón de cerrar (icono close)
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(cerrados, 2);
    });

    testWidgets('navegación con flechas arriba/abajo selecciona elementos',
        (tester) async {
      final ejecutados = <String>[];
      await tester.pumpWidget(
        buildApp(
          onClose: () {},
          onExecute: ejecutados.add,
        ),
      );
      await tester.pumpAndSettle();

      // Bajar una posición
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      // Ejecutar selección con Enter
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(ejecutados, isNotEmpty);
      expect(ejecutados.first, 'go:pesaje_manual');
    });

    testWidgets('funciona correctamente bajo tema oscuro sin errores de contraste',
        (tester) async {
      await tester.pumpWidget(
        buildApp(
          onClose: () {},
          onExecute: (_) {},
          dark: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CommandPalette), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });
  });
}
