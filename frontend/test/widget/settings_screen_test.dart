import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:balansoft_ws/core/theme/app_theme.dart';
import 'package:balansoft_ws/core/theme/theme_controller.dart';
import 'package:balansoft_ws/data/datasources/local/local_storage.dart';
import 'package:balansoft_ws/data/datasources/remote/api_client.dart';
import 'package:balansoft_ws/data/datasources/remote/scale_api_datasource.dart';
import 'package:balansoft_ws/data/services/scale_api_client.dart';
import 'package:balansoft_ws/domain/entities/user.dart';
import 'package:balansoft_ws/domain/repositories/i_auth_repository.dart';
import 'package:balansoft_ws/domain/usecases/auth_usecases.dart';
import 'package:balansoft_ws/injection.dart' as di;
import 'package:balansoft_ws/presentation/providers/bloc/auth/auth_bloc.dart';
import 'package:balansoft_ws/presentation/screens/settings/settings_screen.dart';

class _FakeAuthRepository implements IAuthRepository {
  @override
  Future<User> login({
    required String email,
    required String password,
    String? hardwareId,
    String? deviceBrand,
    String? deviceModel,
    String? osVersion,
    String? macAddress,
  }) async {
    return _adminUser;
  }

  @override
  Future<User> register({
    required String empresaNombre,
    required String empresaRif,
    required String usuarioNombre,
    required String email,
    required String password,
    String? licenciaKey,
  }) async {
    return _adminUser;
  }

  @override
  Future<void> logout() async {}

  @override
  Future<String> refreshToken(String refreshToken) async => 'token';

  @override
  Future<String?> refreshAccessToken() async => 'token';

  @override
  Future<void> forgotPassword(String email) async {}

  @override
  Future<void> resetPassword(String token, String newPassword) async {}

  @override
  Future<User?> getCachedUser() async => _adminUser;

  @override
  Future<void> restoreSession() async {}

  @override
  Future<void> cacheUser(User user) async {}

  @override
  Future<void> clearCache() async {}
}

const _adminUser = User(
  idUsuario: 'u-admin',
  nombre: 'Administrador Balansoft',
  email: 'admin@balansoft.com.ve',
  rol: 'ADMIN',
  idEmpresa: 'emp-1',
);

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super();

  @override
  Future<Map<String, dynamic>> getAccountInfo() async {
    return {
      'nombre_comercial': 'Transportes Balansoft C.A.',
      'nombre_fiscal': 'Transportes Balansoft C.A.',
      'rif_nit': 'J-12345678-9',
      'licencia_tier': 'CENTRAL PRO',
      'licencia_status': 'ACTIVA',
      'licencia_valida': true,
      'licencia_expira': '2026-12-31',
    };
  }

  @override
  Future<Map<String, dynamic>?> getIdentity() async {
    return {
      'nombre_comercial': 'Transportes Balansoft C.A.',
      'nombre_fiscal': 'Transportes Balansoft C.A.',
      'licencia_tier': 'CENTRAL PRO',
      'modo_offline': false,
    };
  }
}

class _FakeLocalStorage extends LocalStorage {
  @override
  Future<({String host, int port})> getScaleConfig() async {
    return (host: '127.0.0.1', port: 5555);
  }

  @override
  Future<String> getDescargasDir() async => '/tmp/descargas';
}

void main() {
  setUp(() {
    di.sl.reset();
    di.sl.registerLazySingleton<ApiClient>(
      () => _FakeApiClient(),
    );
    di.sl.registerLazySingleton<LocalStorage>(() => _FakeLocalStorage());
    di.sl.registerLazySingleton<ScaleApiClient>(
      () => ScaleApiClient(datasource: ScaleApiDatasource(di.sl<ApiClient>())),
    );
  });

  Widget buildApp() {
    final repo = _FakeAuthRepository();
    final authBloc = AuthBloc(
      loginUseCase: LoginUseCase(repo),
      registerUseCase: RegisterUseCase(repo),
      logoutUseCase: LogoutUseCase(repo),
      getCachedUserUseCase: GetCachedUserUseCase(repo),
      restoreSessionUseCase: RestoreSessionUseCase(repo),
      forgotPasswordUseCase: ForgotPasswordUseCase(repo),
      resetPasswordUseCase: ResetPasswordUseCase(repo),
    )..add(CheckAuthStatusEvent());

    return BlocProvider<AuthBloc>(
      create: (_) => authBloc,
      child: MaterialApp(
        theme: buildLightTheme(),
        home: SettingsScreen(themeController: ThemeController()),
      ),
    );
  }

  Future<void> renderAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('settings sin overflows en ventana de escritorio 1280x800',
      (tester) async {
    await renderAt(tester, const Size(1280, 800));
    expect(find.text('Configuración'), findsOneWidget);
    expect(find.text('Transportes Balansoft C.A.'), findsWidgets);
  });

  testWidgets('settings sin overflows en ventana compacta 700x900',
      (tester) async {
    await renderAt(tester, const Size(700, 900));
    expect(find.text('Configuración'), findsOneWidget);
  });

  testWidgets('settings sin overflows en ancho mínimo 320x700',
      (tester) async {
    await renderAt(tester, const Size(320, 700));
    expect(find.text('Configuración'), findsOneWidget);
  });

  testWidgets('settings robusto en ancho mínimo 200x600 (apilado)',
      (tester) async {
    tester.view.physicalSize = const Size(200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildApp());
    await tester.pump();
    final ex = tester.takeException();
    expect(ex, isNull, reason: 'Overflow/layout en 200px de ancho: $ex');
  });
}