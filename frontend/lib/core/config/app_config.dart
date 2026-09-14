import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  static const String appName = 'Balansoft-WS';
  static const String appVersion = '1.0.0';

  static String? apiBaseUrl;
  static String? licenseApiUrl;
  static String? publicKey;

  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    apiBaseUrl = _prefs.getString('api_base_url') ?? 'http://localhost:8000';
    licenseApiUrl = _prefs.getString('license_api_url') ?? 'http://localhost:8080';
    publicKey = _prefs.getString('public_key');
  }

  static SharedPreferences get prefs => _prefs;

  static Future<void> setApiBaseUrl(String url) async {
    apiBaseUrl = url;
    await _prefs.setString('api_base_url', url);
  }
}
