import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../models/user_model.dart';
import '../../../domain/entities/user.dart';
import '../../../core/security/secure_storage_service.dart';

import '../../../domain/entities/printer_preset.dart';

/// Almacenamiento local del cliente.
///
/// TODO lo sensible (usuario con rol, licencia y matriz de accesos) vive en el
/// almacén seguro a través de [SecureStorageService]; NADA de esto se persiste
/// en texto plano (`SharedPreferences`). Solo quedan en SharedPreferences
/// parámetros NO sensibles: host/puerto de la báscula y directorios de
/// exportación.
class LocalStorage {
  static const _userKey = 'cached_user';
  static const _licenseKey = 'cached_license';
  static const _scaleHostKey = 'scale_host';
  static const _scalePortKey = 'scale_port';
  static const _accesosKey = 'cached_matriz_accesos';
  static const _printerPresetKey = 'printer_preset';

  final SecureStorageService _secure;

  LocalStorage({SecureStorageService? secureStorage})
      : _secure = secureStorage ?? SecureStorageService();

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<void> saveUser(User user) async {
    final userModel = UserModel.fromEntity(user);
    await _secure.writeRaw(_userKey, jsonEncode(userModel.toJson()));
  }

  Future<User?> getCachedUser() async {
    final json = await _secure.readRaw(_userKey);
    if (json == null) return null;
    return UserModel.fromJson(jsonDecode(json));
  }

  Future<void> cacheLicense(Map<String, dynamic> license) async {
    await _secure.writeRaw(_licenseKey, jsonEncode(license));
  }

  Map<String, dynamic>? getCachedLicense() {
    return null;
  }

  Future<Map<String, dynamic>?> getCachedLicenseAsync() async {
    final json = await _secure.readRaw(_licenseKey);
    if (json == null) return null;
    return jsonDecode(json);
  }

  Future<void> clearLicense() async {
    await _secure.clearRaw(_licenseKey);
  }

  Future<void> clearAuth() async {
    await _secure.clearRaw(_userKey);
  }

  Future<void> setScaleConfig({required String host, required int port}) async {
    final prefs = await _prefs;
    await prefs.setString(_scaleHostKey, host);
    await prefs.setInt(_scalePortKey, port);
  }

  Future<({String host, int port})> getScaleConfig() async {
    final prefs = await _prefs;
    final host = prefs.getString(_scaleHostKey) ?? '127.0.0.1';
    final port = prefs.getInt(_scalePortKey) ?? 5555;
    return (host: host, port: port);
  }

  Future<void> cacheMatrizAccesos(Map<String, Map<String, String>> matriz) async {
    await _secure.writeRaw(_accesosKey, jsonEncode(matriz));
  }

  Future<Map<String, Map<String, String>>?> getCachedMatrizAccesos() async {
    final raw = await _secure.readRaw(_accesosKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (modulo, row) => MapEntry<String, Map<String, String>>(
          modulo,
          (row as Map).map(
            (rol, acceso) => MapEntry(rol.toString(), acceso.toString()),
          ),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clearMatrizAccesos() async {
    await _secure.clearRaw(_accesosKey);
  }

  Future<String> getDescargasDir() async {
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) return downloads.path;
      final docs = await getApplicationDocumentsDirectory();
      return docs.path;
    } catch (_) {
      return Directory.systemTemp.path;
    }
  }

  Future<void> savePrinterPreset(PrinterPreset preset) async {
    final prefs = await _prefs;
    await prefs.setString(_printerPresetKey, jsonEncode(preset.toJson()));
  }

  Future<PrinterPreset> getPrinterPreset() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_printerPresetKey);
    if (raw == null) return const PrinterPreset();
    try {
      return PrinterPreset.fromJson(jsonDecode(raw));
    } catch (_) {
      return const PrinterPreset();
    }
  }
}