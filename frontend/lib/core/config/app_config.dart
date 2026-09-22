import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  static const String appName = 'Balansoft-WS';
  static const String appVersion = '1.0.0';

  static const String defaultServerApiUrl = 'http://ws.balansoft.com.ve';
  static const String defaultApiBaseUrl = 'http://localhost:8000';

  static String? apiBaseUrl;
  static String? serverApiUrl;
  static String? licenseApiUrl;
  static String? publicKey;
  static bool offline = false;
  static bool wserverAutostart = false;

  static late SharedPreferences _prefs;

  /// La URL de la API LOCAL (estación) aún no se ha configurado.
  static bool get localApiConfigured =>
      apiBaseUrl != null && apiBaseUrl!.trim().isNotEmpty;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    // El servidor central SIEMPRE está presente (default); la API local queda
    // sin valor hasta que se configure en la primera ejecución.
    apiBaseUrl = _prefs.getString('api_base_url');
    serverApiUrl = _prefs.getString('server_api_url') ?? defaultServerApiUrl;
    licenseApiUrl = _prefs.getString('license_api_url') ?? 'http://localhost:8080';
    publicKey = _prefs.getString('public_key');
    offline = _prefs.getBool('offline') ?? false;
    wserverAutostart = _prefs.getBool('wserver_autostart') ?? false;
  }

  static SharedPreferences get prefs => _prefs;

  /// URL de la API local (estación): se configura en "Conexiones" si no existe.
  static Future<void> setApiBaseUrl(String url) async {
    apiBaseUrl = url;
    await _prefs.setString('api_base_url', url);
  }

  /// Borra la URL local configurada: devuelve la app al modo instalación
  /// (verificación de entorno + pantalla de conexiones).
  static Future<void> quitarApiBaseUrl() async {
    apiBaseUrl = null;
    await _prefs.remove('api_base_url');
  }

  /// URL del servidor central (cuenta y licencia). Siempre disponible.
  static Future<void> setServerApiUrl(String url) async {
    serverApiUrl = url;
    await _prefs.setString('server_api_url', url);
  }

  /// Marca el estado offline de la estación (sesión con login-local).
  static Future<void> setOffline(bool value) async {
    offline = value;
    await _prefs.setBool('offline', value);
  }

  /// ¿Arrancar el WServer automáticamente al encender el equipo?
  static Future<void> setWServerAutostart(bool value) async {
    wserverAutostart = value;
    await _prefs.setBool('wserver_autostart', value);
  }
}
