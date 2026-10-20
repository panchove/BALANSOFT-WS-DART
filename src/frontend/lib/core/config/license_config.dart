// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 27001 / ISO/IEC 25010
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

class LicenseConfig {
  static const String productCode = 'WS';
  static const int demoMaxRecords = 10;
  static const int monopuestaMaxUsers = 1;
  static const int centralMaxUsers = 10;
  static const Duration licenseRefreshInterval = Duration(hours: 24);
  static const Duration cacheMaxAge = Duration(minutes: 30);
}
