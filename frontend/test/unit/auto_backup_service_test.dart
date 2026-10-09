import 'dart:async';

import 'package:balansoft_ws/application/backup/auto_backup_service.dart';
import 'package:balansoft_ws/core/config/app_config.dart';
import 'package:balansoft_ws/core/config/station_config.dart';
import 'package:balansoft_ws/data/datasources/remote/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeApi extends ApiClient {
  int crearLlamadas = 0;

  @override
  Future<Map<String, dynamic>> crearBackupAuto() async {
    crearLlamadas++;
    return const {'archivo': 'backup_test.json.gz'};
  }
}

class _FakeApiLento extends ApiClient {
  final completer = Completer<Map<String, dynamic>>();
  int crearLlamadas = 0;

  @override
  Future<Map<String, dynamic>> crearBackupAuto() {
    crearLlamadas++;
    return completer.future;
  }
}

class _FakeApiQueFalla extends ApiClient {
  @override
  Future<Map<String, dynamic>> crearBackupAuto() async {
    throw Exception('sin red');
  }
}

void main() {
  tearDown(() {
    AppConfig.rol = null;
  });

  group('AutoBackupService', () {
    test('en TRABAJADOR no dispara respaldos', () async {
      AppConfig.rol = StationRole.trabajador;
      final api = _FakeApi();
      final service = AutoBackupService(apiClient: api);
      service.ultimaActividad = DateTime.now().subtract(
            const Duration(hours: 1),
          );
      expect(service.habilitado, isFalse);
      final creado = await service.verificarBackup();
      expect(creado, isFalse);
      expect(api.crearLlamadas, 0);
    });

    test('con actividad reciente no dispara', () async {
      AppConfig.rol = StationRole.servidor;
      final api = _FakeApi();
      final service = AutoBackupService(apiClient: api);
      service.ultimaActividad = DateTime.now();
      final creado = await service.verificarBackup();
      expect(creado, isFalse);
      expect(api.crearLlamadas, 0);
    });

    test('en SERVIDOR con inactividad superada dispara el respaldo', () async {
      AppConfig.rol = StationRole.servidor;
      final api = _FakeApi();
      final service = AutoBackupService(apiClient: api);
      service.ultimaActividad = DateTime.now().subtract(
            const Duration(minutes: 10),
          );
      final creado = await service.verificarBackup();
      expect(creado, isTrue);
      expect(api.crearLlamadas, 1);
    });

    test('no duplica mientras hay un respaldo en curso', () async {
      AppConfig.rol = StationRole.servidor;
      final api = _FakeApiLento();
      final service = AutoBackupService(apiClient: api);
      service.ultimaActividad = DateTime.now().subtract(
            const Duration(minutes: 10),
          );
      final f1 = service.verificarBackup();
      final f2 = service.verificarBackup();
      api.completer.complete(const {'archivo': 'a'});
      final r1 = await f1;
      final r2 = await f2;
      expect(r1, isTrue);
      expect(r2, isFalse);
      expect(api.crearLlamadas, 1);
    });

    test('los fallos de red son silenciosos y no rompen el flujo', () async {
      AppConfig.rol = StationRole.servidor;
      final service = AutoBackupService(apiClient: _FakeApiQueFalla());
      service.ultimaActividad = DateTime.now().subtract(
            const Duration(minutes: 10),
          );
      final creado = await service.verificarBackup();
      expect(creado, isFalse);
    });
  });
}