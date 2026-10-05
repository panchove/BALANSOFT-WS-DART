// T10b · Casos 1, 2, 4 y 5 — `specs/001-tipografia-config/tasks.md §11`.
//
//   * Caso 1: las 4 pantallas críticas a 1.40, tema claro   (REQ-FN-008 / CE-02)
//   * Caso 2: las 4 pantallas críticas a 0.85, tema oscuro (REQ-FN-008 / CE-01)
//   * Caso 4: cambio de idioma con el tamaño en el extremo  (REQ-FN-019 / CE-11)
//   * Caso 5: familia `Serif`, que el sistema puede no tener instalada
//                                                          (REQ-FN-006 / CE-03)
//
// Los casos 3 (contraste AA) y 6 (iconos escalados) NO son E2E: son propiedades
// del tema, no de una pantalla, y se comprueban en
// `test/typography/t10b_contrast_test.dart` y `test/typography/t10b_iconos_test.dart`.
//
// Toda la lógica de recorrido y de captura de `RenderFlex overflowed` está en
// `t10b_harness.dart`; aquí solo se declaran los casos y se comprueba el
// veredicto. Cada caso monta la estación desde cero, con la sesión limpia.
//
// ⚠️ Regla dura (`tasks.md §11`): si aparece un overflow, este archivo falla y
// se REPORTA. No se parchea ningún layout (`spec.md §4.2` punto 4).

import 'package:balansoft_ws/core/i18n/locale_controller.dart';
import 'package:balansoft_ws/core/i18n/translations.dart';
import 'package:balansoft_ws/core/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balansoft_ws/presentation/screens/settings/typography_settings_screen.dart';
import 'package:integration_test/integration_test.dart';

import 't10b_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Las etiquetas que deben verse en cada idioma (REQ-FN-019). Se leen de la
  // pantalla, no del diccionario: un `.tr()` que devuelve la clave, o un idioma
  // que no llega a aplicarse, rompería este caso.
  //
  // El subtítulo («Familia, tamaño y ticket PDF») NO va aquí a propósito: es el
  // subtítulo de la entrada del hub de Ajustes, no de la pantalla de
  // tipografía. Comprobarlo exigiría medir la hub, y el hub ya queda registrado
  // como pantalla `ajustes`.
  const es = [
    'Tipografía',
    'Familia de letra de la interfaz',
    'Tamaño del texto de la interfaz',
    'Vista previa',
    'Sistema (por defecto)',
    'Sans Serif',
    'Serif',
    'Monospace',
    'Roboto',
    'Tamaño del ticket PDF',
    'Fuente del ticket PDF',
    'DejaVu (fija, no configurable)',
  ];
  const en = [
    'Typography',
    'Interface font family',
    'Interface text size',
    'Preview',
    'System (default)',
    'Sans Serif',
    'Serif',
    'Monospace',
    'Roboto',
    'Ticket PDF size',
    'Ticket PDF font',
    'DejaVu (fixed, not configurable)',
  ];
  const pt = [
    'Tipografia',
    'Família de letra da interface',
    'Tamanho do texto da interface',
    'Pré-visualização',
    'Sistema (padrão)',
    'Sans Serif',
    'Serif',
    'Monoespaçada',
    'Roboto',
    'Tamanho do ticket PDF',
    'Fonte do ticket PDF',
    'DejaVu (fixa, não configurável)',
  ];

  final casos = <CasoT10b>[
    // ── Caso 1 · extremo superior, tema claro ──────────────────────────────
    const CasoT10b(
      numero: 1,
      titulo: 'las 4 pantallas críticas a 1.40, tema claro',
      factor: 1.40,
      tema: TemaApp.claro,
      idiomas: [AppLanguage.es],
      etiquetasPorIdioma: {AppLanguage.es: es},
    ),

    // ── Caso 2 · extremo inferior, tema oscuro ─────────────────────────────
    const CasoT10b(
      numero: 2,
      titulo: 'las 4 pantallas críticas a 0.85, tema oscuro',
      factor: 0.85,
      tema: TemaApp.oscuro,
      idiomas: [AppLanguage.es],
      etiquetasPorIdioma: {AppLanguage.es: es},
    ),

    // ── Caso 4 · cambio de idioma en el extremo ────────────────────────────
    // El factor se queda en 1.40: es el extremo donde una etiqueta larga se
    // desborda antes. Se recorre es → en → pt.
    const CasoT10b(
      numero: 4,
      titulo: 'cambio de idioma con el tamaño en el extremo',
      factor: 1.40,
      tema: TemaApp.claro,
      idiomas: [AppLanguage.es, AppLanguage.en, AppLanguage.pt],
      etiquetasPorIdioma: {
        AppLanguage.es: es,
        AppLanguage.en: en,
        AppLanguage.pt: pt,
      },
    ),

    // ── Caso 5 · familia que el sistema puede no tener ────────────────────
    const CasoT10b(
      numero: 5,
      titulo: 'familia Serif: cae a la del sistema sin error',
      factor: 1.40,
      tema: TemaApp.claro,
      familia: 'SERIF',
      idiomas: [AppLanguage.es],
      etiquetasPorIdioma: {AppLanguage.es: es},
    ),
  ];

  // `di.init()` registra singletons en GetIt y llamarlo dos veces lanza
  // «ApiClient is already registered». El proceso se prepara una vez y cada caso
  // solo monta su estación encima.
  setUpAll(iniciarProceso);

  for (final caso in casos) {
    testWidgets('T10b caso ${caso.numero}: ${caso.titulo}', (tester) async {
      final inf = InformeT10b(caso);
      capturarOverflows(inf);

      await montarEstacion(tester, caso);

      // El factor se midió, no se imprimió: `factorEfectivo` lee el
      // `MediaQuery` del árbol montado, que es el que usa cada `Text`.
      registrar(tester, inf, 'login', alcanzada: true);

      await asentar(tester, duracion: const Duration(seconds: 10));

      // ── Las 4 pantallas de REQ-FN-008 ───────────────────────────────────
      await irAPanel(tester, inf);
      await irAAjustes(tester, inf);
      await abrirDetalleDeBoletoNuevo(tester, inf);

      // ── Caso 4 · etiquetas en cada idioma ────────────────────────────────
      // El idioma inicial del caso también se comprueba: es el que se ve sin
      // cambiar nada, y en los casos 1, 2 y 5 es el único idioma.
      if (await irAAjustes(tester, inf, registrarPantalla: false)) {
        await comprobarEtiquetasTipografia(tester, inf, caso.idiomas.first);
      }
      for (final destino in caso.idiomas.skip(1)) {
        await comprobarIdioma(tester, inf, destino: destino);
      }

      // ── Caso 5 · elegir `Serif` y comprobar que no rompe nada ──────────
      if (caso.numero == 5) {
        await comprobarFamiliaSerif(tester, inf);
      }

      inf.volcar();

      // ── Criterio de salida (binario) ────────────────────────────────────
      // El overflow va primero: es el criterio que manda (`tasks.md §11`).
      expect(
        inf.overflowos,
        isEmpty,
        reason: 'T10b caso ${caso.numero}: ${inf.overflowos.length} desborde(s) '
            'en las pantallas ${inf.pantallas.keys.toList()}. '
            'REPORTA y PARA; no se parchea el layout.\n'
            '${inf.overflowos.join("\n")}',
      );

      // Una pantalla no alcanzada NO está certificada: "no vi overflow" no es
      // lo mismo que "no lo vi" (el mismo defecto que dejó `detalle_boleto`
      // sin medir en T1).
      expect(
        inf.pantallasNoAlcanzadas,
        isEmpty,
        reason: 'T10b caso ${caso.numero}: sin certificar '
            '${inf.pantallasNoAlcanzadas.join(", ")}\n${inf.fallos.join("\n")}',
      );

      // El factor efectivo debe ser el del caso. Si el SO aporta un factor
      // distinto, el caso no midió lo que dice medir.
      expect(
        inf.factores.values,
        isNotEmpty,
        reason: 'no se midió ningún factor efectivo',
      );
      for (final e in inf.factores.entries) {
        expect(
          e.value,
          closeTo(caso.factor, 0.001),
          reason: 'en ${e.key} el factor efectivo fue ${e.value} y el caso pide '
              '${caso.factor}',
        );
      }

      // El tema efectivo debe ser el pedido.
      for (final e in inf.temas.entries) {
        expect(
          e.value,
          caso.tema == TemaApp.oscuro ? Brightness.dark : Brightness.light,
          reason: 'en ${e.key} el tema efectivo fue ${e.value.name} y el caso '
              'pide ${caso.tema.name}',
        );
      }

      // Las etiquetas del ajuste se leyeron en cada idioma pedido.
      for (final idioma in caso.idiomas) {
        final vistas = inf.etiquetas[idioma.name] ?? const <String>[];
        expect(
          vistas.length,
          (caso.etiquetasPorIdioma[idioma] ?? const <String>[]).length,
          reason: 'en ${idioma.name} solo se leyeron ${vistas.length} de '
              '${(caso.etiquetasPorIdioma[idioma] ?? const <String>[]).length} '
              'etiquetas del ajuste\n${inf.fallos.join("\n")}',
        );
      }

      // Ningún fallo de recorrido (ni el cambio de idioma, ni las etiquetas).
      expect(
        inf.fallos.where((f) => !f.contains('no se alcanzó')).toList(),
        isEmpty,
        reason: 'T10b caso ${caso.numero}: fallos de recorrido\n'
            '${inf.fallos.join("\n")}',
      );
    }, timeout: const Timeout(Duration(minutes: 25)));
  }
}

/// Caso 5: elige `Serif` en el ajuste y comprueba que la pantalla sobrevive.
///
/// "Sin error y sin diálogo" (CE-03) se comprueba por dos vías independientes:
/// que no salte ninguna excepción de Flutter durante la interacción, y que no
/// aparezca un diálogo de error ni un aviso de fallo.
Future<void> comprobarFamiliaSerif(WidgetTester tester, InformeT10b inf) async {
  if (!await irAAjustes(tester, inf, registrarPantalla: false)) {
    inf.fallos.add('caso 5: no se volvió a Ajustes para elegir Serif');
    return;
  }
  await comprobarEtiquetasTipografia(tester, inf, AppLanguage.es);

  // El título ya no está en pantalla (se volvió atrás): se reabre y se elige.
  final titulo = AppTranslations.tr('tipografia_titulo');
  final entrada = find.widgetWithText(ListTile, titulo);
  if (entrada.evaluate().isEmpty) {
    inf.fallos.add('caso 5: no se encontró la entrada «$titulo»');
    return;
  }
  await tocar(tester, entrada);
  if (!await esperar(tester, find.byType(TypographySettingsScreen),
      porque: 'la pantalla de tipografía del caso 5')) {
    inf.fallos.add('caso 5: no se abrió la pantalla de tipografía');
    return;
  }
  await asentar(tester, duracion: const Duration(seconds: 8));

  final antes = tester.takeException();
  final dialogosAntes = find.byType(AlertDialog).evaluate().length;

  await tocar(tester, find.text('Serif'));
  await asentar(tester, duracion: const Duration(seconds: 10));

  // La familia quedó aplicada…
  registrar(tester, inf, 'familia_serif', alcanzada: true);
  // …y nada explotó: ni excepción, ni diálogo nuevo, ni snackbar de error.
  expect(antes, isNull, reason: 'caso 5: ya había excepción antes de Serif');
  expect(tester.takeException(), isNull,
      reason: 'caso 5: elegir Serif lanzó una excepción (REQ-FN-006)');
  expect(find.byType(AlertDialog).evaluate().length, dialogosAntes,
      reason: 'caso 5: elegir Serif abrió un diálogo de error (CE-03)');

  await volverAtras(tester);
}
