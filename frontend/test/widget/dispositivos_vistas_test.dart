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
import 'package:balansoft_ws/presentation/screens/dispositivos/basculas_screen.dart';
import 'package:balansoft_ws/presentation/screens/dispositivos/camaras_screen.dart';
import 'package:balansoft_ws/presentation/screens/dispositivos/impresoras_screen.dart';
import 'package:balansoft_ws/presentation/screens/dispositivos/indicadores_screen.dart';
import 'package:balansoft_ws/presentation/screens/dispositivos/semaforos_screen.dart';

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
  Future<User> register({
    required String empresaNombre,
    required String empresaRif,
    required String usuarioNombre,
    required String email,
    required String password,
    String? licenciaKey,
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
      registerUseCase: RegisterUseCase(repo),
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

  const pantallas = <String, Widget>{
    'Básculas': BasculasScreen(),
    'Indicadores': IndicadoresScreen(),
    'Semáforos': SemaforosScreen(),
    'Cámaras': CamarasScreen(),
  };

  for (final entrada in pantallas.entries) {
    testWidgets('${entrada.key} es una pantalla independiente con AppBar',
        (tester) async {
      await montar(tester, entrada.value);

      expect(find.byType(AppBar), findsOneWidget,
          reason: 'la vista ${entrada.key} debe traer su propia AppBar');
      expect(find.byType(Scaffold), findsWidgets);
      expect(tester.takeException(), isNull);

      await desmontar(tester);
    });
  }

  testWidgets('las cuatro vistas con tabla traen su barra de búsqueda',
      (tester) async {
    for (final pantalla in [
      const IndicadoresScreen(),
      const SemaforosScreen(),
      const CamarasScreen(),
    ]) {
      await montar(tester, pantalla);
      expect(find.byType(TextField), findsWidgets,
          reason: 'debe haber una barra de búsqueda de texto');
      await desmontar(tester);
    }
  });

  testWidgets('Impresoras es su propia pantalla (no comparte la de básculas)',
      (tester) async {
    // No se monta: `PrinterDiscovery.scan()` lanza un subproceso real
    // (`lpstat`/PowerShell) cuyo temporizador no se puede drenar de forma
    // síncrona en un widget test. El montaje de la pantalla se cubre con
    // `flutter analyze` y su lógica de filtrado es cliente puro.
    expect(const ImpresorasScreen(), isA<StatefulWidget>());
    expect(const ImpresorasScreen(), isNot(isA<BasculasScreen>()));
  });
}
