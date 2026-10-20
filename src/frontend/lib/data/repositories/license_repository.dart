// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 27001 / ISO/IEC 25010
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

import 'package:connectivity_plus/connectivity_plus.dart';
import '../../domain/entities/license.dart';
import '../../domain/repositories/i_license_repository.dart';
import '../../core/security/device_info.dart';
import '../datasources/remote/api_client.dart';
import '../datasources/local/local_storage.dart';

/// Implementación del repositorio de licencias combinando validación remota y caché local cifrada.
///
/// Gestiona la interacción con el servidor de licencias (LM) bajo ISO/IEC 27001.
class LicenseRepository implements ILicenseRepository {
  final ApiClient _apiClient;
  final LocalStorage _localStorage;
  final Connectivity _connectivity;

  /// Crea una instancia inyectando el cliente API, almacenamiento local y detector de conectividad.
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

  /// Valida una clave de licencia enviando la huella de hardware del dispositivo.
  @override
  Future<License> validateLicense(String licenseKey) async {
    if (!await _isConnected) {
      final cached = await getCachedLicense();
      if (cached != null) return cached;
      throw Exception('Sin conexión y sin licencia cacheada');
    }

    final hwInfo = await DeviceInfo.getHardwareInfo();
    final response = await _apiClient.validateLicense({
      'licencia_key': licenseKey,
      'hardware_id': hwInfo.hardwareId,
      'mac_address': hwInfo.macAddress,
      'device_brand': hwInfo.brand,
      'device_model': hwInfo.model,
      'os_version': hwInfo.osVersion,
    });

    final license = License.fromJson(response.data);
    await cacheLicense(license);
    return license;
  }

  /// Activa la clave de licencia enlazándola de forma permanente a la estación de pesaje.
  @override
  Future<License> activateLicense(String licenseKey) async {
    final hwInfo = await DeviceInfo.getHardwareInfo();
    final response = await _apiClient.validateLicense({
      'licencia_key': licenseKey,
      'hardware_id': hwInfo.hardwareId,
      'mac_address': hwInfo.macAddress,
      'device_brand': hwInfo.brand,
      'device_model': hwInfo.model,
      'os_version': hwInfo.osVersion,
    });

    final license = License.fromJson(response.data);
    await cacheLicense(license);
    return license;
  }

  /// Obtiene la licencia almacenada en el almacenamiento seguro local.
  @override
  Future<License?> getCachedLicense() async {
    final data = await _localStorage.getCachedLicenseAsync();
    if (data == null) return null;
    return License.fromJson(data);
  }

  /// Persiste los datos de licencia serializados en almacenamiento seguro local.
  @override
  Future<void> cacheLicense(License license) async {
    await _localStorage.cacheLicense(license.toJson());
  }

  /// Elimina los registros locales de licencia.
  @override
  Future<void> clearCache() async {
    await _localStorage.clearLicense();
  }

  /// Refresca el estado de la licencia contra el servidor conservando la versión previa en caso de fallo.
  @override
  Future<License?> refreshLicense(String licenseKey) async {
    try {
      return await validateLicense(licenseKey);
    } catch (_) {
      return getCachedLicense();
    }
  }
}
