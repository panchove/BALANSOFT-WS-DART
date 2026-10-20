// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 27001 / ISO/IEC 25010
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

import '../entities/license.dart';

abstract class ILicenseRepository {
  Future<License> validateLicense(String licenseKey);
  Future<License> activateLicense(String licenseKey);
  Future<License?> getCachedLicense();
  Future<void> cacheLicense(License license);
  Future<void> clearCache();
  Future<License?> refreshLicense(String licenseKey);
}
