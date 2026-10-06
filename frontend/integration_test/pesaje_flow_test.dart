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

/// E2E de la estación (H2b): un recorrido real contra la API.
///
///   login → módulo Entradas → crear pesaje de entrada → registrar salida
///   → verificar el boleto CERRADO en el historial
///
/// Dos modos, según el entorno:
///
/// * `seed` (por defecto, el que usa la CI): la app se configura en memoria
///   con la empresa sembrada por `backend/scripts/seed_e2e_flutter.py`
///   (admin@balansoft.demo / demo1234). El entorno lo levanta
///   `backend/scripts/e2e_flutter.sh up` (BD propia + stub del LM) y la empresa
///   **no tiene básculas**, por lo que el formulario habilita el peso manual.
/// * `instalada`: contra una estación ya instalada (BD y licencia reales). No
///   se pisa ninguna preferencia; las credenciales llegan por
///   `--dart-define` para no versionar secretos.
///
/// No cubre instalación (el rol lo decide el instalador y la app arranca en el
/// login), multiidioma, kiosk ni báscula física.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const instalada = bool.fromEnvironment('E2E_INSTALADA');
  const email =
      String.fromEnvironment('E2E_EMAIL', defaultValue: 'admin@balansoft.demo');
  const pass =
      String.fromEnvironment('E2E_PASS', defaultValue: 'demo1234');
  const baseUrl = String.fromEnvironment(
      'E2E_BASE_URL', defaultValue: 'http://localhost:8000');

  // `pumpAndSettle` normal se queda corto con la red real (login, catálogos,
  // alta del boleto), así que se acota por paso con un plazo de 2 minutos.
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
    // Un spinner en pantalla significa que aún hay una request en vuelo.
    for (var i = 0;
        i < 80 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle(paso, EnginePhase.sendSemanticsUpdate, maxPaso);
    }
  }

  /// Vuelca lo que hay en pantalla: en un fallo de E2E el mensaje de la UI
  /// (snackbar, error de red) suele ser la única pista.
  void volcar(WidgetTester tester, String paso) {
    final textos = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .take(40)
        .toList();
    debugPrint('[E2E $paso] $textos');
  }

  /// Toca un widget llevándolo antes al centro de la vista: los módulos usan
  /// listas con scroll y el botón puede quedar fuera del viewport.
  Future<void> tocar(WidgetTester tester, Finder finder) async {
    expect(finder, findsWidgets, reason: 'no se encontró el widget a tocar');
    await tester.ensureVisible(finder.first);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.tap(finder.first);
    await asentar(tester);
  }

  Future<void> esperar(WidgetTester tester, Finder finder,
      {String? porque, Duration duracion = const Duration(seconds: 45)}) async {
    final limite = DateTime.now().add(duracion);
    while (DateTime.now().isBefore(limite)) {
      await tester.pump(const Duration(milliseconds: 120));
      if (finder.evaluate().isNotEmpty) return;
    }
    volcar(tester, 'esperando ${porque ?? finder}');
    fail('No apareció ${porque ?? finder.toString()}');
  }

  testWidgets('Login → entrada → salida → CERRADO en el historial',
      (tester) async {
    // La estación se opera en escritorio; el tamaño real lo fija el gestor de
    // ventanas, así que se fuerza también el viewport del test para que el
    // hit-testing coincida con lo que ve el operador.
    await windowManager.setSize(const Size(1400, 860));
    tester.view.physicalSize = const Size(1400, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Siempre: `logout` y los setters usan las preferencias reales. En modo
    // instalada se activa la migración única del legado, igual que `main()`.
    await AppConfig.init(migrarLegado: instalada);

    if (!instalada) {
      // Se asignan los campos estáticos DIRECTAMENTE (no los setters) para no
      // escribir en las preferencias reales: correr el E2E seed en una máquina
      // con la estación instalada no debe falsear su estado de instalación.
      // El rol del instalador se fija en memoria: la app arranca en el login.
      AppConfig.rol = StationRole.servidor;
      AppConfig.onboardingCompletado = true;
      AppConfig.apiBaseUrl = baseUrl;
      AppConfig.offline = false;
      AppConfig.wserverAutostart = false;
    }

    // El login de una estación SERVIDOR es CENTRAL-first y `serverApiUrl` está
    // fijado de fábrica al central de producción. El E2E va contra la API de la
    // estación: sin central, el login va directo contra la API local.
    AppConfig.serverApiUrl = null;

    await app.themeController.load();
    await di.init();
    // Misma secuencia que `main()`: el MaterialApp raíz usa el locale global.
    app.localeController = di.sl<LocaleController>();
    await app.localeController.load();
    AppTranslations.setController(app.localeController);

    // Sesión limpia: sin esto el arranque puede restaurar el token de una
    // corrida anterior y saltar el login.
    await di.sl<LogoutUseCase>().execute();
    AppConfig.serverApiUrl = null;

    await tester.pumpWidget(const app.BalansoftApp());
    await asentar(tester);

    // ── 1. Login ──────────────────────────────────────────────────────────
    expect(find.byKey(const Key('email_field')), findsOneWidget,
        reason: 'la app debe abrir en /login con la estación ya configurada');
    await tester.enterText(find.byKey(const Key('email_field')), email);
    await tester.enterText(find.byKey(const Key('password_field')), pass);
    await tocar(tester, find.byKey(const Key('login_button')));

    // ── 2. Módulo Entradas (historial de boletos) ─────────────────────────
    await esperar(tester, find.byKey(const Key('menu_grupo_REPORTES')),
        porque: 'el menú lateral con el dashboard cargado');
    // "Ingresos (Entradas)" vive dentro del grupo REPORTES: si el grupo está
    // plegado se despliega primero.
    if (find.byKey(const Key('menu_entradas')).evaluate().isEmpty) {
      await tocar(tester, find.byKey(const Key('menu_grupo_REPORTES')));
    }
    await esperar(tester, find.byKey(const Key('menu_entradas')),
        porque: 'la entrada de Ingresos en el menú');
    await tocar(tester, find.byKey(const Key('menu_entradas')));
    await esperar(tester, find.byKey(const Key('nuevo_pesaje_btn')),
        porque: 'la lista de ingresos');

    // ── 3. Captura de entrada (peso manual: la empresa no tiene básculas) ──
    // Placa única por corrida: un reintento no debe encontrar dos filas.
    final placa = 'E2E-${DateTime.now().millisecondsSinceEpoch % 100000}';
    await tocar(tester, find.byKey(const Key('nuevo_pesaje_btn')));

    expect(find.byKey(const Key('placa_field')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('placa_field')), placa);
    await asentar(tester);
    await tester.enterText(find.byKey(const Key('peso_entrada_field')), '15000');
    await asentar(tester);

    // Sin báscula, "Capturar peso" fija el tecleo manual (F3 del operador).
    await tocar(tester, find.byKey(const Key('capturar_peso_button')));
    await tocar(tester, find.byKey(const Key('guardar_toolbar_button')));

    // Confirmación de guardado → la API responde con el número de boleto.
    await esperar(tester, find.byKey(const Key('dialogo_confirmar_guardado_btn')),
        porque: 'la confirmación de guardado');
    await tocar(tester, find.byKey(const Key('dialogo_confirmar_guardado_btn')));

    // Sin impresión: seguimos en el formulario para registrar la salida.
    await esperar(tester, find.byKey(const Key('dialogo_nuevo_peso_btn')),
        porque: 'la pregunta de impresión tras guardar la entrada');
    await tocar(tester, find.byKey(const Key('dialogo_nuevo_peso_btn')));

    // ── 4. Cierre: elegir el boleto pendiente y capturar la salida ─────────
    await tocar(tester, find.byKey(const Key('salida_toolbar_button')));

    final fila = find.byKey(Key('boleto_pendiente_$placa'));
    await esperar(tester, fila,
        porque: 'el boleto de entrada $placa pendiente de salida');
    await tocar(tester,
        find.descendant(of: fila, matching: find.byType(FilledButton)));

    expect(find.byKey(const Key('peso_salida_field')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('peso_salida_field')), '13800');
    await asentar(tester);

    await tocar(tester, find.byKey(const Key('guardar_toolbar_button')));
    await esperar(tester, find.byKey(const Key('dialogo_confirmar_guardado_btn')),
        porque: 'la confirmación de guardado de la salida');
    await tocar(tester, find.byKey(const Key('dialogo_confirmar_guardado_btn')));
    await esperar(tester, find.byKey(const Key('dialogo_nuevo_peso_btn')),
        porque: 'la pregunta de impresión tras cerrar el pesaje');
    await tocar(tester, find.byKey(const Key('dialogo_nuevo_peso_btn')));

    // ── 5. El historial debe mostrar el boleto ya cerrado ─────────────────
    await tocar(tester, find.byKey(const Key('salir_toolbar_button')));

    final filaCerrada = find.byKey(Key('boleto_fila_$placa'));
    final limite = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(limite) &&
        filaCerrada.evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    if (filaCerrada.evaluate().isEmpty) {
      // El listado puede quedar desactualizado al volver del formulario: se
      // fuerza el reingreso al módulo (mismo camino que usa el operador).
      volcar(tester, 'historial desactualizado');
      await tocar(tester, find.byKey(const Key('menu_inicio')));
      await tocar(tester, find.byKey(const Key('menu_entradas')));
      await esperar(tester, filaCerrada,
          porque: 'el boleto $placa en el historial de entradas');
    }
    expect(filaCerrada, findsOneWidget);
    expect(
      find.descendant(
          of: filaCerrada,
          matching: find.textContaining('CERRADO')),
      findsWidgets,
      reason: 'el boleto de la placa $placa debe verse como cerrado '
          '',
    );
    expect(
      find.descendant(of: filaCerrada, matching: find.textContaining('TA-')),
      findsWidgets,
      reason: 'la fila debe mostrar el número de boleto asignado',
    );
    debugPrint('[E2E] boleto $placa cerrado y verificado en el historial');
  }, timeout: const Timeout(Duration(minutes: 15)));
}