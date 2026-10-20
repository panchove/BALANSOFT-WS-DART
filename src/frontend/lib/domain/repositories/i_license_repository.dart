// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 27001 / ISO/IEC 25010
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

import '../entities/license.dart';

/// Contrato del repositorio para la validación, activación y almacenamiento de licencias.
///
/// Gestiona la firma Ed25519 y las restricciones de sesiones bajo ISO/IEC 27001.
abstract class ILicenseRepository {
  /// Valida una clave de licencia contra el servidor de licencias (LM).
  ///
  /// Precondiciones:
  /// - [licenseKey] debe ser una clave no vacía (formato canónico `BS-XXXX-XXXX-XXXX` o token firmado).
  ///
  /// Poscondiciones:
  /// - Retorna la entidad [License] validada con fecha de expiración, estado y número de sesiones.
  Future<License> validateLicense(String licenseKey);

  /// Activa una licencia vinculándola al hardware de la máquina local.
  ///
  /// Precondiciones:
  /// - [licenseKey] debe ser válida y no haber excedido el límite de activaciones.
  ///
  /// Poscondiciones:
  /// - Retorna la [License] en estado `activa`.
  /// - Actualiza la caché local segura.
  Future<License> activateLicense(String licenseKey);

  /// Obtiene la licencia almacenada localmente en la caché segura.
  ///
  /// Poscondiciones:
  /// - Retorna [License] si existe registro previo, o `null` si la estación no ha sido activada.
  Future<License?> getCachedLicense();

  /// Persiste una licencia en el almacenamiento seguro local.
  ///
  /// Precondiciones:
  /// - [license] debe estar íntegra y validada criptográficamente.
  Future<void> cacheLicense(License license);

  /// Limpia la licencia almacenada en el dispositivo.
  Future<void> clearCache();

  /// Consulta el servidor central para refrescar el estado de la licencia.
  ///
  /// Poscondiciones:
  /// - Retorna la [License] actualizada si hubo comunicación exitosa, o `null` si se mantiene la versión previa.
  Future<License?> refreshLicense(String licenseKey);
}
