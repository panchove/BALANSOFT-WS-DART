import '../../domain/entities/user.dart';
import '../../domain/repositories/i_auth_repository.dart';
import '../../core/security/secure_storage_service.dart';
import '../datasources/remote/api_client.dart';
import '../datasources/local/local_storage.dart';
import '../models/user_model.dart';

class AuthRepository implements IAuthRepository {
  final ApiClient _apiClient;
  final LocalStorage _localStorage;
  final SecureStorageService _secureStorage;

  AuthRepository({
    required ApiClient apiClient,
    required LocalStorage localStorage,
    required SecureStorageService secureStorage,
  })  : _apiClient = apiClient,
        _localStorage = localStorage,
        _secureStorage = secureStorage;

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
    final response = await _apiClient.login({
      'email': email,
      'password': password,
      'hardware_id': hardwareId,
      'device_brand': deviceBrand,
      'device_model': deviceModel,
      'os_version': osVersion,
      'mac_address': macAddress,
    });

    final data = response.data;
    await _secureStorage.saveTokens(data['access_token'], data['refresh_token']);
    _apiClient.setToken(data['access_token']);

    final user = UserModel.fromJson(data['user']);
    await _localStorage.saveUser(user);

    return user;
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
    final response = await _apiClient.register({
      'empresa_nombre': empresaNombre,
      'empresa_rif': empresaRif,
      'usuario_nombre': usuarioNombre,
      'email': email,
      'password': password,
      'licencia_key': licenciaKey,
    });

    final data = response.data;
    await _secureStorage.saveTokens(data['access_token'], data['refresh_token']);
    _apiClient.setToken(data['access_token']);

    final user = UserModel.fromJson(data['user']);
    await _localStorage.saveUser(user);

    return user;
  }

  @override
  Future<void> logout() async {
    try {
      await _apiClient.logout();
    } catch (_) {}
    _apiClient.clearToken();
    await _secureStorage.clearAuth();
    await _localStorage.clearAuth();
  }

  @override
  Future<String> refreshToken(String refreshToken) async {
    final response = await _apiClient.refreshToken(refreshToken);
    final newToken = response.data['access_token'];
    final newRefresh = response.data['refresh_token'];
    await _secureStorage.saveTokens(newToken, newRefresh);
    _apiClient.setToken(newToken);
    return newToken;
  }

  @override
  Future<String?> refreshAccessToken() async {
    final refresh = await _secureStorage.getRefreshToken();
    if (refresh == null || refresh.isEmpty) return null;
    try {
      return await refreshToken(refresh);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> forgotPassword(String email) async {
    await _apiClient.forgotPassword(email);
  }

  @override
  Future<void> resetPassword(String token, String newPassword) async {
    await _apiClient.resetPassword(token, newPassword);
  }

  @override
  Future<User?> getCachedUser() async {
    return _localStorage.getCachedUser();
  }

  @override
  Future<void> restoreSession() async {
    final token = await _secureStorage.getAccessToken();
    if (token != null && token.isNotEmpty) {
      _apiClient.setToken(token);
    }
  }

  @override
  Future<void> cacheUser(User user) async {
    await _localStorage.saveUser(UserModel.fromEntity(user));
  }

  @override
  Future<void> clearCache() async {
    _apiClient.clearToken();
    await _localStorage.clearAuth();
  }
}
