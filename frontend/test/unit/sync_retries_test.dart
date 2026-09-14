/// T2.3 — Consumo de `maxSyncRetries` / `SYNC_INTERVAL_MINUTES`.
///
/// Verifica que tras agotar los reintentos el pesaje local se marca como
/// `fallido` (deja de reintentarse) y que un push exitoso lo sincroniza.
library;

import 'package:balansoft_ws/data/datasources/local/database_helper.dart';
import 'package:balansoft_ws/data/datasources/remote/api_client.dart';
import 'package:balansoft_ws/data/repositories/weighing_repository.dart';
import 'package:balansoft_ws/domain/entities/weighing.dart';
import 'package:balansoft_ws/domain/repositories/i_weighing_repository.dart';
import 'package:balansoft_ws/domain/usecases/weighing_usecases.dart';
import 'package:balansoft_ws/presentation/providers/bloc/sync/sync_bloc.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _WifiConnectivityPlatform extends ConnectivityPlatform {
  @override
  Future<ConnectivityResult> checkConnectivity() async =>
      ConnectivityResult.wifi;

  @override
  Stream<ConnectivityResult> get onConnectivityChanged =>
      const Stream<ConnectivityResult>.empty();
}

class _FailingApiClient extends ApiClient {
  _FailingApiClient() : super(baseUrl: 'http://localhost:1');

  @override
  Future<Response> createWeighing(Map<String, dynamic> body) async {
    throw DioException(
      requestOptions: RequestOptions(path: '/api/v1/weighing'),
      message: 'Servidor no disponible',
    );
  }
}

class _OkApiClient extends ApiClient {
  _OkApiClient() : super(baseUrl: 'http://localhost:1');

  @override
  Future<Response> createWeighing(Map<String, dynamic> body) async {
    return Response(
      requestOptions: RequestOptions(path: '/api/v1/weighing'),
      statusCode: 201,
      data: {
        'boleto': body['boleto'],
        'id_vehiculo': body['id_vehiculo'],
        'remolque': false,
        'fecha_hora_entrada': '2026-09-08T08:00:00.000Z',
        'peso_entrada_vehiculo': '50000.00',
        'peso_neto_declarado': null,
        'peso_diferencia': null,
        'porcentaje_desviacion': null,
        'densidad': null,
        'estado_boleto': 'PENDIENTE',
        'numero_boleto': 'TA-00000001',
        'sincronizado': true,
        'created_at': '2026-09-08T08:00:00.000Z',
        'updated_at': '2026-09-08T08:00:00.000Z',
      },
    );
  }
}

const _boleto = 'b1b2b3b4-b5b6-4b7b-8b9b-babbbcbdbebf';

/// Repo de conteo sin BD: cuenta los push y no devuelve pendientes.
class _CountingRepo implements IWeighingRepository {
  int pushes = 0;

  @override
  Future<Weighing> createWeighing(
    Weighing weighing, {
    bool online = true,
    Map<String, dynamic>? adicionales,
  }) async =>
      weighing;

  @override
  Future<Weighing> closeWeighing(String boleto, Map<String, dynamic> closeData) async =>
      throw UnimplementedError();

  @override
  Future<Weighing?> getWeighingByBoleto(String boleto) async => null;

  @override
  Future<List<Weighing>> listWeighings({
    int skip = 0,
    int limit = 100,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? vehicleId,
    String? estado,
  }) async =>
      [];

  @override
  Future<Weighing> updateWeighing(String boleto, Map<String, dynamic> data) async =>
      throw UnimplementedError();

  @override
  Future<Weighing> anularWeighing(String boleto, String motivo) async =>
      throw UnimplementedError();

  @override
  Future<List<Weighing>> listPendientes() async => [];

  @override
  Future<Response> getTicketPdf(String boleto) async =>
      Response(requestOptions: RequestOptions(path: ''));

  @override
  Future<int> countWeighingsToday() async => 0;

  @override
  Future<List<Weighing>> getPendingWeighings() async => [
        Weighing(
          boleto: _boleto,
          idVehiculo: 'ABC123',
          fechaHoraEntrada: DateTime.now(),
          pesoEntradaVehiculo: 50000,
          pesoSalidaVehiculo: 45000,
          pesoNeto: 5000,
          numeroBoleto: 'TA-00000001',
          estadoBoleto: 'PENDIENTE',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

  @override
  Future<int> markAsSynced(String boleto) async => 1;

  @override
  Future<void> pushWeighing(Weighing weighing) async {
    pushes++;
  }

  @override
  Future<int> incrementSyncAttempt(String boleto) async => 1;

  @override
  Future<List<Weighing>> getFailedWeighings() async => [];
}

Future<void> _seedPendiente(DatabaseHelper dbHelper) async {
  final db = await dbHelper.database;
  await db.insert('weighing_local', {
    'boleto': _boleto,
    'id_vehiculo': 'ABC123',
    'remolque': 0,
    'fecha_hora_entrada': '2026-09-08T08:00:00.000',
    'peso_entrada_vehiculo': 50000.0,
    'estado_boleto': 'PENDIENTE',
    'sincronizado': 0,
    'pendiente': 1,
    'intentos_sync': 0,
    'fallido': 0,
    'created_at': '2026-09-08T08:00:00.000',
    'updated_at': '2026-09-08T08:00:00.000',
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    ConnectivityPlatform.instance = _WifiConnectivityPlatform();
    final db = await DatabaseHelper().database;
    await db.delete('weighing_local');
  });

  group('maxSyncRetries', () {
    test('tras agotar los reintentos el pesaje se marca como fallido', () async {
      final dbHelper = DatabaseHelper();
      await _seedPendiente(dbHelper);
      final repo = WeighingRepository(
        apiClient: _FailingApiClient(),
        dbHelper: dbHelper,
        connectivity: Connectivity(),
      );
      final sync = SyncWeighingsUseCase(repo);

      expect(await repo.getPendingWeighings(), hasLength(1));

      for (var i = 0; i < 3; i++) {
        await sync.execute();
      }

      expect(await repo.getPendingWeighings(), isEmpty,
          reason: 'con intentos >= maxSyncRetries no debe reintentarse');
      final fallidos = await repo.getFailedWeighings();
      expect(fallidos, hasLength(1));
      expect(fallidos.first.boleto, _boleto);
      expect(fallidos.first.isPendingSync, isTrue);
    });

    test('push exitoso sincroniza y limpia reintentos', () async {
      final dbHelper = DatabaseHelper();
      await _seedPendiente(dbHelper);
      final repo = WeighingRepository(
        apiClient: _OkApiClient(),
        dbHelper: dbHelper,
        connectivity: Connectivity(),
      );

      final sync = SyncWeighingsUseCase(repo);
      final creados = await sync.execute();

      expect(creados, 1);
      expect(await repo.getPendingWeighings(), isEmpty);
      expect(await repo.getFailedWeighings(), isEmpty);
    });
  });

  group('getPendingWeighings', () {
    test('excluye pendientes con intentos agotados', () async {
      final dbHelper = DatabaseHelper();
      final db = await dbHelper.database;
      // dos filas pendientes: una sin intentos y otra con intentos agotados
      await db.insert('weighing_local', {
        'boleto': _boleto,
        'id_vehiculo': 'AAA111',
        'remolque': 0,
        'fecha_hora_entrada': '2026-09-08T08:00:00.000',
        'peso_entrada_vehiculo': 40000.0,
        'estado_boleto': 'PENDIENTE',
        'sincronizado': 0,
        'pendiente': 1,
        'intentos_sync': 0,
        'fallido': 0,
        'created_at': '2026-09-08T08:00:00.000',
        'updated_at': '2026-09-08T08:00:00.000',
      });
      await db.insert('weighing_local', {
        'boleto': 'c1b2b3b4-b5b6-4b7b-8b9b-babbbcbdbebf',
        'id_vehiculo': 'BBB222',
        'remolque': 0,
        'fecha_hora_entrada': '2026-09-08T09:00:00.000',
        'peso_entrada_vehiculo': 30000.0,
        'estado_boleto': 'PENDIENTE',
        'sincronizado': 0,
        'pendiente': 1,
        'intentos_sync': 5,
        'fallido': 0,
        'created_at': '2026-09-08T09:00:00.000',
        'updated_at': '2026-09-08T09:00:00.000',
      });

      final repo = WeighingRepository(
        apiClient: _FailingApiClient(),
        dbHelper: dbHelper,
        connectivity: Connectivity(),
      );
      final pendientes = await repo.getPendingWeighings();
      expect(pendientes, hasLength(1));
      expect(pendientes.first.idVehiculo, 'AAA111');
    });
  });

  group('SyncBloc · timer periódico', () {
    test('dispara push automático según el intervalo configurado', () async {
      final repo = _CountingRepo();
      final bloc = SyncBloc(
        syncUseCase: SyncWeighingsUseCase(repo),
        pendingCountUseCase: GetPendingWeighingsCountUseCase(repo),
        failedCountUseCase: GetFailedWeighingsCountUseCase(repo),
        autoSyncInterval: const Duration(milliseconds: 30),
      );

      await Future<void>.delayed(const Duration(milliseconds: 100));
      await bloc.close();

      expect(repo.pushes, greaterThanOrEqualTo(2),
          reason: 'el timer periódico debe disparar al menos 2 push en ~100ms');
    });
  });
}