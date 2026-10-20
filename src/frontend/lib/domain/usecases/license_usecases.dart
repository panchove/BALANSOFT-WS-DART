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

/// Caso de uso para verificar la validez y estado de una licencia contra el servidor.
class ValidateLicenseUseCase {
  final ILicenseRepository _repo;
  ValidateLicenseUseCase(this._repo);

  /// Ejecuta la validación de [licenseKey].
  ///
  /// Precondiciones:
  /// - [licenseKey] no vacía.
  ///
  /// Poscondiciones:
  /// - Retorna [License] con estatus de activación y vigencia.
  Future<License> execute(String licenseKey) async {
    return _repo.validateLicense(licenseKey);
  }
}

/// Caso de uso para activar una clave de licencia en la estación actual.
class ActivateLicenseUseCase {
  final ILicenseRepository _repo;
  ActivateLicenseUseCase(this._repo);

  /// Ejecuta la activación de [licenseKey] enlazándola al hardware local.
  ///
  /// Precondiciones:
  /// - [licenseKey] válida.
  ///
  /// Poscondiciones:
  /// - Retorna [License] activada y actualiza la caché persistente.
  Future<License> execute(String licenseKey) async {
    return _repo.activateLicense(licenseKey);
  }
}

/// Caso de uso para obtener la licencia almacenada en el almacenamiento seguro local.
class GetCachedLicenseUseCase {
  final ILicenseRepository _repo;
  GetCachedLicenseUseCase(this._repo);

  /// Ejecuta la consulta de licencia en caché.
  ///
  /// Poscondiciones:
  /// - Retorna [License] si la máquina está licenciada, o `null`.
  Future<License?> execute() => _repo.getCachedLicense();
}

/// Caso de uso para borrar la licencia persistida localmente.
class ClearLicenseCacheUseCase {
  final ILicenseRepository _repo;
  ClearLicenseCacheUseCase(this._repo);

  /// Ejecuta la eliminación de los datos de licencia locales.
  Future<void> execute() => _repo.clearCache();
}
