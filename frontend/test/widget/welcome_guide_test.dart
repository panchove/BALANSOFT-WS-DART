import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:balansoft_ws/core/config/app_config.dart';
import 'package:balansoft_ws/core/i18n/translations.dart';
import 'package:balansoft_ws/core/theme/app_theme.dart';
import 'package:balansoft_ws/core/widgets/welcome_guide_dialog.dart';

/// Mini tutorial de bienvenida: se muestra una sola vez tras el onboarding y
/// se puede repetir desde Ayuda. Cubre el stepper (avance/retroceso), el flag
/// `tutorial_visto` y que el texto respete el tema claro (sin blanco).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // `AppConfig` es estático y no se puede usar `init()` en testWidgets
    // (FakeAsync); el flag del tutorial se resetea en memoria por test.
    AppConfig.tutorialVisto = false;
  });

  Future<void> montar(WidgetTester tester, {bool marcarVisto = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: ThemeMode.light,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () =>
                    mostrarGuiaRapida(ctx, marcarVisto: marcarVisto),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> abrir(WidgetTester tester) async {
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('se abre en el paso 1 de 7', (tester) async {
    await montar(tester);
    await abrir(tester);
    expect(find.text(AppTranslations.tr('tutorial_title')), findsOneWidget);
    expect(find.text(AppTranslations.tr('tutorial_sidebar_title')),
        findsOneWidget);
    expect(
      find.text(AppTranslations.tr('tutorial_step', args: ['1', '7'])),
      findsOneWidget,
    );
  });

  testWidgets('Siguiente avanza y Atrás retrocede', (tester) async {
    await montar(tester);
    await abrir(tester);

    await tester.tap(find.byKey(const Key('guia_siguiente_btn')));
    await tester.pumpAndSettle();
    expect(find.text(AppTranslations.tr('tutorial_dashboard_title')),
        findsOneWidget);
    expect(
      find.text(AppTranslations.tr('tutorial_step', args: ['2', '7'])),
      findsOneWidget,
    );

    await tester.tap(find.text(AppTranslations.tr('tutorial_back')));
    await tester.pumpAndSettle();
    expect(find.text(AppTranslations.tr('tutorial_sidebar_title')),
        findsOneWidget);
  });

  testWidgets('en el último paso aparece Finalizar y marca visto',
      (tester) async {
    await montar(tester);
    await abrir(tester);

    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byKey(const Key('guia_siguiente_btn')));
      await tester.pumpAndSettle();
    }
    expect(find.text(AppTranslations.tr('tutorial_finish')), findsOneWidget);

    await tester.tap(find.byKey(const Key('guia_siguiente_btn')));
    await tester.pumpAndSettle();
    expect(find.text(AppTranslations.tr('tutorial_title')), findsNothing);
    expect(AppConfig.tutorialVisto, isTrue);
  });

  testWidgets('Saltar cierra y marca visto', (tester) async {
    await montar(tester);
    await abrir(tester);

    await tester.tap(find.text(AppTranslations.tr('tutorial_skip')));
    await tester.pumpAndSettle();
    expect(find.text(AppTranslations.tr('tutorial_title')), findsNothing);
    expect(AppConfig.tutorialVisto, isTrue);
  });

  testWidgets('sin marcarVisto (desde Ayuda) no altera el flag',
      (tester) async {
    await montar(tester, marcarVisto: false);
    await abrir(tester);
    await tester.tap(find.text(AppTranslations.tr('tutorial_skip')));
    await tester.pumpAndSettle();
    expect(AppConfig.tutorialVisto, isFalse);
  });

  testWidgets('tema claro: el título no usa blanco', (tester) async {
    await montar(tester);
    await abrir(tester);
    final titulo = tester.widget<Text>(
      find.text(AppTranslations.tr('tutorial_title')),
    );
    expect(titulo.style?.color, isNot(Colors.white));
  });
}
