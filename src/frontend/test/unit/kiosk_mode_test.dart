import 'package:balansoft_ws/core/config/env_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EnvConfig modo kiosk', () {
    test('isKioskForEnv es true cuando APP_ENV=production', () {
      expect(EnvConfig.isKioskForEnv('production'), isTrue);
      expect(EnvConfig.isKioskForEnv('prod'), isTrue);
    });

    test('isKioskForEnv es false en desarrollo o sin variable', () {
      expect(EnvConfig.isKioskForEnv('development'), isFalse);
      expect(EnvConfig.isKioskForEnv(''), isFalse);
    });
  });
}