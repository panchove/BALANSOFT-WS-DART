/// Refresco de los datos de empresa del usuario en sesión.
///
/// Defecto observado en la estación (2026-10-16): al guardar el perfil de
/// empresa o subir el logo, la app seguía pidiendo el logo **anterior**
/// (`GET /media/uploads/<viejo>.jpg` → 404 en bucle, 13 veces en una sesión)
/// porque el top-nav pinta `AuthState.user.logoUrl` y ese usuario se construyó
/// en el login, antes del `PUT /api/v1/empresa`. El refresco solo ocurría al
/// restaurar sesión, así que hasta reloguear la UI mostraba —y pedía— el logo
/// viejo, que ya no existe en `media/`.
///
/// Cubre las dos piezas de la corrección:
///  * `AuthBloc` → `RefreshCompanyEvent` refresca el usuario en sesión sin
///    `AuthLoading` (la pantalla no parpadea ni pierde la sesión).
///  * `AuthRepository.refrescarEmpresaEnUsuarioCacheado()` → relee `GET
///    /api/v1/empresa`, fusiona nombre/RIF/dirección/logo en el usuario
///    cacheado, lo persiste y lo devuelve.
library;

import 'dart:typed_data';

import 'package:balansoft_ws/core/security/secure_storage_service.dart';
import 'package:balansoft_ws/data/datasources/local/local_storage.dart';
import 'package:balansoft_ws/data/datasources/remote/api_client.dart';
import 'package:balansoft_ws/data/repositories/auth_repository.dart';
import 'package:balansoft_ws/domain/entities/user.dart';
import 'package:balansoft_ws/domain/repositories/i_auth_repository.dart';
import 'package:balansoft_ws/domain/usecases/auth_usecases.dart';
import 'package:balansoft_ws/presentation/providers/bloc/auth/auth_bloc.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────── datos de prueba ───────────────────────────

const _logoViejo = '/media/uploads/57d822c31fd041948fa8f4395deb60a8.jpg';
const _logoNuevo = '/media/uploads/c1fe8b58b11143839840ce182c9f4d84.jpg';

const _user = {
  'idUsuario': 'u-1',
  'nombre': 'Operador',
  'email': 'admin@balansoft.demo',
  'rol': 'ADMIN',
  'idEmpresa': 'emp-1',
};

const _userConLogoViejo = User(
  idUsuario: 'u-1',
  nombre: 'Operador',
  email: 'admin@balansoft.demo',
  rol: 'ADMIN',
  idEmpresa: 'emp-1',
  empresaNombre: 'Variedades S&S',
  empresaRif: 'J-1',
  logoUrl: _logoViejo,
);

const _userConLogoNuevo = User(
  idUsuario: 'u-1',
  nombre: 'Operador',
  email: 'admin@balansoft.demo',
  rol: 'ADMIN',
  idEmpresa: 'emp-1',
  empresaNombre: 'Variedades S&S',
  empresaRif: 'J-1',
  logoUrl: _logoNuevo,
);

const _perfilNuevo = '{"nombre_fiscal":"Variedades S&S","rif_nit":"J-1",'
    '"direccion":"Av. 1","logo_url":"$_logoNuevo"}';

// ─────────────────────────── dobles de prueba ───────────────────────────

/// `HttpClientAdapter` de Dio que responde siempre lo mismo, sin red real
/// (mismo patrón que `test/unit/health_test.dart`).
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({this.body = '{}', this.throwDio = false});

  final String body;
  final bool throwDio;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (throwDio) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// `LocalStorage` en memoria: evita el keyring de la plataforma (la suite de
/// unit tests nunca toca el almacén seguro real).
class _FakeLocalStorage extends LocalStorage {
  _FakeLocalStorage(this.guardado);

  User? guardado;
  int escrituras = 0;

  @override
  Future<User?> getCachedUser() async => guardado;

  @override
  Future<void> saveUser(User user) async {
    escrituras++;
    guardado = user;
  }
}

/// Repositorio de auth de mentira para el BLoC (solo interesa el refresco).
class _FakeAuthRepository implements IAuthRepository {
  _FakeAuthRepository({this.resultado});

  User? resultado;
  Object? error;
  int refrescos = 0;

  @override
  Future<User?> refrescarEmpresaEnUsuarioCacheado() async {
    refrescos++;
    if (error != null) throw error!;
    return resultado;
  }

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
      throw UnimplementedError();

  @override
  Future<User> register({
    required String empresaNombre,
    required String empresaRif,
    required String usuarioNombre,
    required String email,
    required String password,
    String? licenciaKey,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> logout() async {}

  @override
  Future<String> refreshToken(String refreshToken) async =>
      throw UnimplementedError();

  @override
  Future<String?> refreshAccessToken() async => null;

  @override
  Future<void> forgotPassword(String email) async {}

  @override
  Future<void> resetPassword(String token, String newPassword) async {}

  @override
  Future<User?> getCachedUser() async => resultado;

  @override
  Future<SesionRestaurada> restoreSession() async => SesionRestaurada.ok;

  @override
  Future<void> cacheUser(User user) async {}

  @override
  Future<void> clearCache() async {}
}

AuthBloc _blocCon(_FakeAuthRepository repo) => AuthBloc(
      loginUseCase: LoginUseCase(repo),
      registerUseCase: RegisterUseCase(repo),
      logoutUseCase: LogoutUseCase(repo),
      getCachedUserUseCase: GetCachedUserUseCase(repo),
      restoreSessionUseCase: RestoreSessionUseCase(repo),
      forgotPasswordUseCase: ForgotPasswordUseCase(repo),
      resetPasswordUseCase: ResetPasswordUseCase(repo),
      refrescarEmpresaUseCase: RefrescarEmpresaUseCase(repo),
    );

/// Repositorio real con `GET /api/v1/empresa` servido por el stub.
AuthRepository _repoReal(_FakeLocalStorage storage,
        {String perfil = '{}', bool apiCaida = false}) =>
    AuthRepository(
      apiClient: ApiClient(dio: Dio()..httpClientAdapter = _StubAdapter(
        body: perfil,
        throwDio: apiCaida,
      )),
      localStorage: storage,
      secureStorage: SecureStorageService(),
    );

void main() {
  group('AuthBloc · RefreshCompanyEvent', () {
    blocTest<AuthBloc, AuthState>(
      'refresca el usuario en sesión con el logo nuevo, sin AuthLoading',
      build: () => _blocCon(_FakeAuthRepository(resultado: _userConLogoNuevo)),
      seed: () => const AuthAuthenticated(_userConLogoViejo),
      act: (bloc) => bloc.add(const RefreshCompanyEvent()),
      expect: () => [
        isA<AuthAuthenticated>().having(
          (s) => s.user.logoUrl,
          'logo que pintará el top-nav',
          _logoNuevo,
        ),
      ],
    );

    test('sin sesión no consulta al repositorio ni cambia el estado', () async {
      final repo = _FakeAuthRepository(resultado: _userConLogoNuevo);
      final bloc = _blocCon(repo);

      bloc.add(const RefreshCompanyEvent());
      await pumpEventQueue();

      expect(repo.refrescos, 0, reason: 'no hay token con el que releer');
      expect(bloc.state, isA<AuthInitial>());
      await bloc.close();
    });

    test('si el refresco falla mantiene la sesión y no propaga el error',
        () async {
      final repo = _FakeAuthRepository(resultado: _userConLogoViejo);
      final bloc = _blocCon(repo);
      // Deja la sesión iniciada (AuthAuthenticated) como en la app real.
      bloc.add(const CheckAuthStatusEvent());
      await pumpEventQueue();
      expect(bloc.state, isA<AuthAuthenticated>());

      repo.error = StateError('sin red');
      bloc.add(const RefreshCompanyEvent());
      await pumpEventQueue();

      expect(repo.refrescos, 1);
      expect(bloc.state, isA<AuthAuthenticated>(),
          reason: 'un logo que no se puede releer no debe cerrar la sesión');
      await bloc.close();
    });
  });

  group('AuthRepository · refrescarEmpresaEnUsuarioCacheado', () {
    test('aplica nombre, RIF y logo al usuario cacheado y lo persiste',
        () async {
      final storage = _FakeLocalStorage(_userConLogoViejo);
      final repo = _repoReal(storage, perfil: _perfilNuevo);

      final user = await repo.refrescarEmpresaEnUsuarioCacheado();

      expect(user, isNotNull);
      expect(user!.logoUrl, _logoNuevo,
          reason: 'la UI deja de pedir el logo que ya no existe');
      expect(user.empresaRif, 'J-1');
      expect(user.empresaNombre, 'Variedades S&S');
      expect(user.idUsuario, _user['idUsuario'],
          reason: 'conserva los datos de la cuenta (no los pisa con la empresa)');
      expect(storage.guardado!.logoUrl, _logoNuevo,
          reason: 'y queda persistido para el próximo arranque');
      expect(storage.escrituras, 1);
    });

    test('sin usuario cacheado devuelve null', () async {
      final repo = _repoReal(_FakeLocalStorage(null), perfil: _perfilNuevo);
      expect(await repo.refrescarEmpresaEnUsuarioCacheado(), isNull);
    });

    test('si la API falla devuelve null y conserva el usuario anterior',
        () async {
      final storage = _FakeLocalStorage(_userConLogoViejo);
      final repo = _repoReal(storage, apiCaida: true);

      expect(await repo.refrescarEmpresaEnUsuarioCacheado(), isNull);
      expect(storage.guardado!.logoUrl, _logoViejo,
          reason: 'no es crítico: el usuario cacheado no se borra ni se corrompe');
      expect(storage.escrituras, 0);
    });
  });
}
