import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/config/app_config.dart';
import 'core/config/env_config.dart';
import 'core/i18n/locale_controller.dart';
import 'core/i18n/translations.dart';
import 'core/services/wserver_manager.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/utils/unsaved_work_guard.dart';
import 'data/datasources/remote/api_client.dart';
import 'data/repositories/activacion_repository.dart';
import 'injection.dart' as di;
import 'presentation/providers/bloc/auth/auth_bloc.dart';
import 'presentation/providers/bloc/weighing/weighing_bloc.dart';
import 'presentation/providers/bloc/license/license_bloc.dart';
import 'presentation/providers/bloc/sync/sync_bloc.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/auth/register_screen.dart';
import 'presentation/screens/auth/forgot_password_screen.dart';
import 'presentation/screens/auth/reset_password_screen.dart';
import 'presentation/screens/dashboard/home_shell.dart';
import 'presentation/screens/setup/environment_check_screen.dart';
import 'presentation/screens/weighing/weighing_detail_screen.dart';
import 'presentation/screens/weighing/weighing_list_screen.dart'
    show weighingListRouteObserver;
import 'presentation/screens/settings/settings_screen.dart';
import 'presentation/screens/settings/connections_screen.dart';

import 'presentation/screens/setup/mode_selection_screen.dart';
import 'presentation/screens/setup/database_config_screen.dart';
import 'presentation/screens/setup/company_setup_screen.dart';
import 'presentation/screens/setup/activation_screen.dart';
import 'presentation/screens/setup/worker_connection_screen.dart';
import 'presentation/screens/setup/preferences_screen.dart';

final themeController = ThemeController();
late final LocaleController localeController;

/// Ruta de arranque según el estado de la instalación.
///
/// Cada modo tiene su propio camino (docs/MANEJO_DB.md §13):
/// - Sin preferencias → idioma y tema.
/// - Sin modo elegido → servidor o trabajador.
/// - SERVIDOR: entorno → validar cuenta/licencia → datos de empresa.
/// - TRABAJADOR: apuntar al servidor de la cuenta → login.
/// Con la instalación cerrada, la app va directo al login (o al dashboard si
/// la sesión sigue viva).
String _rutaInicial() {
  if (!AppConfig.setupPreferenciasCompletado) return '/setup_preferences';
  if (AppConfig.modoEstacion == null) return '/mode_selection';

  if (AppConfig.esTrabajador) {
    return AppConfig.localApiConfigured ? '/login' : '/worker_connection';
  }

  if (AppConfig.esServidor) {
    // Verificación de entorno (WServer + PostgreSQL) antes de validar la cuenta.
    if (!AppConfig.licenciaVerificada) return '/setup';
    // Cuenta validada: faltan los datos de empresa.
    if (!AppConfig.empresaSetupCapturado) return '/company_setup';
  }

  return '/login';
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // El manejador de ventana DEBE inicializarse antes de runApp para que
    // funcionen los atajos F9 (maximizar/restaurar) y F11 (pantalla completa).
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    // La estación arranca maximizada (el operador no debe redimensionar).
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(minimumSize: Size(1280, 800), center: true),
      () async {
        await windowManager.maximize();
      },
    );
  }

  await _aplicarModoKiosk();

  await AppConfig.init();
  await themeController.load();
  await di.init();
  localeController = di.sl<LocaleController>();
  await localeController.load();
  AppTranslations.setController(localeController); // conectar singleton

  runApp(const BalansoftApp());
}

/// Contexto raíz del `MaterialApp`, para dialogues launched por el
/// `WindowListener` (cierre de ventana), que vive fuera del árbol de widgets.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> _aplicarModoKiosk() async {
  if (!EnvConfig.isKiosk) return;
  try {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      await windowManager.setAsFrameless();
      await windowManager.setFullScreen(true);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  } catch (_) {
    // Si el entorno no soporta kiosk, continuar con la ventana normal.
  }
}

class BalansoftApp extends StatefulWidget {
  const BalansoftApp({super.key});

  @override
  State<BalansoftApp> createState() => _BalansoftAppState();
}

class _BalansoftAppState extends State<BalansoftApp> with WindowListener {
  @override
  void initState() {
    super.initState();
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      windowManager.addListener(this);
    }
  }

  @override
  void dispose() {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowClose() async {
    // Si la estación tiene captura a medias (pesaje de báscula sin boleto,
    // datos del camión, copia de un boleto...), advertir antes de perderla.
    if (tieneDatosSinGuardar) {
      final salir = await _confirmarCierreConDatos();
      if (salir != true) return;
    }
    final autostart =
        await WServerManager.autostartActivo() || AppConfig.wserverAutostart;
    if (!autostart) {
      await WServerManager.detener();
    }
    await windowManager.destroy();
  }

  /// Diálogo de confirmación del cierre cuando hay información sin guardar.
  Future<bool?> _confirmarCierreConDatos() {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return Future.value(true);
    return showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            color: SwsColors.danger, size: 36),
        title: Text(AppTranslations.tr('weighing_unsaved_exit_title'),
            textAlign: TextAlign.center),
        content: Text(
          AppTranslations.tr('weighing_unsaved_exit_msg'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: Text(AppTranslations.tr('weighing_unsaved_cancel_btn')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SwsColors.danger),
            onPressed: () => Navigator.of(c).pop(true),
            child: Text(AppTranslations.tr('weighing_unsaved_confirm_exit')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>(
          create: (_) => di.sl<AuthBloc>()..add(const CheckAuthStatusEvent()),
        ),
        BlocProvider<WeighingBloc>(
          create: (_) => di.sl<WeighingBloc>(),
        ),
        BlocProvider<LicenseBloc>(
          create: (_) => di.sl<LicenseBloc>()..add(CheckCachedLicenseEvent()),
        ),
        BlocProvider<SyncBloc>(
          create: (_) => di.sl<SyncBloc>()..add(SyncStatusEvent()),
        ),
      ],
      child: AnimatedBuilder(
        animation: Listenable.merge([themeController, localeController]),
        builder: (context, _) => MaterialApp(
          key: ValueKey(localeController.activeLanguageCode),
          navigatorKey: navigatorKey,
          title: 'Balansoft-WS',
          debugShowCheckedModeBanner: false,
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          themeMode: themeController.themeMode,
          locale: localeController.locale,
          supportedLocales: const [
            Locale('es'),
            Locale('en'),
            Locale('pt'),
          ],
          navigatorObservers: [weighingListRouteObserver],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // Primera ejecución: paso 1 de instalación (idioma y tema) antes de
          // cualquier requerimiento de red; luego selección de modo.
          initialRoute: _rutaInicial(),
          routes: {
            '/setup_preferences': (_) => SetupPreferencesScreen(
                  localeController: localeController,
                  themeController: themeController,
                ),
            '/mode_selection': (_) => const ModeSelectionScreen(),
            '/setup': (_) => const EnvironmentCheckScreen(setupMode: true),
            '/activation': (_) =>
                ActivationScreen(repository: di.sl<ActivacionRepository>()),
            '/worker_connection': (_) => WorkerConnectionScreen(
                  clientFactory: (baseUrl) => ApiClient(baseUrl: baseUrl),
                ),
            '/db_config': (_) => const DatabaseConfigScreen(),
            '/company_setup': (_) =>
                CompanySetupScreen(localeController: localeController),
            '/login': (_) => const LoginScreen(),
            '/register': (_) => const RegisterScreen(),
            '/forgot-password': (_) => const ForgotPasswordScreen(),
            '/reset-password': (_) => const ResetPasswordScreen(),
            '/connections': (_) => const ConnectionsScreen(setupMode: true),
            '/dashboard': (_) => HomeShell(themeController: themeController),
            '/weighing/detail': (ctx) {
              final boleto = ModalRoute.of(ctx)!.settings.arguments as String;
              return WeighingDetailScreen(boleto: boleto);
            },
            '/settings': (_) => SettingsScreen(
                  themeController: themeController,
                  localeController: localeController,
                ),
          },
        ),
      ),
    );
  }
}
