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

import 'presentation/screens/setup/mode_selection_screen.dart';
import 'presentation/screens/setup/database_config_screen.dart';

final themeController = ThemeController();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // El manejador de ventana DEBE inicializarse antes de runApp para que
    // funcionen los atajos F9 (maximizar/restaurar) y F11 (pantalla completa).
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
  }

  await _aplicarModoKiosk();

  await AppConfig.init();
  await themeController.load();
  await di.init();

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
    final autostart =
        await WServerManager.autostartActivo() || AppConfig.wserverAutostart;
    if (!autostart) {
      await WServerManager.detener();
    }
    await windowManager.destroy();
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
        animation: themeController,
        builder: (context, _) => MaterialApp(
          title: 'Balansoft-WS',
          debugShowCheckedModeBanner: false,
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          themeMode: themeController.themeMode,
          // Primera ejecución: si la API local no está configurada, se abre la
          // selección de modo (instalación).
          initialRoute:
              AppConfig.localApiConfigured ? '/login' : '/mode_selection',
          routes: {
            '/mode_selection': (_) => const ModeSelectionScreen(),
            '/setup': (_) => const EnvironmentCheckScreen(setupMode: true),
            '/db_config': (_) => const DatabaseConfigScreen(),
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
