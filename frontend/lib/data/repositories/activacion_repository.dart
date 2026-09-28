import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/config/app_config.dart';
import '../../core/config/cuenta_activada.dart';
import '../../core/security/device_info.dart';
import '../../core/security/secure_storage_service.dart';
import '../../data/datasources/remote/api_client.dart';
import '../../data/datasources/local/local_storage.dart';
import '../../data/models/user_model.dart';

/// Resultado de validar la cuenta en el servidor central (paso 3 de la
/// instalación del modo SERVIDOR).
class ActivacionResultado {
  final bool exito;
  final String? error;
  final bool titular;
  final CuentaActivada? cuenta;

  const ActivacionResultado({
    required this.exito,
    this.error,
    this.titular = false,
    this.cuenta,
  });
}

/// Activación de la estación: valida las credenciales que el proveedor
/// entregó contra el servidor central, deja la sesión abierta y guarda los
/// datos de la cuenta para precargar el formulario de empresa.
class ActivacionRepository {
  final ApiClient _apiClient;
  final LocalStorage _localStorage;
  final SecureStorageService _secureStorage;

  ActivacionRepository({
    required ApiClient apiClient,
    required LocalStorage localStorage,
    required SecureStorageService secureStorage,
  })  : _apiClient = apiClient,
        _localStorage = localStorage,
        _secureStorage = secureStorage;

  /// Valida `email`/`password` contra el servidor central.
  ///
  /// Envía `modo_solicitado: SERVIDOR` para que el backend rechace (403) si
  /// esta máquina no es la titular de la licencia. La sesión que devuelve se
  /// guarda: el operador no vuelve a escribir la contraseña.
  Future<ActivacionResultado> activar({
    required String email,
    required String password,
  }) async {
    final serverUrl = (AppConfig.serverApiUrl ?? '').trim().replaceAll(RegExp(r'/$'), '');
    if (serverUrl.isEmpty) {
      return const ActivacionResultado(
        exito: false,
        error: 'No hay servidor central configurado para validar la cuenta.',
      );
    }

    final hw = await DeviceInfo.getHardwareInfo();
    try {
      final response = await _apiClient.loginCentral({
        'email': email,
        'password': password,
        'server_url': serverUrl,
        'hardware_id': hw.hardwareId,
        'mac_address': hw.macAddress,
        'device_brand': hw.brand,
        'device_model': hw.model,
        'os_version': hw.osVersion,
        'version_app': AppConfig.appVersion,
        'modo_solicitado': 'SERVIDOR',
      });
      final data = Map<String, dynamic>.from(response.data as Map);

      final licencia = (data['license'] as Map<String, dynamic>?) ?? const {};
      final titular = licencia['puede_ser_servidor'] == true;

      // La sesión queda abierta: de aquí en adelante la estación ya está
      // autenticada y el operador entra directo tras guardar los datos.
      await _secureStorage.saveTokens(data['access_token'], data['refresh_token']);
      _apiClient.setToken(data['access_token']);

      final usuario = data['user'];
      if (usuario is Map<String, dynamic>) {
        await _localStorage.saveUser(UserModel.fromJson(usuario));
      }

      final cuenta = CuentaActivada.fromLoginResponse(
        data,
        email: email,
        titular: titular,
      );
      if (!cuenta.tieneDatos) {
        return const ActivacionResultado(
          exito: false,
          error: 'El servidor central no devolvió los datos de la empresa.',
        );
      }
      await CuentaActivada.guardar(cuenta);
      await AppConfig.setLicenciaVerificada(verificada: true, titular: titular);

      return ActivacionResultado(exito: true, titular: titular, cuenta: cuenta);
    } on DioException catch (e) {
      return ActivacionResultado(
        exito: false,
        error: _mensaje(e),
      );
    } catch (e) {
      return ActivacionResultado(
        exito: false,
        error: 'No se pudo validar la cuenta: $e',
      );
    }
  }

  /// Traduce el error del backend a un mensaje entendible para el instalador.
  ///
  /// Importante: el backend devuelve 502 tanto si no hay red hacia el central
  /// como si el central respondió con un error propio (500, 422…), y en ambos
  /// casos manda el `detail` real en el cuerpo. **Nunca** se descarta ese
  /// detalle: es lo único que distingue "no hay internet" de "la cuenta está
  /// mal" o "el central falló".
  @visibleForTesting
  static String mensajeDe(DioException e) => _mensaje(e);

  static String _mensaje(DioException e) {
    final status = e.response?.statusCode;
    var detalle = e.message ?? 'Error inesperado';
    final data = e.response?.data;
    if (data is Map && data['detail'] != null) {
      detalle = data['detail'].toString();
    }

    // Sin respuesta del servidor: no se alcanzó la API. Puede ser la red o
    // que la API local (WServer) no esté levantada.
    if (e.response == null) {
      final esTimeout = e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout;
      if (esTimeout) {
        return 'No hubo respuesta de la API de esta máquina. Revise que el '
            'servidor local esté encendido y que el antivirus no bloquee el '
            'puerto.';
      }
      return 'No se pudo contactar la API de esta máquina ($detalle). '
          'Verifique que el servidor local esté ejecutándose.';
    }

    return switch (status) {
      401 => 'Credenciales incorrectas. Verifique el correo y la contraseña '
          'entregados por el proveedor.',
      403 => detalle,
      502 => 'El servidor central no pudo validar la cuenta: $detalle',
      _ => detalle,
    };
  }
}
