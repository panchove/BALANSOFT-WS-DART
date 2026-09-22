import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';
import 'core/config/app_config.dart';
import 'core/config/env_config.dart';
import 'core/services/wserver_manager.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
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
import 'presentation/screens/settings/settings_screen.dart';
import 'presentation/screens/settings/connections_screen.dart';

final themeController = ThemeController();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // El manejador de ventana DEBE inicializarse antes de runApp para que
    // funcionen los atajos F9 (maximizar/restaurar) y F11 (pantalla completa).
    await windowManager.ensureInitialized();
  }

  await _aplicarModoKiosk();

  await AppConfig.init();
  await themeController.load();
  await di.init();

  // Primera instalación: la API local aún no está configurada. Se asegura de
  // que el WServer (backend local compilado) esté levantado para que el modo
  // instalación de "Conexiones" pueda probar/editar la conexión de entrada.
  if (!AppConfig.localApiConfigured) {
    try {
      await WServerManager.ensureRunning();
    } catch (_) {
      // Best-effort: si WServer no está disponible, el usuario podrá indicar
      // la URL de una API local/externa de forma manual.
    }
  }

  runApp(const BalansoftApp());
}

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

class BalansoftApp extends StatelessWidget {
  const BalansoftApp({super.key});

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
        animation: themeController,
        builder: (context, _) => MaterialApp(
          title: 'Balansoft-WS',
          debugShowCheckedModeBanner: false,
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          themeMode: themeController.themeMode,
          // Primera ejecución: si la API local no está configurada, se abre la
          // verificación de entorno (instalación) y después la pantalla de
          // conexiones.
          initialRoute:
              AppConfig.localApiConfigured ? '/login' : '/setup',
          routes: {
            '/setup': (_) => const EnvironmentCheckScreen(setupMode: true),
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
            '/settings': (_) => SettingsScreen(themeController: themeController),
          },
        ),
      ),
    );
  }
}
