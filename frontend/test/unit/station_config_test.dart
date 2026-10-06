import 'dart:io';

import 'package:balansoft_ws/core/config/station_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Contrato `config.json` (BALANSOFT-INSTALLER `core/station_config.py`):
/// exactamente dos claves, urls http/https sin credenciales ni path, rol
/// SERVIDOR|TRABAJADOR, override de usuario con prioridad sobre el de sistema
/// y error duro si el archivo presente es inválido. Sin archivos ni legado,
/// error `ausente`.
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('station_config_test_');
    StationConfigPaths.pruebasOverrideDir = '${tmp.path}/override';
    StationConfigPaths.pruebasSistemaDir = '${tmp.path}/sistema';
  });

  tearDown(() {
    StationConfigPaths.pruebasOverrideDir = null;
    StationConfigPaths.pruebasSistemaDir = null;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('validarApiBaseUrl', () {
    test('acepta http/https con y sin path raíz', () {
      expect(validarApiBaseUrl('http://192.168.1.10:8000'), isTrue);
      expect(validarApiBaseUrl('http://192.168.1.10:8000/'), isTrue);
      expect(validarApiBaseUrl('https://ws.balansoft.com.ve'), isTrue);
      expect(validarApiBaseUrl('https://api.balansoft.com/'), isTrue);
    });

    test('rechaza esquema no http(s), host vacío y credenciales', () {
      expect(validarApiBaseUrl('ftp://x.com'), isFalse);
      expect(validarApiBaseUrl('http://'), isFalse);
      expect(validarApiBaseUrl('http://user:pass@x.com'), isFalse);
    });

    test('rechaza query, fragmento y path distinto de raíz', () {
      expect(validarApiBaseUrl('http://x.com?a=1'), isFalse);
      expect(validarApiBaseUrl('http://x.com#frag'), isFalse);
      expect(validarApiBaseUrl('http://x.com/api'), isFalse);
      expect(validarApiBaseUrl('http://x.com/a/'), isFalse);
    });

    test('rechaza puerto fuera de rango (0 y >65535)', () {
      expect(validarApiBaseUrl('http://x.com:0'), isFalse);
      expect(validarApiBaseUrl('http://x.com:99999'), isFalse);
      expect(validarApiBaseUrl('http://x.com:65536'), isFalse);
      expect(validarApiBaseUrl('http://x.com:8000'), isTrue);
    });
  });

  group('StationRole.parse', () {
    test('reconoce exactamente SERVIDOR y TRABAJADOR', () {
      expect(StationRole.parse('SERVIDOR'), StationRole.servidor);
      expect(StationRole.parse(' TRABAJADOR '), StationRole.trabajador);
      expect(StationRole.servidor.etiqueta, 'SERVIDOR');
      expect(StationRole.trabajador.etiqueta, 'TRABAJADOR');
    });

    test('lanza con cualquier otro valor o nulo', () {
      expect(() => StationRole.parse('servidor'), throwsFormatException);
      expect(() => StationRole.parse('LOCAL'), throwsFormatException);
      expect(() => StationRole.parse(''), throwsFormatException);
      expect(() => StationRole.parse(null), throwsArgumentError);
    });
  });

  group('cargar: override → sistema → legado → ausente', () {
    test('sin archivos ni legado lanza ausente', () async {
      SharedPreferences.setMockInitialValues({});
      await expectLater(
        StationConfigLoader.cargar(),
        throwsA(isA<StationConfigError>()
            .having((e) => e.motivo, 'motivo', StationConfigErrorType.ausente)),
      );
    });

    test('lee el override y lo prefiere sobre el sistema', () async {
      final dir = Directory(StationConfigPaths.pruebasOverrideDir!);
      await dir.create(recursive: true);
      await File('${dir.path}/config.json').writeAsString(
        '{"api_base_url": "http://10.0.0.5:8000", "rol": "TRABAJADOR"}',
      );
      final dirS = Directory(StationConfigPaths.pruebasSistemaDir!);
      await dirS.create(recursive: true);
      await File('${dirS.path}/config.json').writeAsString(
        '{"api_base_url": "http://10.0.0.1:8000", "rol": "SERVIDOR"}',
      );

      final cfg = await StationConfigLoader.cargar();
      expect(cfg.apiBaseUrl, 'http://10.0.0.5:8000');
      expect(cfg.rol, StationRole.trabajador);
    });

    test('cae al sistema cuando no existe override', () async {
      final dirS = Directory(StationConfigPaths.pruebasSistemaDir!);
      await dirS.create(recursive: true);
      await File('${dirS.path}/config.json').writeAsString(
        '{"api_base_url": "http://srv:8000", "rol": "SERVIDOR"}',
      );

      final cfg = await StationConfigLoader.cargar();
      expect(cfg.apiBaseUrl, 'http://srv:8000');
      expect(cfg.rol, StationRole.servidor);
    });
  });

  group('error duro: archivo presente pero inválido', () {
    test('JSON no válido', () async {
      final dir = Directory(StationConfigPaths.pruebasOverrideDir!);
      await dir.create(recursive: true);
      await File('${dir.path}/config.json').writeAsString('{no-json');

      await expectLater(
        StationConfigLoader.cargar(),
        throwsA(isA<StationConfigError>()
            .having((e) => e.motivo, 'motivo', StationConfigErrorType.jsonInvalido)),
      );
    });

    test('claves incompletas o extra', () async {
      final dir = Directory(StationConfigPaths.pruebasOverrideDir!);
      await dir.create(recursive: true);
      await File('${dir.path}/config.json')
          .writeAsString('{"api_base_url": "http://x.com:8000"}');
      await expectLater(
        StationConfigLoader.cargar(),
        throwsA(isA<StationConfigError>()
            .having((e) => e.motivo, 'motivo', StationConfigErrorType.camposInvalidos)),
      );

      await File('${dir.path}/config.json').writeAsString(
        '{"api_base_url": "http://x.com:8000", "rol": "SERVIDOR", "extra": 1}',
      );
      await expectLater(
        StationConfigLoader.cargar(),
        throwsA(isA<StationConfigError>()
            .having((e) => e.motivo, 'motivo', StationConfigErrorType.camposInvalidos)),
      );
    });

    test('rol desconocido', () async {
      final dir = Directory(StationConfigPaths.pruebasOverrideDir!);
      await dir.create(recursive: true);
      await File('${dir.path}/config.json').writeAsString(
        '{"api_base_url": "http://x.com:8000", "rol": "ADMIN"}',
      );
      await expectLater(
        StationConfigLoader.cargar(),
        throwsA(isA<StationConfigError>()
            .having((e) => e.motivo, 'motivo', StationConfigErrorType.esquemaInvalido)),
      );
    });

    test('URL inválida', () async {
      final dir = Directory(StationConfigPaths.pruebasOverrideDir!);
      await dir.create(recursive: true);
      await File('${dir.path}/config.json').writeAsString(
        '{"api_base_url": "ftp://x.com", "rol": "SERVIDOR"}',
      );
      await expectLater(
        StationConfigLoader.cargar(),
        throwsA(isA<StationConfigError>()
            .having((e) => e.motivo, 'motivo', StationConfigErrorType.esquemaInvalido)),
      );
    });

    test('el error del override no se degrada al sistema', () async {
      final dir = Directory(StationConfigPaths.pruebasOverrideDir!);
      await dir.create(recursive: true);
      await File('${dir.path}/config.json').writeAsString('{mal');
      final dirS = Directory(StationConfigPaths.pruebasSistemaDir!);
      await dirS.create(recursive: true);
      await File('${dirS.path}/config.json').writeAsString(
        '{"api_base_url": "http://ok:8000", "rol": "SERVIDOR"}',
      );

      await expectLater(
        StationConfigLoader.cargar(),
        throwsA(isA<StationConfigError>()),
      );
    });
  });

  group('migración única del legado', () {
    test('sin archivos migra prefs válidas al override y limpia el legado',
        () async {
      SharedPreferences.setMockInitialValues({
        'api_base_url': 'http://192.168.1.20:8000',
        'modo_estacion': 'TRABAJADOR',
        'licencia_verificada': true,
        'setup_preferencias_completado': true,
      });

      final cfg = await StationConfigLoader.cargar(migrarLegado: true);
      expect(cfg.apiBaseUrl, 'http://192.168.1.20:8000');
      expect(cfg.rol, StationRole.trabajador);

      // El archivo quedó escrito y las claves legadas fueron limpiadas.
      final f = File(StationConfigPaths.overridePath);
      expect(await f.exists(), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('api_base_url'), isNull);
      expect(prefs.getString('modo_estacion'), isNull);
      expect(prefs.getBool('licencia_verificada'), isNull);
      expect(prefs.getBool('setup_preferencias_completado'), isNull);

      // Segunda carga: ya no toca prefs, lee el archivo.
      final cfg2 = await StationConfigLoader.cargar();
      expect(cfg2.apiBaseUrl, 'http://192.168.1.20:8000');
      expect(cfg2.rol, StationRole.trabajador);
    });

    test('no migra si faltan claves legadas o la URL es inválida', () async {
      SharedPreferences.setMockInitialValues({'api_base_url': 'ftp://x'});
      await expectLater(
        StationConfigLoader.cargar(migrarLegado: true),
        throwsA(isA<StationConfigError>()
            .having((e) => e.motivo, 'motivo', StationConfigErrorType.ausente)),
      );
    });
  });

  group('escritura del override', () {
    test('escribe 2 claves, modo 0600 y volumen legible', () async {
      const cfg = StationConfig(
        apiBaseUrl: 'http://10.1.1.7:8000',
        rol: StationRole.servidor,
      );
      await StationConfigWriter.escribirOverride(cfg);

      final f = File(StationConfigPaths.overridePath);
      expect(await f.exists(), isTrue);
      final json = await f.readAsString();
      expect(json, contains('"api_base_url": "http://10.1.1.7:8000"'));
      expect(json, contains('"rol": "SERVIDOR"'));

      if (!Platform.isWindows) {
        final stat = await f.stat();
        // 0600 = rw para el dueño, nada para el resto.
        expect(stat.mode & 0x1FF, 0x180);
      }
    });

    test('actualizarApiBaseUrl conserva el rol', () async {
      SharedPreferences.setMockInitialValues({});
      await StationConfigWriter.escribirOverride(const StationConfig(
        apiBaseUrl: 'http://old:8000',
        rol: StationRole.trabajador,
      ));

      await StationConfigWriter.actualizarApiBaseUrl('http://new:9000');
      final cfg = await StationConfigLoader.cargar();
      expect(cfg.apiBaseUrl, 'http://new:9000');
      expect(cfg.rol, StationRole.trabajador);
    });

    test('actualizarApiBaseUrl rechaza URL inválida', () async {
      SharedPreferences.setMockInitialValues({});
      await StationConfigWriter.escribirOverride(const StationConfig(
        apiBaseUrl: 'http://old:8000',
        rol: StationRole.servidor,
      ));
      await expectLater(
        StationConfigWriter.actualizarApiBaseUrl('http://x.com:99999'),
        throwsFormatException,
      );
    });
  });
}