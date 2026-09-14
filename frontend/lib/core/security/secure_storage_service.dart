import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Almacenamiento seguro de tokens y claves sensibles.
///
/// Usa `FlutterSecureStorage` (keychain/keystore). En plataformas sin
/// keyring disponible (p. ej. Linux desktop sin libsecret), degrada a
/// `SharedPreferences` para no romper la sesión, pero siempre elimina la
/// copia en texto plano cuando el almacenamiento seguro funciona.
class SecureStorageService {
  static const String accessTokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String licenseKey = 'licencia_key';

  // Claves legacy usadas por versiones previas en SharedPreferences.
  static const String _legacyAccessKey = 'auth_token';
  static const String _legacyRefreshKey = 'refresh_token';

  final FlutterSecureStorage _storage;

  SecureStorageService({FlutterSecureStorage? storage})
      : _storage =
            storage ?? const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  Future<void> saveTokens(String accessToken, String refreshToken) async {
    await saveAccessToken(accessToken);
    await saveRefreshToken(refreshToken);
  }

  Future<void> saveAccessToken(String token) => _write(accessTokenKey, token);
  Future<void> saveRefreshToken(String token) => _write(refreshTokenKey, token);

  Future<String?> getAccessToken() => _read(accessTokenKey);
  Future<String?> getRefreshToken() => _read(refreshTokenKey);

  Future<void> saveLicenseKey(String key) => _write(licenseKey, key);
  Future<String?> getLicenseKey() => _read(licenseKey);

  Future<void> clearAuth() async {
    await _delete(accessTokenKey);
    await _delete(refreshTokenKey);
  }

  /// Migración one-shot: mueve tokens de SharedPreferences al almacén seguro.
  Future<void> migrateFromSharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final access = prefs.getString(_legacyAccessKey) ?? prefs.getString(accessTokenKey);
    final refresh = prefs.getString(_legacyRefreshKey) ?? prefs.getString(refreshTokenKey);
    final lic = prefs.getString(licenseKey);

    if (access != null && access.isNotEmpty) {
      await _write(accessTokenKey, access);
      await prefs.remove(_legacyAccessKey);
      await prefs.remove(accessTokenKey);
    }
    if (refresh != null && refresh.isNotEmpty) {
      await _write(refreshTokenKey, refresh);
      await prefs.remove(_legacyRefreshKey);
      await prefs.remove(refreshTokenKey);
    }
    if (lic != null && lic.isNotEmpty) {
      await _write(licenseKey, lic);
      await prefs.remove(licenseKey);
    }
  }

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
      // Si el almacenamiento seguro funcionó, eliminar cualquier copia en claro.
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(key)) {
        await prefs.remove(key);
      }
    } catch (_) {
      // Plataforma sin keyring (p. ej. Linux): degradar a SharedPreferences.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    }
  }

  Future<void> _delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}