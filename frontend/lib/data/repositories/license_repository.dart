import 'package:connectivity_plus/connectivity_plus.dart';
import '../../domain/entities/license.dart';
import '../../domain/repositories/i_license_repository.dart';
import '../../core/security/device_info.dart';
import '../datasources/remote/api_client.dart';
import '../datasources/local/local_storage.dart';

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
    final result = await _connectivity.checkConnectivity();
    return result != ConnectivityResult.none;
  }

  @override
  Future<License> validateLicense(String licenseKey, String hardwareId) async {
    if (!await _isConnected) {
      final cached = await getCachedLicense();
      if (cached != null) return cached;
      throw Exception('Sin conexión y sin licencia cacheada');
    }

    final hwInfo = await DeviceInfo.getHardwareInfo();
    final response = await _apiClient.validateLicense({
      'licencia_key': licenseKey,
      'hardware_id': hwInfo.hardwareId,
    });

    final license = License.fromJson(response.data);
    await cacheLicense(license);
    return license;
  }

  @override
  Future<License> activateLicense(String licenseKey, String hardwareId) async {
    final hwInfo = await DeviceInfo.getHardwareInfo();
    final response = await _apiClient.validateLicense({
      'licencia_key': licenseKey,
      'hardware_id': hwInfo.hardwareId,
    });

    final license = License.fromJson(response.data);
    await cacheLicense(license);
    return license;
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
      final hwInfo = await DeviceInfo.getHardwareInfo();
      return await validateLicense(licenseKey, hwInfo.hardwareId);
    } catch (_) {
      return getCachedLicense();
    }
  }
}
