import '../entities/license.dart';
import '../repositories/i_license_repository.dart';
import '../../core/security/device_info.dart';

class ValidateLicenseUseCase {
  final ILicenseRepository _repo;
  ValidateLicenseUseCase(this._repo);

  Future<License> execute(String licenseKey) async {
    final hwInfo = await DeviceInfo.getHardwareInfo();
    return _repo.validateLicense(licenseKey, hwInfo.hardwareId);
  }
}

class ActivateLicenseUseCase {
  final ILicenseRepository _repo;
  ActivateLicenseUseCase(this._repo);

  Future<License> execute(String licenseKey) async {
    final hwInfo = await DeviceInfo.getHardwareInfo();
    return _repo.activateLicense(licenseKey, hwInfo.hardwareId);
  }
}

class GetCachedLicenseUseCase {
  final ILicenseRepository _repo;
  GetCachedLicenseUseCase(this._repo);

  Future<License?> execute() => _repo.getCachedLicense();
}

class ClearLicenseCacheUseCase {
  final ILicenseRepository _repo;
  ClearLicenseCacheUseCase(this._repo);

  Future<void> execute() => _repo.clearCache();
}
