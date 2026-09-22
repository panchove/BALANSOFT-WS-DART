import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Almacenamiento seguro de tokens, claves sensibles y caché de sesión.
///
/// Patrón portado desde BALANSOFT-SG: TODO lo sensible vive SOLO en el
/// almacén seguro del sistema (keychain/keystore, en Android con AEncryptedSharedPreferences).
///
/// Regla de seguridad: **no hay fallback a SharedPreferences en claro**.
/// Si el almacén seguro no está disponible (p. ej. Linux desktop sin
/// keyring/libsecret), los valores se conservan únicamente EN MEMORIA durante
/// la sesión del proceso: al reiniciar la app se requerirá volver a iniciar
/// sesión, y nunca queda un token/rol/licencia en texto plano en disco.
class SecureStorageService {
  static const String accessTokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String serverAccessTokenKey = 'server_access_token';
  static const String serverRefreshTokenKey = 'server_refresh_token';
  static const String licenseKey = 'licencia_key';

  // Claves legacy usadas por versiones previas en SharedPreferences.
  static const String _legacyAccessKey = 'auth_token';
  static const String _legacyRefreshKey = 'refresh_token';

  final FlutterSecureStorage _storage;

  // Caché de sesión en memoria: respaldo SOLO del mismo proceso cuando la
  // plataforma no dispone de keyring. No se persiste nunca en disco.
  final Map<String, String> _memoria = {};

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

  /// Tokens de la sesión contra el servidor central (credencial global).
  Future<void> saveServerTokens(String accessToken, String refreshToken) async {
    await _write(serverAccessTokenKey, accessToken);
    await _write(serverRefreshTokenKey, refreshToken);
  }

  Future<String?> getServerAccessToken() => _read(serverAccessTokenKey);
  Future<String?> getServerRefreshToken() => _read(serverRefreshTokenKey);

  Future<void> saveLicenseKey(String key) => _write(licenseKey, key);
  Future<String?> getLicenseKey() => _read(licenseKey);

  /// Lectura/escritura cruda dentro del mismo vault seguro: la usa
  /// `LocalStorage` para la caché de sesión (usuario con rol, matriz de
  /// accesos y licencia) evitando compartir código de texto plano.
  Future<String?> readRaw(String key) => _read(key);

  Future<void> writeRaw(String key, String value) => _write(key, value);

  Future<void> clearAuth() async {
    await _delete(accessTokenKey);
    await _delete(refreshTokenKey);
  }

  Future<void> clearServerAuth() async {
    await _delete(serverAccessTokenKey);
    await _delete(serverRefreshTokenKey);
  }

  Future<void> clearRaw(String key) => _delete(key);

  /// Migración one-shot: mueve valores legacy de SharedPreferences al almacén
  /// seguro y BORRA siempre las copias en claro (tokens y licencia).
  Future<void> migrateFromSharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final access = prefs.getString(_legacyAccessKey) ?? prefs.getString(accessTokenKey);
    final refresh = prefs.getString(_legacyRefreshKey) ?? prefs.getString(refreshTokenKey);
    final lic = prefs.getString(licenseKey);

    if (access != null && access.isNotEmpty) {
      await _write(accessTokenKey, access);
    }
    if (refresh != null && refresh.isNotEmpty) {
      await _write(refreshTokenKey, refresh);
    }
    if (lic != null && lic.isNotEmpty) {
      await _write(licenseKey, lic);
    }
    // Eliminar SIEMPRE el texto plano, aunque el almacén seguro no estuviera
    // disponible (ahí el valor queda solo en memoria de esta sesión).
    await prefs.remove(_legacyAccessKey);
    await prefs.remove(accessTokenKey);
    await prefs.remove(_legacyRefreshKey);
    await prefs.remove(refreshTokenKey);
    await prefs.remove(licenseKey);
  }

  Future<String?> _read(String key) async {
    try {
      final value = await _storage.read(key: key);
      if (value != null && value.isNotEmpty) {
        _memoria[key] = value;
        return value;
      }
    } catch (_) {
      // Almacén seguro no disponible: solo queda la memoria de la sesión.
    }
    return _memoria[key];
  }

  Future<void> _write(String key, String value) async {
    _memoria[key] = value;
    try {
      await _storage.write(key: key, value: value);
      // Si el almacén seguro funcionó, eliminar cualquier copia en claro.
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(key)) {
        await prefs.remove(key);
      }
    } catch (_) {
      // Plataforma sin keyring (p. ej. Linux): NO se escribe en claro. La
      // sesión vive solo en memoria (re-login al reiniciar la app).
    }
  }

  Future<void> _delete(String key) async {
    _memoria.remove(key);
    try {
      await _storage.delete(key: key);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}