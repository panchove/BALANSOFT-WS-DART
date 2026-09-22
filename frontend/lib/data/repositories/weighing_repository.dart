import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/entities/weighing.dart';
import '../../domain/repositories/i_weighing_repository.dart';
import '../datasources/remote/api_client.dart';
import '../datasources/local/database_helper.dart';
import '../models/weighing_model.dart';

class WeighingRepository implements IWeighingRepository {
  final ApiClient _apiClient;
  final DatabaseHelper _dbHelper;
  final Connectivity _connectivity;

  WeighingRepository({
    required ApiClient apiClient,
    required DatabaseHelper dbHelper,
    required Connectivity connectivity,
  })  : _apiClient = apiClient,
        _dbHelper = dbHelper,
        _connectivity = connectivity;

  Future<bool> get _isConnected async {
    final result = await _connectivity.checkConnectivity();
    return result != ConnectivityResult.none;
  }

  String _extractDioError(DioException e, String fallback) {
    if (e.response != null) {
      final data = e.response?.data;
      if (data is Map && data['detail'] != null) {
        return data['detail'].toString();
      } else if (data is String && data.isNotEmpty) {
        return data;
      }
      return 'Error en el servidor (${e.response?.statusCode})';
    }
    return fallback;
  }

  @override
  Future<Weighing> createWeighing(
    Weighing weighing, {
    bool online = true,
    Map<String, dynamic>? adicionales,
  }) async {
    final payload = <String, dynamic>{...weighing.toJson(), ...?adicionales};
    if (online && await _isConnected) {
      try {
        final response = await _apiClient.createWeighing(payload);
        final created = Weighing.fromJson(response.data);
        await _saveLocal(created, synced: true);
        return created;
      } on DioException catch (e) {
        if (e.response != null) {
          throw Exception(_extractDioError(e, 'Error al registrar pesaje'));
        }
        await _saveLocal(weighing, synced: false, pending: true);
        return weighing;
      } catch (e) {
        if (e is Exception) rethrow;
        throw Exception('Error al registrar pesaje: $e');
      }
    } else {
      await _saveLocal(weighing, synced: false, pending: true);
      return weighing;
    }
  }

  @override
  Future<Weighing> closeWeighing(String boleto, Map<String, dynamic> closeData) async {
    if (await _isConnected) {
      try {
        final response = await _apiClient.closeWeighing(boleto, closeData);
        final closed = Weighing.fromJson(response.data);
        await _saveLocal(closed, synced: true);
        return closed;
      } on DioException catch (e) {
        if (e.response != null) {
          throw Exception(_extractDioError(e, 'Error al cerrar pesaje'));
        }
      } catch (e) {
        if (e is Exception) rethrow;
      }
    }
    final local = await getWeighingByBoleto(boleto);
    if (local == null) throw Exception('Pesaje no encontrado');
    final updated = local.copyWith(
      fechaHoraSalida: closeData['fecha_hora_salida'] != null
          ? DateTime.parse(closeData['fecha_hora_salida'])
          : DateTime.now(),
      pesoSalidaVehiculo: closeData['peso_salida_vehiculo'],
      pesoSalidaRemolque: closeData['peso_salida_remolque'],
      densidad: closeData['densidad'],
      unidades: closeData['unidades'],
      costoFlete: closeData['costo_flete'],
      observaciones: closeData['observaciones'],
      estadoBoleto: 'CERRADO',
    );
    await _saveLocal(updated, synced: false, pending: true);
    return updated;
  }

  @override
  Future<Weighing?> getWeighingByBoleto(String boleto) async {
    if (await _isConnected) {
      try {
        final response = await _apiClient.getWeighingByBoleto(boleto);
        return Weighing.fromJson(response.data);
      } catch (_) {
        return _getLocal(boleto);
      }
    }
    return _getLocal(boleto);
  }

  @override
  Future<List<Weighing>> listWeighings({
    int skip = 0,
    int limit = 100,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? vehicleId,
    String? estado,
  }) async {
    if (await _isConnected) {
      try {
        final params = <String, dynamic>{
          'skip': skip,
          'limit': limit,
        };
        if (dateFrom != null) params['date_from'] = dateFrom.toIso8601String();
        if (dateTo != null) params['date_to'] = dateTo.toIso8601String();
        if (vehicleId != null) params['vehicle_id'] = vehicleId;
        if (estado != null) params['estado'] = estado;

        final response = await _apiClient.listWeighings(params: params);
        final list = (response.data as List)
            .map((j) => Weighing.fromJson(j))
            .toList();
        for (final w in list) {
          await _saveLocal(w, synced: true);
        }
        return await _mergeLocalPendientes(list);
      } catch (_) {
        return _listLocal();
      }
    }
    return _listLocal();
  }

  @override
  Future<Weighing> updateWeighing(String boleto, Map<String, dynamic> data) async {
    if (await _isConnected) {
      final response = await _apiClient.updateWeighing(boleto, data);
      final updated = Weighing.fromJson(response.data);
      await _saveLocal(updated, synced: true);
      return updated;
    } else {
      final local = await getWeighingByBoleto(boleto);
      if (local == null) throw Exception('Pesaje no encontrado');
      final updated = local.copyWith(
        documento: data['documento'],
        flete: data['flete'],
        costoFlete: data['costo_flete'],
        observaciones: data['observaciones'],
      );
      await _saveLocal(updated, synced: false, pending: true);
      return updated;
    }
  }

  @override
  Future<Weighing> anularWeighing(String boleto, String motivo) async {
    if (await _isConnected) {
      try {
        final response = await _apiClient.anularWeighing(boleto, motivo);
        final anulado = Weighing.fromJson(response.data);
        await _saveLocal(anulado, synced: true);
        return anulado;
      } on DioException catch (e) {
        if (e.response != null) {
          throw Exception(_extractDioError(e, 'Error al anular pesaje'));
        }
      } catch (e) {
        if (e is Exception) rethrow;
      }
    }
    final local = await getWeighingByBoleto(boleto);
    if (local == null) throw Exception('Pesaje no encontrado');
    final updated = local.copyWith(
      estadoBoleto: 'ANULADO',
      motivoAnulacion: motivo,
      observaciones:
          '${local.observaciones ?? ''}\n[ANULADO] Motivo: $motivo'.trim(),
    );
    await _saveLocal(updated, synced: false, pending: true);
    return updated;
  }

    @override
  Future<Response> getTicketPdf(String boleto) async {
    return _apiClient.getTicketPdf(boleto);
  }

  @override
  Future<Response> getTicketTxt(String boleto) async {
    return _apiClient.getTicketTxt(boleto);
  }

  @override
  Future<List<Weighing>> listPendientes() async {
    if (await _isConnected) {
      try {
        final response = await _apiClient.listPendientes();
        final list = (response.data as List)
            .map((j) => Weighing.fromJson(j))
            .toList();
        for (final w in list) {
          await _saveLocal(w, synced: true);
        }
        return list;
      } catch (_) {
        return _listLocal()
            .then((l) => l.where((w) => w.isOpen).toList());
      }
    }
    return _listLocal().then((l) => l.where((w) => w.isOpen).toList());
  }

  @override
  Future<int> countWeighingsToday() async {
    final db = await _dbHelper.database;
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day).toIso8601String();
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM weighing_local WHERE fecha_hora_entrada >= ?',
      [start],
    );
    return result.first['cnt'] as int? ?? 0;
  }

  @override
  Future<List<Weighing>> getPendingWeighings() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'weighing_local',
      where: 'pendiente = 1 AND sincronizado = 0 AND fallido = 0 '
          'AND intentos_sync < ${AppConstants.maxSyncRetries}',
    );
    return result.map((row) => WeighingModel.fromLocalDb(row)).toList();
  }

  @override
  Future<void> pushWeighing(Weighing weighing) async {
    if (!await _isConnected) {
      throw Exception('Sin conexión');
    }
    final payload = <String, dynamic>{...weighing.toJson()};
    final response = await _apiClient.createWeighing(payload);
    final created = Weighing.fromJson(response.data);
    await _saveLocal(created, synced: true);
  }

  @override
  Future<int> incrementSyncAttempt(String boleto) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery(
      'SELECT intentos_sync FROM weighing_local WHERE boleto = ?',
      [boleto],
    );
    if (rows.isEmpty) return 0;
    final actual = (rows.first['intentos_sync'] as int?) ?? 0;
    final nuevo = actual + 1;
    final fallido = nuevo >= AppConstants.maxSyncRetries ? 1 : 0;
    return db.update(
      'weighing_local',
      {'intentos_sync': nuevo, 'fallido': fallido},
      where: 'boleto = ?',
      whereArgs: [boleto],
    );
  }

  @override
  Future<List<Weighing>> getFailedWeighings() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'weighing_local',
      where: 'fallido = 1 AND sincronizado = 0',
      orderBy: 'fecha_hora_entrada DESC',
    );
    return result.map((row) => WeighingModel.fromLocalDb(row)).toList();
  }

  @override
  Future<int> markAsSynced(String boleto) async {
    final db = await _dbHelper.database;
    return await db.update(
      'weighing_local',
      {'sincronizado': 1, 'pendiente': 0, 'intentos_sync': 0, 'fallido': 0},
      where: 'boleto = ?',
      whereArgs: [boleto],
    );
  }

  Future<void> _saveLocal(
    Weighing weighing, {
    required bool synced,
    bool pending = false,
  }) async {
    final db = await _dbHelper.database;
    final model = WeighingModel.fromEntity(weighing);
    final data = model.toLocalDb();
    data['sincronizado'] = synced ? 1 : 0;
    data['pendiente'] = pending ? 1 : 0;
    await db.insert('weighing_local', data,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Weighing?> _getLocal(String boleto) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'weighing_local',
      where: 'boleto = ? OR numero_boleto = ?',
      whereArgs: [boleto, boleto],
    );
    if (result.isEmpty) return null;
    return WeighingModel.fromLocalDb(result.first);
  }

  Future<List<Weighing>> _listLocal() async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'weighing_local',
      orderBy: 'fecha_hora_entrada DESC',
    );
    return result.map((row) => WeighingModel.fromLocalDb(row)).toList();
  }

  /// Fusiona los registros locales pendientes/fallidos con la lista del
  /// backend: si un pesaje quedó local (403, sin conexión) todavía no figura
  /// en el servidor, debe seguir apareciendo en la lista.
  Future<List<Weighing>> _mergeLocalPendientes(List<Weighing> remotos) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'weighing_local',
      where: 'sincronizado = 0',
      orderBy: 'fecha_hora_entrada DESC',
    );
    if (result.isEmpty) return remotos;
    final pendientes = result
        .map((row) => WeighingModel.fromLocalDb(row))
        .where((w) => !remotos.any((r) => r.boleto == w.boleto))
        .toList();
    return [...pendientes, ...remotos];
  }
}
