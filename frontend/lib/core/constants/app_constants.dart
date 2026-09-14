class AppConstants {
  static const String appName = 'Balansoft-WS';
  static const String dbName = 'balansoft_ws.db';
  static const int dbVersion = 1;

  // Sync
  static const int syncBatchSize = 50;
  static const int maxSyncRetries = 3;
  static const int syncIntervalMinutes = 2;
  static const int healthCheckSeconds = 30;
}
