// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 27001 / ISO/IEC 25010
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

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
