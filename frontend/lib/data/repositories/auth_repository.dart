import 'dart:async';

import 'package:dio/dio.dart';

import '../../core/config/app_config.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/i_auth_repository.dart';
import '../../core/security/device_info.dart';
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

  /// Errores que permiten intentar el login OFFLINE (red caída o LM sin respuesta).
  bool _esErrorSinConexion(DioException e) {
    if (e.response?.statusCode == 503) return true;
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return true;
      default:
        return false;
    }
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
  }) async {
    final body = {
      'email': email,
      'password': password,
      'hardware_id': hardwareId,
      'device_brand': deviceBrand,
      'device_model': deviceModel,
      'os_version': osVersion,
      'mac_address': macAddress,
    };

    Response response;
    var offline = false;
    try {
      response = await _apiClient.login(body);
    } on DioException catch (e) {
      if (!_esErrorSinConexion(e)) rethrow;
      // Sin conexión al servidor de licencias: validar contra la DB local.
      offline = true;
      response = await _apiClient.loginLocal(body);
    }

    final data = response.data;
    await _secureStorage.saveTokens(data['access_token'], data['refresh_token']);
    _apiClient.setToken(data['access_token']);

    final user = UserModel.fromJson(data['user']);
    await _localStorage.saveUser(user);
    await AppConfig.setOffline(offline);

    // Best-effort: registrar la identidad local y empujar la cola de usuarios.
    // Nunca debe hacer fallar el login: se captura cualquier error.
    unawaited(_sincronizarIdentidadYUsuarios(
      data,
      user,
      offline: offline,
      email: email,
      password: password,
      hardwareId: hardwareId,
    ));

    return user;
  }

  /// Tras un login con sesión válida, persiste la identidad de la estación y
  /// envía al servidor central los usuarios locales pendientes de sincronizar.
  /// Flujo: GET/PUT /api/v1/identity (backend local) -> cola pendientes ->
  /// POST {server}/api/v1/sync/users -> POST entregados (backend local).
  Future<void> _sincronizarIdentidadYUsuarios(
    Map<String, dynamic> data,
    User user, {
    required bool offline,
    String? email,
    String? password,
    String? hardwareId,
  }) async {
    if (data['empresa'] is! Map<String, dynamic>) return;
    final empresa = data['empresa'] as Map<String, dynamic>;
    final license = data['license'] as Map<String, dynamic>?;

    try {
      final identidadActual = await _apiClient.getIdentity();
      if (identidadActual == null && !offline) {
        final hwInfo = await DeviceInfo.getHardwareInfo();
        await _apiClient.saveIdentity({
          'id_cuenta': empresa['id_cuenta'] ?? empresa['id_empresa'],
          'rif_nit': empresa['rif_nit'],
          'nombre_fiscal': empresa['nombre_fiscal'],
          'nombre_comercial': empresa['nombre_comercial'],
          'licencia_tier': license?['tier'] ?? empresa['licencia_tier'],
          'licencia_status': license?['status'] ?? empresa['licencia_status'],
          'licencia_expira': empresa['licencia_expira'],
          'hardware_id': hwInfo.hardwareId,
          'rol_dispositivo': 'LOCAL',
          'modo_offline': offline,
        });
      }
    } catch (_) {
      // Identidad no crítica: el login ya se consideró exitoso.
    }

    if (offline || user.rol != 'ADMIN') return;

    // Autenticarse contra el servidor central para obtener su credencial
    // global (token con sub = id_credencial). Sin esto `/sync/users` responde
    // 401/404 porque el token local no corresponde a una credencial global.
    await _autenticarServidorCentral(
      email: email,
      password: password,
      hardwareId: hardwareId,
    );

    try {
      final pendientes = await _apiClient.usuariosPendientes();
      if (pendientes.isEmpty) return;
      final items = <Map<String, dynamic>>[];
      final ids = <String>[];
      for (final p in pendientes) {
        final accion = p is Map ? (p['accion'] ?? 'upsert') : 'upsert';
        final payload = p is Map ? (p['payload'] ?? {}) : {};
        if (payload is! Map) continue;
        ids.add(p is Map && p['id'] != null ? '${p['id']}' : '${payload['id']}');
        items.add({
          'matricula': payload['matricula'],
          'nombre': payload['nombre'],
          'email': payload['email'],
          'password_hash': payload['password_hash'],
          'rol': payload['rol'],
          'activo': payload['activo'],
          'accion': accion,
        });
      }
      if (items.isEmpty) return;
      await _apiClient.pushUsuariosServer(items);
      await _apiClient.marcarUsuariosEntregados(ids);
    } catch (_) {
      // Sin credencial de servidor aún o red caída: la cola espera al próximo login.
    }
  }

  /// Obtiene la credencial global del servidor central y la deja lista en el
  /// [ApiClient]. Prioriza un login fresco con las credenciales del ADMIN y,
  /// si falla, reutiliza el token guardado de un login anterior.
  Future<void> _autenticarServidorCentral({
    String? email,
    String? password,
    String? hardwareId,
  }) async {
    final serverUrl = AppConfig.serverApiUrl;
    if (serverUrl == null || serverUrl.isEmpty) return;

    if (email != null && email.isNotEmpty && password != null && password.isNotEmpty) {
      try {
        final hw = hardwareId ?? (await DeviceInfo.getHardwareInfo()).hardwareId;
        final resp = await _apiClient.serverLogin(
          email: email,
          password: password,
          hardwareId: hw,
        );
        final acceso = resp.data['access_token'] as String?;
        final refresco = resp.data['refresh_token'] as String?;
        if (acceso != null && acceso.isNotEmpty) {
          await _secureStorage.saveServerTokens(acceso, refresco ?? '');
          _apiClient.setServerToken(acceso);
          return;
        }
      } catch (_) {
        // Credencial del servidor distinta o servidor no disponible.
      }
    }

    final existente = await _secureStorage.getServerAccessToken();
    if (existente != null && existente.isNotEmpty) {
      _apiClient.setServerToken(existente);
    }
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
    _apiClient.setServerToken(null);
    await _secureStorage.clearAuth();
    await _secureStorage.clearServerAuth();
    await _localStorage.clearAuth();
    await AppConfig.setOffline(false);
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
    final serverToken = await _secureStorage.getServerAccessToken();
    if (serverToken != null && serverToken.isNotEmpty) {
      _apiClient.setServerToken(serverToken);
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
