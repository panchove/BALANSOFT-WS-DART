import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:balansoft_ws/core/theme/app_theme.dart';
import 'package:balansoft_ws/data/datasources/remote/api_client.dart';
import 'package:balansoft_ws/domain/entities/user.dart';
import 'package:balansoft_ws/domain/repositories/i_auth_repository.dart';
import 'package:balansoft_ws/domain/usecases/auth_usecases.dart';
import 'package:balansoft_ws/injection.dart' as di;
import 'package:balansoft_ws/presentation/providers/bloc/auth/auth_bloc.dart';
import 'package:balansoft_ws/presentation/screens/dispositivos/dispositivos_screen.dart';

/// Las cuatro (cinco) vistas de dispositivos son pantallas independientes:
/// cada una monta su propio `Scaffold` + `AppBar` y expone la barra de filtros
/// de su tabla. Este test es un **humo de montaje**: ninguna abre socket, el
/// `ApiClient` está doblado y las listas llegan vacías.
class _FakeApiClient extends ApiClient {
  @override
  Future<Response> getList(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async =>
      Response(
        data: const <Map<String, dynamic>>[],
        requestOptions: RequestOptions(path: path),
      );

  @override
  Future<List<Map<String, dynamic>>> descubrirBalanzas({
    bool incluirSimuladas = true,
  }) async =>
      const <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> descubrirSemaforos({
    bool incluirSimulados = true,
  }) async =>
      const <Map<String, dynamic>>[];
}

class _FakeAuthRepository implements IAuthRepository {
  _FakeAuthRepository(this.usuario);

  final User usuario;

  @override
  Future<User> login({
    required String email,
    required String password,
    String? hardwareId,
    String? deviceBrand,
    String? deviceModel,
    String? osVersion,
    String? macAddress,
  }) async =>
      usuario;


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
  Future<User?> getCachedUser() async => usuario;

  @override
  Future<User?> refrescarEmpresaEnUsuarioCacheado() async => usuario;

  @override
  Future<SesionRestaurada> restoreSession() async => SesionRestaurada.ok;

  @override
  Future<bool> setupCrearAdmin(Map<String, dynamic> data) async => true;

  @override
  Future<void> cacheUser(User user) async {}

  @override
  Future<void> clearCache() async {}
}

const _admin = User(
  idUsuario: 'u-admin',
  nombre: 'Administrador',
  email: 'admin@balansoft.com.ve',
  rol: 'ADMIN',
  idEmpresa: 'emp-1',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await di.sl.reset();
    di.sl.registerLazySingleton<ApiClient>(_FakeApiClient.new);
  });

  Widget buildApp(Widget pantalla) {
    final repo = _FakeAuthRepository(_admin);
    final authBloc = AuthBloc(
      loginUseCase: LoginUseCase(repo),

      logoutUseCase: LogoutUseCase(repo),
      getCachedUserUseCase: GetCachedUserUseCase(repo),
      restoreSessionUseCase: RestoreSessionUseCase(repo),
      forgotPasswordUseCase: ForgotPasswordUseCase(repo),
      resetPasswordUseCase: ResetPasswordUseCase(repo),
      refrescarEmpresaUseCase: RefrescarEmpresaUseCase(repo),
    )..add(const CheckAuthStatusEvent());

    return BlocProvider<AuthBloc>.value(
      value: authBloc,
      child: MaterialApp(
        theme: buildLightTheme(),
        home: pantalla,
      ),
    );
  }

  Future<void> montar(WidgetTester tester, Widget pantalla) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildApp(pantalla));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
  }

  testWidgets('DispositivosScreen se monta con TabBar y AppBar', (tester) async {
    await montar(tester, const DispositivosScreen(initialTab: 0));

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byType(TabBar), findsOneWidget);
    expect(tester.takeException(), isNull);

    await desmontar(tester);
  });

  testWidgets('DispositivosScreen monta pestañas sin excepciones', (tester) async {
    for (final tab in [0, 1, 2, 3, 5]) {
      await montar(tester, DispositivosScreen(initialTab: tab));
      expect(tester.takeException(), isNull);
      await desmontar(tester);
    }
  });
}
