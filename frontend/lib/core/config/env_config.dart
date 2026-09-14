class EnvConfig {
  static const String appEnv = String.fromEnvironment('APP_ENV');
  static const bool isDevelopment = bool.fromEnvironment('DEV', defaultValue: false);
  static const bool isProduction = bool.fromEnvironment('PROD', defaultValue: false);
  static const bool isStaging = bool.fromEnvironment('STAGING', defaultValue: false);

  /// Modo kiosk: pantalla completa sin bordes del SO. Se activa en producción.
  static bool get isKiosk => isKioskForEnv(appEnv);

  static bool isKioskForEnv(String env) =>
      env == 'production' || env == 'prod' || isProduction;

  static String get apiBaseUrl =>
      isProduction ? 'https://api.balansoft.com' : 'http://localhost:8000';
}