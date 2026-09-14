import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../models/user_model.dart';
import '../../../domain/entities/user.dart';

class LocalStorage {
  static const _userKey = 'cached_user';
  static const _licenseKey = 'cached_license';
  static const _scaleHostKey = 'scale_host';
  static const _scalePortKey = 'scale_port';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<void> saveUser(User user) async {
    final prefs = await _prefs;
    final userModel = UserModel.fromEntity(user);
    await prefs.setString(_userKey, jsonEncode(userModel.toJson()));
  }

  Future<User?> getCachedUser() async {
    final prefs = await _prefs;
    final json = prefs.getString(_userKey);
    if (json == null) return null;
    return UserModel.fromJson(jsonDecode(json));
  }

  Future<void> cacheLicense(Map<String, dynamic> license) async {
    final prefs = await _prefs;
    await prefs.setString(_licenseKey, jsonEncode(license));
  }

  Map<String, dynamic>? getCachedLicense() {
    return null;
  }

  Future<Map<String, dynamic>?> getCachedLicenseAsync() async {
    final prefs = await _prefs;
    final json = prefs.getString(_licenseKey);
    if (json == null) return null;
    return jsonDecode(json);
  }

  Future<void> clearLicense() async {
    final prefs = await _prefs;
    await prefs.remove(_licenseKey);
  }

  Future<void> clearAuth() async {
    final prefs = await _prefs;
    await prefs.remove(_userKey);
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
}
