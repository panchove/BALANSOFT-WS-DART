import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:balansoft_ws/core/config/app_config.dart';
import 'package:balansoft_ws/core/security/secure_storage_service.dart';
import 'package:balansoft_ws/data/datasources/local/local_storage.dart';
import 'package:balansoft_ws/data/datasources/remote/api_client.dart';
import 'package:balansoft_ws/domain/entities/user.dart';
import 'package:balansoft_ws/data/repositories/auth_repository.dart';

class _MockApiClient extends ApiClient {
  Map<String, dynamic>? ultimoPayload;
  Response<dynamic>? respuesta;

  @override
  Future<Response<dynamic>> setupCrearAdmin(Map<String, dynamic> data) async {
    ultimoPayload = data;
    return respuesta ??
        Response(
          requestOptions: RequestOptions(path: '/api/v1/auth/setup-admin'),
          statusCode: 200,
          data: {
            'access_token': 'jwt-access-token-123',
            'refresh_token': 'jwt-refresh-token-456',
            'token_type': 'bearer',
            'user': {
              'id_usuario': 'u-admin-1',
              'nombre': 'Administrador',
              'email': 'admin@empresa.com',
              'rol': 'ADMIN',
              'id_empresa': 'emp-1',
              'activo': true,
            },
            'empresa': {
              'id_empresa': 'emp-1',
              'nombre_fiscal': 'Empresa Demo C.A.',
              'rif_nit': 'J-12345678-9',
            },
          },
        );
  }
}

class _MockSecureStorage extends SecureStorageService {
  String? savedAccessToken;
  String? savedRefreshToken;

  @override
  Future<void> saveTokens(String accessToken, String refreshToken) async {
    savedAccessToken = accessToken;
    savedRefreshToken = refreshToken;
  }
}

class _MockLocalStorage extends LocalStorage {
  User? savedUser;

  @override
  Future<void> saveUser(User user) async {
    savedUser = user;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthRepository.setupCrearAdmin', () {
    late _MockApiClient mockApi;
    late _MockSecureStorage mockSecure;
    late _MockLocalStorage mockLocal;
    late AuthRepository repository;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await AppConfig.init();
      // Garantizar que onboardingCompletado empiece en false
      await AppConfig.setOnboardingCompletado(false);

      mockApi = _MockApiClient();
      mockSecure = _MockSecureStorage();
      mockLocal = _MockLocalStorage();
      repository = AuthRepository(
        apiClient: mockApi,
        secureStorage: mockSecure,
        localStorage: mockLocal,
      );
    });

    test('al registrar admin exitoso se persisten tokens, usuario y onboardingCompletado = true', () async {
      expect(AppConfig.onboardingCompletado, isFalse);

      final payload = {
        'nombre': 'Administrador',
        'email': 'admin@empresa.com',
        'password': 'password123',
        'empresa_nombre': 'Empresa Demo C.A.',
        'empresa_rif': 'J-12345678-9',
      };

      final ok = await repository.setupCrearAdmin(payload);

      expect(ok, isTrue);
      expect(mockApi.ultimoPayload, payload);
      expect(mockSecure.savedAccessToken, 'jwt-access-token-123');
      expect(mockSecure.savedRefreshToken, 'jwt-refresh-token-456');
      expect(mockLocal.savedUser?.email, 'admin@empresa.com');
      expect(mockLocal.savedUser?.rol, 'ADMIN');

      // Verifica el requerimiento: onboarding queda marcado como completado
      expect(AppConfig.onboardingCompletado, isTrue);
    });

    test('si la respuesta carece de access_token devuelve false y no completa onboarding', () async {
      mockApi.respuesta = Response(
        requestOptions: RequestOptions(path: '/api/v1/auth/setup-admin'),
        statusCode: 200,
        data: <String, dynamic>{},
      );

      final ok = await repository.setupCrearAdmin({'test': 123});

      expect(ok, isFalse);
      expect(mockSecure.savedAccessToken, isNull);
      expect(AppConfig.onboardingCompletado, isFalse);
    });
  });
}
