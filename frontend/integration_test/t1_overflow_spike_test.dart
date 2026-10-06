// SPIKE T1 — DESCARTABLE. NO COMMITEAR.
//
// Mide el número de eventos `RenderFlex overflowed` con el factor de texto en
// 1.40 (extremo superior del selector) en las 4 pantallas críticas de
// REQ-FN-008. Único entregable: el entero `overflow_count` y el reporte por
// ocurrencia. Criterio de salida binario en `tasks.md §1`:
//
//   overflow_count == 0  → T1 pasa
//   overflow_count  > 0  → PARAR y reabrir la pregunta 5 de spec.md §3
//
// El factor se inyecta con `platformDispatcher.textScaleFactorTestValue`, que
// es el factor de accesibilidad del SO: es lo que `MediaQuery.fromView`
// convierte en `textScaler`, y por tanto lo que llega a TODOS los `Text`,
// incluidos los de tamaño fijo (H-1). No se toca código de producción.

import 'package:balansoft_ws/core/config/app_config.dart';
import 'package:balansoft_ws/core/config/station_config.dart';
import 'package:balansoft_ws/core/i18n/locale_controller.dart';
import 'package:balansoft_ws/core/i18n/translations.dart';
import 'package:balansoft_ws/domain/usecases/auth_usecases.dart';
import 'package:balansoft_ws/injection.dart' as di;
import 'package:balansoft_ws/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const email = 'admin@balansoft.demo';
  const pass = 'demo1234';
  const baseUrl = String.fromEnvironment(
      'E2E_BASE_URL', defaultValue: 'http://localhost:8000');

  /// Factor bajo medición: extremo superior del selector (spec.md §3, P2).
  const factor = 1.40;

  /// Una entrada por overflow: `pantalla :: mensaje exacto`.
  final overflowos = <String>[];
  /// Pantallas alcanzadas de verdad; una no alcanzada NO se puede certificar.
  final alcanzadas = <String>[];
  final noAlcanzadas = <String>[];
  String actual = 'arranque';

  testWidgets('T1 SPIKE: overflow_count a factor 1.40', (tester) async {
    // ── Captura de `RenderFlex overflowed` ──────────────────────────────────
    // Se capturan los overflows y se delegan el resto de errores al manejador
    // original: si el spike se traga cualquier otra excepción, un fallo real
    // pasaría por bueno.
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final texto = details.exceptionAsString();
      if (texto.contains('overflowed')) {
        // El mensaje de Flutter solo da píxeles y dirección. El criterio de
        // salida exige además el widget y su fila/columna: se extraen del
        // nodo de diagnóstico del error.
        final nodo = details.context;
        final donde = nodo == null ? 'contexto:null' : nodo.toString();
        // `DiagnosticsNode` no expone el objeto; se usa el propio renderer del
        // nodo, que ya incluye el tipo del widget y su configuracion.
        final tipo = nodo == null
            ? 'sin objeto'
            : nodo.toDescription().split('\n').first.trim();
        overflowos.add('$actual :: $texto :: widget=$tipo :: $donde');
      } else {
        originalOnError?.call(details);
      }
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    const paso = Duration(milliseconds: 100);
    const maxPaso = Duration(minutes: 2);

    Future<void> asentar(WidgetTester tester,
        {Duration duracion = const Duration(seconds: 25)}) async {
      final limite = DateTime.now().add(duracion);
      while (DateTime.now().isBefore(limite)) {
        await tester.pump(const Duration(milliseconds: 120));
        if (!tester.binding.hasScheduledFrame) return;
      }
      await tester.pumpAndSettle(paso, EnginePhase.sendSemanticsUpdate, maxPaso);
      for (var i = 0;
          i < 80 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
          i++) {
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pumpAndSettle(paso, EnginePhase.sendSemanticsUpdate, maxPaso);
      }
    }

    Future<bool> tocar(WidgetTester tester, Finder finder) async {
      if (finder.evaluate().isEmpty) {
        debugPrint('[T1] no se encontró ${finder.toString()}');
        return false;
      }
      await tester.ensureVisible(finder.first);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(finder.first);
      await asentar(tester);
      return true;
    }

    /// Vuelca lo visible: en un spike, un widget ausente hay que poder nombrarlo.
    void volcar(WidgetTester tester, String paso) {
      final textos = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .take(25)
          .toList();
      debugPrint('[T1 $paso] $textos');
    }

    Future<bool> esperar(WidgetTester tester, Finder finder,
        {String? porque, Duration duracion = const Duration(seconds: 45)}) async {
      final limite = DateTime.now().add(duracion);
      while (DateTime.now().isBefore(limite)) {
        await tester.pump(const Duration(milliseconds: 120));
        if (finder.evaluate().isNotEmpty) return true;
      }
      debugPrint('[T1] no apareció ${porque ?? finder.toString()}');
      return false;
    }

    /// Registra una pantalla: alcanzada o no. Una no alcanzada se reporta
    /// aparte porque "no vi overflow" no es lo mismo que "no lo vi".
    void registrar(String pantalla, bool ok) {
      (ok ? alcanzadas : noAlcanzadas).add(pantalla);
      actual = pantalla;
    }

    // ── Entorno ────────────────────────────────────────────────────────────
    await windowManager.setSize(const Size(1400, 860));
    tester.view.physicalSize = const Size(1400, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // El factor se fija ANTES de pumpWidget para que lo herede el MediaQuery
    // raíz del MaterialApp.
    tester.platformDispatcher.textScaleFactorTestValue = factor;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    await AppConfig.init();

    // Modo seed: campos estáticos directos, sin escribir en las preferencias
    // reales (misma razón que el E2E de UI). El rol del instalador se fija en
    // memoria; la app arranca igualmente en el login.
    AppConfig.rol = StationRole.servidor;
    AppConfig.onboardingCompletado = true;
    AppConfig.apiBaseUrl = baseUrl;
    AppConfig.offline = false;
    AppConfig.wserverAutostart = false;
    AppConfig.serverApiUrl = null;

    await app.themeController.load();
    await di.init();
    app.localeController = di.sl<LocaleController>();
    await app.localeController.load();
    AppTranslations.setController(app.localeController);

    await di.sl<LogoutUseCase>().execute();
    AppConfig.serverApiUrl = null;

    await tester.pumpWidget(const app.BalansoftApp());
    await asentar(tester);

    debugPrint('[T1] textScaler efectivo = '
        '${tester.platformDispatcher.textScaleFactor}');

    // ── Login ──────────────────────────────────────────────────────────────
    final okLogin = await esperar(tester, find.byKey(const Key('email_field')));
    registrar('login', okLogin);
    if (!okLogin) return;
    await tester.enterText(find.byKey(const Key('email_field')), email);
    await tester.enterText(find.byKey(const Key('password_field')), pass);
    await tocar(tester, find.byKey(const Key('login_button')));
    registrar('panel_principal', true);
    await esperar(tester, find.byKey(const Key('menu_inicio')),
        porque: 'el menú lateral');

    // El menú lateral puede estar plegado: se abre antes de navegar.
    if (find.byKey(const Key('menu_inicio')).evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 300));
    }

    // ── Pantalla 1: panel principal (dashboard) ────────────────────────────
    if (await esperar(tester, find.byKey(const Key('menu_inicio')))) {
      await tocar(tester, find.byKey(const Key('menu_inicio')));
      await asentar(tester, duracion: const Duration(seconds: 8));
      registrar('panel_principal', true);
    } else {
      registrar('panel_principal', false);
    }

    // ── Pantalla 2: ajustes ────────────────────────────────────────────────
    if (find.byKey(const Key('menu_configuracion')).evaluate().isEmpty) {
      await tocar(tester, find.byKey(const Key('menu_grupo_MANTENIMIENTO')));
    }
    if (await esperar(tester, find.byKey(const Key('menu_configuracion')))) {
      await tocar(tester, find.byKey(const Key('menu_configuracion')));
      await asentar(tester, duracion: const Duration(seconds: 8));
      registrar('ajustes', true);
    } else {
      registrar('ajustes', false);
    }

    // ── Pantalla 3: formulario de pesaje ───────────────────────────────────
    if (find.byKey(const Key('menu_entradas')).evaluate().isEmpty) {
      await tocar(tester, find.byKey(const Key('menu_grupo_REPORTES')));
    }
    var okEntradas = await esperar(tester, find.byKey(const Key('menu_entradas')));
    if (okEntradas) await tocar(tester, find.byKey(const Key('menu_entradas')));
    okEntradas = okEntradas &&
        await esperar(tester, find.byKey(const Key('nuevo_pesaje_btn')));
    if (okEntradas) {
      await tocar(tester, find.byKey(const Key('nuevo_pesaje_btn')));
      final placa = 'T1-${DateTime.now().millisecondsSinceEpoch % 100000}';
      await tester.enterText(find.byKey(const Key('placa_field')), placa);
      await asentar(tester);
      registrar('formulario_pesaje', true);

      // El detalle del boleto requiere un boleto EXISTENTE: si no se guarda,
      // la pantalla 4 nunca llega a renderizarse y quedaría sin medir.
      // Se replica el flujo del E2E de UI: peso manual -> capturar -> guardar
      // -> confirmar -> descartar impresion -> salir al listado -> abrir fila.
      await tester.enterText(find.byKey(const Key('peso_entrada_field')), '15000');
      await asentar(tester);
      await tocar(tester, find.byKey(const Key('capturar_peso_button')));
      await tocar(tester, find.byKey(const Key('guardar_toolbar_button')));
      final okConf = await esperar(
          tester, find.byKey(const Key('dialogo_confirmar_guardado_btn')));
      debugPrint('[T1] diálogo de confirmación de guardado: $okConf');
      if (okConf) {
        await tocar(
            tester, find.byKey(const Key('dialogo_confirmar_guardado_btn')));
        final okImp = await esperar(
            tester, find.byKey(const Key('dialogo_nuevo_peso_btn')));
        debugPrint('[T1] diálogo de impresión: $okImp');
        if (okImp) {
          await tocar(tester, find.byKey(const Key('dialogo_nuevo_peso_btn')));
        }
      }
      await asentar(tester);

      // El cierre (salida) es lo que hace que el boleto aparezca en el
      // historial. Con la entrada sola queda PENDIENTE y la corrida anterior
      // dejo `detalle_boleto` sin medir: 3 de 4 pantallas, no 4. Se replica el
      // flujo del E2E de UI, que si llega al historial.
      await tocar(tester, find.byKey(const Key('salida_toolbar_button')));
      final filaPendiente = find.byKey(Key('boleto_pendiente_$placa'));
      final okPendiente = await esperar(tester, filaPendiente,
          porque: 'el boleto de entrada $placa pendiente de salida',
          duracion: const Duration(seconds: 25));
      debugPrint('[T1] boleto pendiente de salida: $okPendiente');
      if (okPendiente) {
        await tocar(tester,
            find.descendant(of: filaPendiente, matching: find.byType(FilledButton)));
        if (find.byKey(const Key('peso_salida_field')).evaluate().isNotEmpty) {
          await tester.enterText(find.byKey(const Key('peso_salida_field')), '13800');
          await asentar(tester);
          await tocar(tester, find.byKey(const Key('guardar_toolbar_button')));
          if (await esperar(tester, find.byKey(const Key('dialogo_confirmar_guardado_btn')),
              duracion: const Duration(seconds: 20))) {
            await tocar(tester, find.byKey(const Key('dialogo_confirmar_guardado_btn')));
            if (await esperar(tester, find.byKey(const Key('dialogo_nuevo_peso_btn')),
                duracion: const Duration(seconds: 20))) {
              await tocar(tester, find.byKey(const Key('dialogo_nuevo_peso_btn')));
            }
          }
        }
      }
      await asentar(tester);
      await tocar(tester, find.byKey(const Key('salir_toolbar_button')));
      await asentar(tester);
      // Tras el cierre el boleto vive en SALIDAS (`estadoInicial: 'CERRADO'`),
      // no en ENTRADAS: se busca en los dos listados. La corrida anterior solo
      // miraba ENTRADAS y por eso `detalle_boleto` quedaba sin medir.
      var okDetalle = await esperar(tester, find.byKey(Key('boleto_fila_$placa')),
          porque: 'la fila del boleto cerrado en ENTRADAS',
          duracion: const Duration(seconds: 10));
      if (!okDetalle) {
        await tocar(tester, find.byKey(const Key('menu_salidas')));
        okDetalle = await esperar(tester, find.byKey(Key('boleto_fila_$placa')),
            porque: 'la fila del boleto cerrado en SALIDAS',
            duracion: const Duration(seconds: 20));
      }
      if (!okDetalle) {
        volcar(tester, 'historial sin la fila');
        // `menu_inicio` puede no estar construido: el sidebar es lazy y tras
        // navegar queda scrolleado. `menu_entradas` sí es visible.
        if (find.byKey(const Key('menu_entradas')).evaluate().isEmpty) {
          await tocar(tester, find.byKey(const Key('menu_grupo_REPORTES')));
        }
        if (await tocar(tester, find.byKey(const Key('menu_entradas')))) {
          okDetalle = await esperar(tester, find.byKey(Key('boleto_fila_$placa')),
              porque: 'la fila tras reingresar a Entradas',
              duracion: const Duration(seconds: 25));
        }
      }
      registrar('detalle_boleto', okDetalle);
      if (okDetalle) {
        // Se abre la fila: su `ListTile` lleva al detalle del boleto.
        await tocar(tester, find.byKey(Key('boleto_fila_$placa')));
        await asentar(tester, duracion: const Duration(seconds: 8));
        registrar('detalle_boleto', true);
      }
    } else {
      registrar('formulario_pesaje', false);
      registrar('detalle_boleto', false);
    }

    // ── Reporte ────────────────────────────────────────────────────────────
    debugPrint('=== T1 REPORTE ===');
    debugPrint('factor_medido: $factor');
    debugPrint('pantallas_alcanzadas: ${alcanzadas.join(", ")}');
    debugPrint('pantallas_no_alcanzadas: ${noAlcanzadas.join(", ")}');
    debugPrint('overflow_count: ${overflowos.length}');
    for (final o in overflowos) {
      debugPrint('OVERFLOW :: $o');
    }
    debugPrint('=== FIN T1 ===');
  }, timeout: const Timeout(Duration(minutes: 20)));
}