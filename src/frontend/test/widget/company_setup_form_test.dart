import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:balansoft_ws/core/i18n/locale_controller.dart';
import 'package:balansoft_ws/core/i18n/translations.dart';
import 'package:balansoft_ws/core/theme/app_theme.dart';
import 'package:balansoft_ws/core/widgets/company_setup_form.dart';

/// Regresión de los tres bugs de la configuración inicial (tema, wizard y logo):
///
/// 1. En tema claro los textos usaban colores fijos de tema oscuro
///    (`SwsColors.white`/`darkCard`/`surfaceGlassBorder`) → texto blanco sobre
///    fondo blanco ilegible.
/// 2. `_siguiente()` incrementaba `_paso` pero el `PageView` nunca se movía
///    (y tiene `NeverScrollableScrollPhysics`) → había que pulsar "Continuar"
///    3 veces para que apareciera "Finalizar", sin cambio visible de página.
/// 3. `PhotoPickerField` solo mostraba bytes locales; el `logo_url` ya guardado
///    no se mostraba → parecía que el logo "se perdía" al reabrir el wizard.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> montar(
    WidgetTester tester, {
    bool oscuro = false,
    String? logoUrl,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final form = CompanySetupForm(
      localeController: LocaleController(),
      logoUrlExistente: logoUrl,
      initial: const CompanySetupData(nombreFiscal: 'Mi Empresa'),
      onSubmit: (_) async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: oscuro ? ThemeMode.dark : ThemeMode.light,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 560,
              height: 680,
              child: form,
            ),
          ),
        ),
      ),
    );
  }

  Text tituloDelCuerpo(WidgetTester tester, String clave) {
    return tester
        .widgetList<Text>(find.text(AppTranslations.tr(clave)))
        .firstWhere((t) => t.style?.fontSize == 18);
  }

  testWidgets('tema claro: el título del paso no usa blanco', (tester) async {
    await montar(tester);
    final titulo = tituloDelCuerpo(tester, 'initial_setup_step_company');
    expect(titulo.style?.color, isNot(Colors.white),
        reason: 'bug 1: texto blanco sobre fondo claro es ilegible');
  });

  testWidgets('Continuar avanza el PageView al paso 2 (una sola pulsación)',
      (tester) async {
    await montar(tester);

    // Paso 1: ningún selector (paso 2) debe ser tocable todavía.
    expect(find.byType(DropdownButtonFormField<String>).hitTestable(),
        findsNothing);

    // Bug 2: con el PageView sin mover, esta pulsación no cambiaba de página.
    await tester.tap(find.byKey(const Key('empresa_continuar_btn')));
    await tester.pumpAndSettle();

    // Paso 2 visible: 3 selectores (boleto, reporte, idioma) tocables.
    expect(find.byType(DropdownButtonFormField<String>).hitTestable(),
        findsNWidgets(3));
    expect(find.byKey(const Key('empresa_continuar_btn')), findsOneWidget);
    expect(find.byKey(const Key('empresa_finalizar_btn')), findsNothing);
  });

  testWidgets('Continuar 2ª vez llega al paso 3 con botón Finalizar',
      (tester) async {
    await montar(tester);

    await tester.tap(find.byKey(const Key('empresa_continuar_btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('empresa_continuar_btn')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('empresa_finalizar_btn')), findsOneWidget);
    // Campo de carpeta de reportes (paso 3) visible.
    final campo = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '',
    ).hitTestable();
    expect(campo, findsWidgets);
  });

  testWidgets('Atrás vuelve al paso anterior', (tester) async {
    await montar(tester);

    await tester.tap(find.byKey(const Key('empresa_continuar_btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('empresa_continuar_btn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('empresa_finalizar_btn')), findsOneWidget);

    await tester.tap(
      find
          .widgetWithText(OutlinedButton, AppTranslations.tr('btn_back'))
          .hitTestable(),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('empresa_finalizar_btn')), findsNothing);
  });

  testWidgets('muestra el logo ya guardado (URL remota)', (tester) async {
    const url = 'http://127.0.0.1:8000/media/empresa/logo.png';
    await montar(tester, logoUrl: url);

    final imagen = find.byWidgetPredicate(
      (w) => w is Image && w.image is NetworkImage && (w.image as NetworkImage).url == url,
    );
    expect(imagen, findsOneWidget,
        reason: 'bug 3: el logo existente debe mostrarse como referencia');
  });
}