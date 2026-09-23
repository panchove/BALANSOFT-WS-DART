import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/config/app_config.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/i_auth_repository.dart';
import '../../core/security/device_info.dart';
import '../../core/security/secure_storage_service.dart';
import '../../core/utils/save_file_utils.dart';
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

    final serverUrl = AppConfig.serverApiUrl?.trim();
    if (serverUrl != null && serverUrl.isNotEmpty) {
      // 1) CENTRAL-first: el backend local valida la cuenta en el servidor
      // central (DB del panel) y hace espejo local (empresa + admin) si existe.
      try {
        response = await _apiClient.loginCentral({
          ...body,
          'server_url': serverUrl,
        });
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        if (status == 403) {
          // Límite de sesiones de la licencia alcanzado en el central: no debe
          // sortearse con el login local.
          rethrow;
        }
        if (_esErrorSinConexion(e) || status == 400 || status == 502) {
          // Central caído/sin configurar: continuar offline con la DB local.
          offline = true;
          response = await _apiClient.loginLocal(body);
        } else {
          // 401: la credencial no existe en el panel → puede ser un usuario
          // operativo local creado por el admin. Intentar login local.
          response = await _intentarLoginLocalOOffline(body);
        }
      }
    } else {
      // Estación autónoma (sin servidor central): login local con LM primero,
      // y respaldo offline si la red cae.
      response = await _intentarLoginLocalOOffline(body);
    }

    final data = response.data;
    await _secureStorage.saveTokens(data['access_token'], data['refresh_token']);
    _apiClient.setToken(data['access_token']);

    final user = UserModel.fromJson(data['user']);
    await _localStorage.saveUser(user);
    await AppConfig.setOffline(offline);

    if (data['empresa'] is Map<String, dynamic>) {
      final emp = data['empresa'] as Map<String, dynamic>;
      final rutaExp = emp['ruta_exportacion_reportes'] as String?;
      if (rutaExp != null && rutaExp.trim().isNotEmpty) {
        await SaveFileUtils.setRutaPersonalizada(rutaExp);
      }
    }

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

  /// Login local estándar (valida licencia con el LM) y, si la red cae, cae al
  /// respaldo OFFLINE validando solo las credenciales de la DB local.
  Future<Response> _intentarLoginLocalOOffline(
    Map<String, dynamic> body,
  ) async {
    try {
      return await _apiClient.login(body);
    } on DioException catch (e) {
      if (_esErrorSinConexion(e)) {
        return await _apiClient.loginLocal(body);
      }
      rethrow;
    }
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
        final hw = await DeviceInfo.getHardwareInfo();
        final resp = await _apiClient.serverLogin(
          email: email,
          password: password,
          hardwareId: hardwareId ?? hw.hardwareId,
          deviceBrand: hw.brand,
          deviceModel: hw.model,
          osVersion: hw.osVersion,
          macAddress: hw.macAddress,
          nombreEquipo: Platform.localHostname,
          sistemaOperativo: hw.osVersion,
          versionApp: AppConfig.appVersion,
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
  Future<SesionRestaurada> restoreSession() async {
    final token = await _secureStorage.getAccessToken();
    if (token != null && token.isNotEmpty) {
      _apiClient.setToken(token);
    }
    final serverToken = await _secureStorage.getServerAccessToken();
    if (serverToken != null && serverToken.isNotEmpty) {
      _apiClient.setServerToken(serverToken);
    }

    // Validar la sesión guardada intentando renovar el access token. Si el
    // servidor rechaza con 401 (p.ej. BD recién vaciada/reinstalada) la sesión
    // local no vale y se limpia para volver al login. Si es un problema de red,
    // se conserva la sesión offline (offline-first) y el operador trabaja con
    // la BD local.
    final refresh = await _secureStorage.getRefreshToken();
    if (refresh == null || refresh.isEmpty) {
      await _limpiarSesionLocal();
      return SesionRestaurada.invalida;
    }
    try {
      await refreshToken(refresh);
      try {
        final perfil = await _apiClient.getEmpresaPerfil();
        final rutaExp = perfil['ruta_exportacion_reportes'] as String?;
        if (rutaExp != null && rutaExp.trim().isNotEmpty) {
          await SaveFileUtils.setRutaPersonalizada(rutaExp);
        }
      } catch (_) {}
      return SesionRestaurada.ok;
    } on DioException catch (e) {
      if (_esErrorSinConexion(e)) {
        return SesionRestaurada.offline;
      }
      await _limpiarSesionLocal();
      return SesionRestaurada.invalida;
    }
  }

  /// Descarta la sesión local (tokens + usuario cacheado) tras detectar que el
  /// refresh token fue rechazado por el servidor.
  Future<void> _limpiarSesionLocal() async {
    _apiClient.clearToken();
    _apiClient.setServerToken(null);
    await _secureStorage.clearAuth();
    await _secureStorage.clearServerAuth();
    await _localStorage.clearAuth();
    await AppConfig.setOffline(false);
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
