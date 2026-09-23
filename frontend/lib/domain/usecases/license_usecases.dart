import '../entities/license.dart';
import '../repositories/i_license_repository.dart';

class ValidateLicenseUseCase {
  final ILicenseRepository _repo;
  ValidateLicenseUseCase(this._repo);

  Future<License> execute(String licenseKey) async {
    return _repo.validateLicense(licenseKey);
  }
}

class ActivateLicenseUseCase {
  final ILicenseRepository _repo;
  ActivateLicenseUseCase(this._repo);

  Future<License> execute(String licenseKey) async {
    return _repo.activateLicense(licenseKey);
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
