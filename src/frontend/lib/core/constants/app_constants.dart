// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 25010 / ISO/IEC 27001
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

class AppConstants {
  static const String appName = 'Balansoft-WS';
  static const String dbName = 'balansoft_ws.db';
  static const int dbVersion = 5;

  // Sync
  static const int syncBatchSize = 50;
  static const int maxSyncRetries = 3;
  static const int syncIntervalMinutes = 2;
  static const int healthCheckSeconds = 10;

  // Backups automáticos por inactividad (REQ-NF-BKP-001; estación SERVIDOR).
  // Mismo valor por defecto que `backup_auto_idle_minutes` del backend.
  static const int backupAutoIdleMinutes = 5;
}
