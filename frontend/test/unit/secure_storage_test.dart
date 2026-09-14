import 'package:balansoft_ws/core/security/secure_storage_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('SecureStorageService', () {
    test('saveTokens + getAccessToken devuelve el token guardado', () async {
      final service = SecureStorageService();
      await service.saveTokens('jwt-access', 'jwt-refresh');

      expect(await service.getAccessToken(), 'jwt-access');
      expect(await service.getRefreshToken(), 'jwt-refresh');
    });

    test('los tokens NO se guardan en SharedPreferences', () async {
      final service = SecureStorageService();
      await service.saveTokens('jwt-access', 'jwt-refresh');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(SecureStorageService.accessTokenKey), isNull);
      expect(prefs.getString('auth_token'), isNull);
      expect(prefs.getString('refresh_token'), isNull);
    });

    test('clearAuth elimina acceso y refresh', () async {
      final service = SecureStorageService();
      await service.saveTokens('jwt-access', 'jwt-refresh');

      await service.clearAuth();

      expect(await service.getAccessToken(), isNull);
      expect(await service.getRefreshToken(), isNull);
    });

    test('migrateFromSharedPreferences mueve tokens legacy al almacén seguro', () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'legacy-access',
        'refresh_token': 'legacy-refresh',
      });

      final service = SecureStorageService();
      await service.migrateFromSharedPreferences();

      expect(await service.getAccessToken(), 'legacy-access');
      expect(await service.getRefreshToken(), 'legacy-refresh');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), isNull);
      expect(prefs.getString('refresh_token'), isNull);
      expect(prefs.getString(SecureStorageService.accessTokenKey), isNull);
      expect(prefs.getString(SecureStorageService.refreshTokenKey), isNull);
    });

    test('saveLicenseKey/getLicenseKey funcionan', () async {
      final service = SecureStorageService();
      await service.saveLicenseKey('WS-XXXX-XXXX-XXXX-XXXX');

      expect(await service.getLicenseKey(), 'WS-XXXX-XXXX-XXXX-XXXX');
    });
  });
}