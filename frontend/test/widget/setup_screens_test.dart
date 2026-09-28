import 'package:balansoft_ws/core/config/app_config.dart';
import 'package:balansoft_ws/core/security/secure_storage_service.dart';
import 'package:balansoft_ws/core/i18n/locale_controller.dart';
import 'package:balansoft_ws/core/i18n/translations.dart';
import 'package:balansoft_ws/core/theme/theme_controller.dart';
import 'package:balansoft_ws/presentation/screens/setup/database_config_screen.dart';
import 'package:balansoft_ws/presentation/screens/setup/environment_check_screen.dart';
import 'package:balansoft_ws/presentation/screens/setup/mode_selection_screen.dart';
import 'package:balansoft_ws/presentation/screens/setup/activation_screen.dart';
import 'package:balansoft_ws/presentation/screens/setup/preferences_screen.dart';
import 'package:balansoft_ws/presentation/screens/setup/worker_connection_screen.dart';
import 'package:balansoft_ws/data/datasources/local/local_storage.dart';
import 'package:balansoft_ws/data/datasources/remote/api_client.dart';
import 'package:balansoft_ws/data/repositories/activacion_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Monta una pantalla del flujo de instalación y devuelve las excepciones de
/// layout. El flujo completo es el primer contacto del operador con la app:
/// un `Expanded` dentro de un alto infinito tumba la ventana al arrancar.
Future<Object?> _montar(
  WidgetTester tester,
  Widget pantalla, {
  Size tamano = const Size(1366, 768),
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(home: pantalla));
  // Las pantallas consultan la API local: se avanza el tiempo sin esperar red.
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  return tester.takeException();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocaleController localeController;
  late ThemeController themeController;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppConfig.init();
    localeController = LocaleController();
    await localeController.load();
    themeController = ThemeController();
    await themeController.load();
    AppTranslations.setController(localeController);
  });

  group('Pantallas del flujo de instalación', () {
    testWidgets('Preferencias (idioma y tema) sin errores de layout',
        (tester) async {
      final excepcion = await _montar(
        tester,
        SetupPreferencesScreen(
          localeController: localeController,
          themeController: themeController,
        ),
      );

      expect(excepcion, isNull);
      expect(find.byType(SetupPreferencesScreen), findsOneWidget);
    });

    testWidgets('Selección de modo sin errores de layout', (tester) async {
      final excepcion = await _montar(tester, const ModeSelectionScreen());

      expect(excepcion, isNull);
      expect(find.byType(ModeSelectionScreen), findsOneWidget);
    });

    testWidgets('Verificación de entorno (diagnóstico) sin errores de layout',
        (tester) async {
      final excepcion = await _montar(
        tester,
        const EnvironmentCheckScreen(setupMode: false),
      );

      expect(excepcion, isNull);
      expect(find.byType(EnvironmentCheckScreen), findsOneWidget);
    });

    testWidgets('Configuración de base de datos sin errores de layout',
        (tester) async {
      final excepcion = await _montar(tester, const DatabaseConfigScreen());

      expect(excepcion, isNull);
      expect(find.byType(DatabaseConfigScreen), findsOneWidget);
    });

    testWidgets('Activación de cuenta sin errores de layout', (tester) async {
      // La activación se monta desde main.dart con el repositorio inyectado;
      // aquí basta un doble vacío porque no se llega a llamar al central.
      final excepcion = await _montar(
        tester,
        ActivationScreen(repository: _repoFalso()),
      );

      expect(excepcion, isNull);
      expect(find.byType(ActivationScreen), findsOneWidget);
      expect(find.text('activation_email'.tr()), findsOneWidget);
      expect(find.text('activation_password'.tr()), findsOneWidget);
    });

    testWidgets('Conexión del trabajador sin errores de layout',
        (tester) async {
      final excepcion = await _montar(
        tester,
        WorkerConnectionScreen(
          clientFactory: (baseUrl) => ApiClient(baseUrl: baseUrl),
        ),
      );

      expect(excepcion, isNull);
      expect(find.byType(WorkerConnectionScreen), findsOneWidget);
      expect(find.text('worker_host'.tr()), findsOneWidget);
      expect(find.text('worker_port'.tr()), findsOneWidget);
    });
  });

  group('Modo de la estación', () {
    test('el modo elegido queda persistido y define el tipo de estación',
        () async {
      await AppConfig.setModoEstacion('SERVIDOR');
      expect(AppConfig.modoEstacion, 'SERVIDOR');
      expect(AppConfig.esServidor, isTrue);
      expect(AppConfig.esTrabajador, isFalse);

      await AppConfig.setModoEstacion('TRABAJADOR');
      expect(AppConfig.modoEstacion, 'TRABAJADOR');
      expect(AppConfig.esServidor, isFalse);
      expect(AppConfig.esTrabajador, isTrue);
    });

    test('el modo sobrevive a un reinicio de la app', () async {
      await AppConfig.setModoEstacion('TRABAJADOR');
      await AppConfig.setApiBaseUrl('http://192.168.1.10:8000');
      expect(AppConfig.esTitularLicencia, isFalse);

      // Reconstruye el estado desde SharedPreferences, como en el arranque.
      await AppConfig.init();

      expect(AppConfig.modoEstacion, 'TRABAJADOR');
      expect(AppConfig.esTrabajador, isTrue);
      expect(AppConfig.localApiConfigured, isTrue);
    });

    test('la instalación se da por completa solo con empresa + licencia',
        () async {
      await AppConfig.setSetupPreferenciasCompletado();
      await AppConfig.setModoEstacion('SERVIDOR');
      await AppConfig.setLicenciaVerificada(verificada: true, titular: true);
      expect(AppConfig.licenciaVerificada, isTrue);
      expect(AppConfig.esTitularLicencia, isTrue);
      expect(AppConfig.instalacionCompletada, isFalse);

      await AppConfig.setEmpresaSetupCapturado();
      expect(AppConfig.instalacionCompletada, isTrue);
    });

    test('el trabajador completa la instalación con su conexión, no con licencia',
        () async {
      await AppConfig.setSetupPreferenciasCompletado();
      await AppConfig.setModoEstacion('TRABAJADOR');
      await AppConfig.setApiBaseUrl('http://10.0.0.5:8000');

      expect(AppConfig.instalacionCompletada, isTrue);
    });
  });
}

/// Doble mínimo: la pantalla solo lo usa al pulsar "verificar".
ActivacionRepository _repoFalso() => ActivacionRepository(
      apiClient: ApiClient(baseUrl: 'http://localhost:8000'),
      localStorage: LocalStorage(),
      secureStorage: SecureStorageService(),
    );
