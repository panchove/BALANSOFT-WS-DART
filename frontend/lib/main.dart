import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/config/app_config.dart';
import 'core/config/env_config.dart';
import 'core/config/station_config.dart';
import 'core/controllers/typography_controller.dart';
import 'core/i18n/locale_controller.dart';
import 'core/i18n/translations.dart';
import 'core/services/wserver_manager.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/utils/unsaved_work_guard.dart';
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
import 'presentation/screens/weighing/weighing_detail_screen.dart';
import 'presentation/screens/weighing/weighing_list_screen.dart'
    show weighingListRouteObserver;
import 'presentation/screens/settings/settings_screen.dart';
import 'presentation/screens/settings/connections_screen.dart';
import 'presentation/widgets/tipografia_scope.dart';

final themeController = ThemeController();
late final LocaleController localeController;

/// Ruta de arranque: SIEMPRE el login.
///
/// El instalador (BALANSOFT-INSTALLER) decide el rol de la estación y escribe
/// `config.json`; la app ya no tiene asistente de instalación. Si la config
/// falta o es inválida, `main()` ni siquiera monta `BalansoftApp` (error duro
/// con instrucciones), así que aquí solo hay login, registro y recuperación.
String _rutaInicial() => '/login';

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
    // El `center: true` de las opciones se aplica al mostrar la ventana, así
    // que `maximize()` se pide después de `show()`/`focus()` para que la
    // maximización sea la última palabra y no compita con el centrado
    // (REQ-FN-020).
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(minimumSize: Size(1280, 800), center: true),
      () async {
        await windowManager.show();
        await windowManager.focus();
        await windowManager.maximize();
      },
    );
  }

  await _aplicarModoKiosk();

  // Config de estación: `config.json` del instalador (override → sistema) con
  // migración única del legado (wizard viejo). Sin config válida la app NO
  // opera: se muestra el error de provisión en lugar del login.
  await AppConfig.init(migrarLegado: true);
  if (!AppConfig.instalacionValida) {
    runApp(PantallaErrorConfig(error: AppConfig.configError));
    return;
  }
  await themeController.load();
  await di.init();
  localeController = di.sl<LocaleController>();
  await localeController.load();
  AppTranslations.setController(localeController); // conectar singleton

  runApp(const BalansoftApp());
}

/// Pantalla mínima de error de provisión: se muestra cuando el instalador no
/// escribió `config.json` (o lo escribió inválido). El operador no debería
/// verla en una estación bien instalada; da la instrucción concreta en
/// español e inglés (el locale aún no está cargado en este punto).
class PantallaErrorConfig extends StatelessWidget {
  final StationConfigError? error;

  const PantallaErrorConfig({super.key, this.error});

  @override
  Widget build(BuildContext context) {
    final mensajeEs = error == null
        ? 'No se encontró la configuración de la estación.'
        : 'La configuración de la estación es inválida: ${error!.motivo.name}.';
    final mensajeEn = error == null
        ? 'Station configuration not found.'
        : 'Invalid station configuration: ${error!.motivo.name}.';
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0E1F33),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.settings_suggest_outlined,
                      color: Colors.amber, size: 64),
                  const SizedBox(height: 20),
                  const Text(
                    'Balansoft-WS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '$mensajeEs\n\n$mensajeEn'
                    '\n\nEjecute el instalador de Balansoft-WS para configurar '
                    'esta estación.\nRun the Balansoft-WS installer to '
                    'configure this station.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
  /// Ajuste de tipografía del operador (familia + factor), REQ-FN-001..005.
  ///
  /// Se resuelve del contenedor de dependencias y **no** de `main()` porque el
  /// E2E de UI monta `BalansoftApp` directamente, sin pasar por `main()`. Es la
  /// misma instancia que usa Ajustes → Tipografía, que es lo que permite que el
  /// cambio se aplique a toda la app sin reiniciar (REQ-FN-004).
  late final TypographyController _typography = di.sl<TypographyController>();

  @override
  void initState() {
    super.initState();
    // Restituye el ajuste persistido en este dispositivo (REQ-FN-005). El
    // controlador arranca en los valores por defecto y notifica al terminar, así
    // que el primer frame se ve sin ajuste y se corrige en cuanto hay lectura.
    unawaited(_typography.load());
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
    // Solo la estación SERVIDOR gestiona el WServer (el TRABAJADOR es cliente
    // delgado y jamás levanta backend local): no tiene nada que detener.
    if (AppConfig.esServidor) {
      final autostart =
          await WServerManager.autostartActivo() || AppConfig.wserverAutostart;
      if (!autostart) {
        await WServerManager.detener();
      }
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
        // `typographyController` va en la lista para que el factor y la familia
        // se apliquen **sin reiniciar** (REQ-FN-004).
        animation: Listenable.merge(
            [themeController, localeController, _typography]),
        builder: (context, _) => MaterialApp(
          key: ValueKey(localeController.activeLanguageCode),
          navigatorKey: navigatorKey,
          title: 'Balansoft-WS',
          debugShowCheckedModeBanner: false,
          theme: buildLightTheme(
            familia: _typography.familiaUiFontFamily,
            factorIconos: _typography.textScale,
          ),
          darkTheme: buildDarkTheme(
            familia: _typography.familiaUiFontFamily,
            factorIconos: _typography.textScale,
          ),
          themeMode: themeController.themeMode,
          locale: localeController.locale,
          supportedLocales: const [
            Locale('es'),
            Locale('en'),
            Locale('pt'),
          ],
          // Punto único de aplicación del ajuste de tamaño (REQ-FN-002).
          //
          // Va en el `builder` del `MaterialApp` porque es el único sitio que
          // queda por encima de TODAS las rutas, diálogos y `showDialog`, y por
          // debajo del `Navigator`: así los 322 `fontSize:` fijos en código
          // escalan sin tocar ninguno, porque todos leen el `textScaler` de este
          // `MediaQuery`.
          builder: (context, hijo) => TipografiaScope(
            controlador: _typography,
            child: hijo ?? const SizedBox.shrink(),
          ),
          navigatorObservers: [weighingListRouteObserver],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // La estación arranca siempre en el login: el instalador decidió el
          // rol y escribió config.json (docs/MANEJO_DB.md §13).
          initialRoute: _rutaInicial(),
          routes: {
            '/login': (_) => const LoginScreen(),
            '/register': (_) => const RegisterScreen(),
            '/forgot-password': (_) => const ForgotPasswordScreen(),
            '/reset-password': (_) => const ResetPasswordScreen(),
            '/connections': (_) => const ConnectionsScreen(),
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
