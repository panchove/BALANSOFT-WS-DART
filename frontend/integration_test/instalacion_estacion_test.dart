import 'package:balansoft_ws/core/config/app_config.dart';
import 'package:balansoft_ws/domain/usecases/auth_usecases.dart';
import 'package:balansoft_ws/injection.dart' as di;
import 'package:balansoft_ws/main.dart' as app;
import 'package:balansoft_ws/presentation/screens/dashboard/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

/// E2E de **instalación real** de la estación (modo SERVIDOR).
///
///   preferencias → modo servidor → verificación de entorno → activar cuenta
///   → datos de empresa (precargados del central) → dashboard
///
/// A diferencia de [pesaje_flow_test.dart], este piloto **no fuerza**
/// `serverApiUrl = null`: valida la cuenta contra el servidor central real y
/// exige que el WServer local esté levantado (el de la instalación, con la BD
/// ya inicializada).
///
/// Las credenciales se inyectan por `--dart-define` para no versionar secretos:
///
///   flutter test integration_test/instalacion_estacion_test.dart -d linux \
///     --dart-define=REAL_EMAIL=... --dart-define=REAL_PASS=...
///
/// Sin esas variables el test se omite (`skip`), así que `flutter test` y la CI
/// no se ven afectados.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const email = String.fromEnvironment('REAL_EMAIL');
  const pass = String.fromEnvironment('REAL_PASS');
  const paso = Duration(milliseconds: 100);
  const maxPaso = Duration(minutes: 3);

  Future<void> asentar(WidgetTester tester,
      {Duration duracion = const Duration(seconds: 12)}) async {
    final limite = DateTime.now().add(duracion);
    while (DateTime.now().isBefore(limite)) {
      await tester.pump(const Duration(milliseconds: 100));
      if (!tester.binding.hasScheduledFrame) return;
    }
    await tester.pumpAndSettle(paso, EnginePhase.sendSemanticsUpdate, maxPaso);
  }

  Future<void> esperar(WidgetTester tester, Finder finder,
      {String? porque, Duration duracion = const Duration(seconds: 45)}) async {
    final limite = DateTime.now().add(duracion);
    while (DateTime.now().isBefore(limite)) {
      await tester.pump(const Duration(milliseconds: 120));
      if (finder.evaluate().isNotEmpty) return;
    }
    fail('No apareció ${porque ?? finder.toString()}: $finder');
  }

  /// Toca un widget llevándolo antes al centro de la vista (el wizard usa
  /// listas con scroll y en pantallas angostas el botón puede quedar fuera).
  Future<void> tocar(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder.first);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(finder.first, warnIfMissed: true);
    await asentar(tester);
  }

  /// Toca un botón que puede estar deshabilitado mientras se verifica algo.
  Future<void> tocarCuandoHabilite(WidgetTester tester, Key key,
      {Duration duracion = const Duration(seconds: 90)}) async {
    final limite = DateTime.now().add(duracion);
    while (DateTime.now().isBefore(limite)) {
      await tester.pump(const Duration(milliseconds: 150));
      final f = find.byKey(key);
      if (f.evaluate().isEmpty) continue;
      final t = tester.widget<ButtonStyleButton>(f.first);
      if (t.onPressed == null) continue;
      await tocar(tester, f);
      return;
    }
    fail('El botón $key nunca estuvo habilitado');
  }

  testWidgets('instalación real → dashboard con la cuenta del central',
      (tester) async {
    if (email.isEmpty || pass.isEmpty) {
      markTestSkipped(
          'Requiere --dart-define=REAL_EMAIL=... y REAL_PASS=...');
      return;
    }

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(1440, 900));
    debugPrint('E2E-INST size=${tester.view.physicalSize / tester.view.devicePixelRatio}');

    // `main()` recarga las preferencias del disco: se vacían para que la app
    // arranque de verdad en modo instalación (preferencias → modo → entorno →
    // activación → empresa), igual que en una estación nueva.
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    // Estado de instalación limpia: sin preferencias, sin modo, sin licencia
    // verificada y sin datos de empresa (lo que el usuario dejó preparado).
    AppConfig.apiBaseUrl = null;
    AppConfig.setupPreferenciasCompletado = false;
    AppConfig.modoEstacion = null;
    AppConfig.licenciaVerificada = false;
    AppConfig.esTitularLicencia = false;
    AppConfig.empresaSetupCapturado = false;
    AppConfig.onboardingCompletado = false;
    AppConfig.offline = false;
    AppConfig.wserverAutostart = false;


    // Sesión previa (si quedó algo de otra corrida): se cierra para que la
    // instalación valide la cuenta contra el central de verdad.
    try {
      await di.sl<LogoutUseCase>().execute();
    } catch (_) {}

    app.main();
    await asentar(tester, duracion: const Duration(seconds: 30));

    // ─── 1. Preferencias (idioma/tema) ─────────────────────────────────
    debugPrint('E2E-INST paso 1 preferencias');
    await esperar(tester, find.byKey(const Key('setup_continuar_btn')),
        porque: 'la pantalla de preferencias');
    await tocar(tester, find.byKey(const Key('setup_continuar_btn')));

    // ─── 2. Modo SERVIDOR ─────────────────────────────────────────────
    debugPrint('E2E-INST paso 2 modo');
    await esperar(tester, find.byKey(const Key('modo_servidor_card')),
        porque: 'la selección de modo');
    await tocar(tester, find.byKey(const Key('modo_servidor_card')));

    // ─── 3. Verificación de entorno (WServer + PostgreSQL) ────────────
    debugPrint('E2E-INST paso 3 entorno');
    await esperar(tester, find.byKey(const Key('entorno_continuar_btn')),
        porque: 'la verificación de entorno');
    await tocarCuandoHabilite(tester, const Key('entorno_continuar_btn'));
    await asentar(tester);

    // ─── 4. Activación de la cuenta contra el servidor central ────────
    debugPrint('E2E-INST paso 4 activación');
    await esperar(tester, find.byKey(const Key('activacion_email_field')),
        porque: 'la pantalla de activación');
    await tester.enterText(find.byKey(const Key('activacion_email_field')), email);
    await tester.enterText(
        find.byKey(const Key('activacion_password_field')), pass);
    await asentar(tester);
    await tocar(tester, find.byKey(const Key('activacion_enviar_btn')));
    await asentar(tester, duracion: const Duration(seconds: 40));

    // Si el central rechazó la cuenta, la pantalla muestra el error y no avanza.
    final sigueActivacion =
        find.byKey(const Key('activacion_email_field')).evaluate().isNotEmpty;
    if (sigueActivacion) {
      final textos = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .where((t) => t != null && t.isNotEmpty)
          .toList();
      fail('La activación no avanzó. Textos en pantalla: $textos');
    }

    // ─── 5. Datos de empresa precargados del central ──────────────────
    debugPrint('E2E-INST paso 5 empresa');
    await esperar(tester, find.byKey(const Key('empresa_continuar_btn')),
        porque: 'el formulario de empresa');
    for (var i = 0; i < 4; i++) {
      if (find.byKey(const Key('empresa_finalizar_btn')).evaluate().isNotEmpty) {
        break;
      }
      await tocarCuandoHabilite(tester, const Key('empresa_continuar_btn'),
          duracion: const Duration(seconds: 20));
    }
    await tocarCuandoHabilite(tester, const Key('empresa_finalizar_btn'),
        duracion: const Duration(seconds: 60));
    await asentar(tester, duracion: const Duration(seconds: 40));

    // ─── 6. Dashboard con la sesión del central ya abierta ───────────
    await esperar(tester, find.byType(DashboardScreen),
        porque: 'el dashboard tras guardar la empresa');
    expect(AppConfig.esServidor, isTrue);
    expect(AppConfig.licenciaVerificada, isTrue);
    expect(AppConfig.empresaSetupCapturado, isTrue);
    debugPrint('E2E-INST OK titular=${AppConfig.esTitularLicencia} '
        'onboarding=${AppConfig.onboardingCompletado}');
  }, timeout: const Timeout(Duration(minutes: 12)));
}