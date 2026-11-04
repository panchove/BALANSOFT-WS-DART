import 'package:connectivity_plus/connectivity_plus.dart';
import '../../domain/entities/license.dart';
import '../../domain/repositories/i_license_repository.dart';
import '../../core/security/device_info.dart';
import '../datasources/remote/api_client.dart';
import '../datasources/local/local_storage.dart';
import 'package:dio/dio.dart';

class LicenseRepository implements ILicenseRepository {
  final ApiClient _apiClient;
  final LocalStorage _localStorage;
  final Connectivity _connectivity;

  LicenseRepository({
    required ApiClient apiClient,
    required LocalStorage localStorage,
    required Connectivity connectivity,
  })  : _apiClient = apiClient,
        _localStorage = localStorage,
        _connectivity = connectivity;

  Future<bool> get _isConnected async {
    final results = await _connectivity.checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  /// Traduce los errores técnicos del servidor (WServer o LM) a mensajes claros.
  String _traducirError(dynamic e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data.containsKey('detail')) {
        final detail = data['detail'];
        if (detail is String) {
          // Si el WServer responde con un error del License Manager
          if (detail.contains('Firma Ed25519') || detail.contains('inválida')) {
            return 'Error de seguridad: La firma de la licencia no es válida. Contacte a soporte.';
          }
          if (detail.contains('no está disponible') || detail.contains('no respondió')) {
            return 'El servidor de licencias no responde. Verifique su conexión a internet.';
          }
          if (detail.contains('no existe en el License Manager')) {
            return 'La licencia ingresada no existe. Verifique la clave.';
          }
          if (detail.contains('ya tiene una empresa configurada')) {
            return 'Esta estación ya ha sido configurada previamente.';
          }
          return detail;
        }
        if (detail is Map && detail.containsKey('message')) {
          return detail['message'].toString();
        }
      }
      return e.message ?? 'Error de conexión con el servidor.';
    }
    return e.toString().replaceAll('Exception: ', '');
  }

  @override
  Future<License> validateLicense(String licenseKey) async {
    if (!await _isConnected) {
      final cached = await getCachedLicense();
      if (cached != null) return cached;
      throw Exception('Sin conexión a internet y no hay una licencia guardada en este equipo.');
    }

    try {
      final hwInfo = await DeviceInfo.getHardwareInfo();
      
      // Llamamos al WServer local. Él se encargará de hablar con el LM 
      // (obtener token, activar si es necesario, y validar).
      final response = await _apiClient.setupValidarLicencia({
        'license_key': licenseKey,
        'hardware_id': hwInfo.hardwareId,
        'mac_address': hwInfo.macAddress,
        'device_brand': hwInfo.brand,
        'device_model': hwInfo.model,
        'os_version': hwInfo.osVersion,
      });

      // WServer responde con un SetupValidateResponse
      final data = response.data as Map<String, dynamic>;

      if (data['valid'] == false) {
         throw Exception(data['message'] ?? 'La licencia no es válida o no está activa.');
      }

      // Si la respuesta es válida, construimos la entidad License
      final license = License.fromJson({
        'license_key': licenseKey,
        'valid': data['valid'],
        'status': data['status'],
        'tier': data['tier'],
        'expires_at': data['expires_at'],
        'client_email': data['client_email'],
        'client_name': data['client_name'],
        'client_id': data['client_id'],
        // Agregamos campos por defecto para evitar nulls si la entidad los requiere
        'plan_type': 'basic',
        'features': {}, 
      });

      await cacheLicense(license);
      return license;

    } catch (e) {
      throw Exception(_traducirError(e));
    }
  }

  @override
  Future<License> activateLicense(String licenseKey) async {
    // En esta arquitectura, la activación la hace el WServer internamente.
    // El método validateLicense ya llama al endpoint correcto.
    // Simplemente redirigimos para mantener la interfaz limpia.
    return validateLicense(licenseKey);
  }

  @override
  Future<License?> getCachedLicense() async {
    final data = await _localStorage.getCachedLicenseAsync();
    if (data == null) return null;
    return License.fromJson(data);
  }

  @override
  Future<void> cacheLicense(License license) async {
    await _localStorage.cacheLicense(license.toJson());
  }

  @override
  Future<void> clearCache() async {
    await _localStorage.clearLicense();
  }

  @override
  Future<License?> refreshLicense(String licenseKey) async {
    try {
      return await validateLicense(licenseKey);
    } catch (_) {
      return getCachedLicense();
    }
  }
}