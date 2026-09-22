import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balansoft_ws/domain/entities/weighing.dart';
import 'package:balansoft_ws/domain/repositories/i_weighing_repository.dart';
import 'package:balansoft_ws/domain/usecases/weighing_usecases.dart';
import 'package:balansoft_ws/presentation/providers/bloc/weighing/weighing_bloc.dart';

Weighing _weighing({String estado = 'PENDIENTE'}) => Weighing(
      boleto: 'b1b2b3b4-b5b6-4b7b-8b9b-babbbcbdbebf',
      idVehiculo: 'ABC123',
      fechaHoraEntrada: DateTime.now(),
      pesoEntradaVehiculo: 50000,
      pesoSalidaVehiculo: 45000,
      pesoNeto: 5000,
      numeroBoleto: 'TA-00000001',
      estadoBoleto: estado,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

class _FakeRepo implements IWeighingRepository {
  Object? error;

  @override
  Future<Weighing> createWeighing(
    Weighing weighing, {
    bool online = true,
    Map<String, dynamic>? adicionales,
  }) async {
    if (error != null) throw error!;
    return _weighing();
  }

  @override
  Future<Weighing> closeWeighing(String boleto, Map<String, dynamic> closeData) async {
    if (error != null) throw error!;
    return _weighing(estado: 'CERRADO');
  }

  @override
  Future<Weighing?> getWeighingByBoleto(String boleto) async {
    if (error != null) throw error!;
    return _weighing();
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
    if (error != null) throw error!;
    return [_weighing()];
  }

  @override
  Future<Weighing> updateWeighing(String boleto, Map<String, dynamic> data) async => _weighing();

  @override
  Future<Weighing> anularWeighing(String boleto, String motivo) async {
    if (error != null) throw error!;
    return _weighing(estado: 'ANULADO');
  }

  @override
  Future<List<Weighing>> listPendientes() async => [_weighing()];

  @override
  Future<Response> getTicketPdf(String boleto) async => Response(requestOptions: RequestOptions(path: ''));

  @override
  Future<Response> getTicketTxt(String boleto) async => Response(requestOptions: RequestOptions(path: ''));

  @override
  Future<int> countWeighingsToday() async => 1;

  @override
  Future<List<Weighing>> getPendingWeighings() async {
    if (error != null) throw error!;
    return [_weighing()];
  }

  @override
  Future<int> markAsSynced(String boleto) async => 1;

  @override
  Future<void> pushWeighing(Weighing weighing) async {
    if (error != null) throw error!;
  }

  @override
  Future<int> incrementSyncAttempt(String boleto) async => 1;

  @override
  Future<List<Weighing>> getFailedWeighings() async => [];
}

WeighingBloc _bloc(Object? error) {
  final repo = _FakeRepo()..error = error;
  return WeighingBloc(
    createUseCase: CreateWeighingUseCase(repo),
    closeUseCase: CloseWeighingUseCase(repo),
    anularUseCase: AnularWeighingUseCase(repo),
    listUseCase: ListWeighingsUseCase(repo),
    getUseCase: GetWeighingUseCase(repo),
    syncUseCase: SyncWeighingsUseCase(repo),
  );
}

void main() {
  group('WeighingBloc create', () {
    blocTest<WeighingBloc, WeighingState>(
      'emite Created al crear',
      build: () => _bloc(null),
      act: (b) => b.add(CreateWeighingEvent(_weighing())),
      expect: () => [
        isA<WeighingLoading>(),
        isA<WeighingCreated>(),
      ],
    );

    blocTest<WeighingBloc, WeighingState>(
      'emite Error si falla',
      build: () => _bloc(Exception('boom')),
      act: (b) => b.add(CreateWeighingEvent(_weighing())),
      expect: () => [
        isA<WeighingLoading>(),
        isA<WeighingError>(),
      ],
    );
  });

  group('WeighingBloc close', () {
    blocTest<WeighingBloc, WeighingState>(
      'close emite Closed',
      build: () => _bloc(null),
      act: (b) => b.add(const CloseWeighingEvent('boleto-x', {'peso_salida_vehiculo': 45000})),
      expect: () => [
        isA<WeighingLoading>(),
        isA<WeighingClosed>(),
      ],
    );
  });

  group('WeighingBloc anular', () {
    blocTest<WeighingBloc, WeighingState>(
      'anular emite Anulado',
      build: () => _bloc(null),
      act: (b) => b.add(const AnularWeighingEvent('boleto-x', 'motivo de anulación en prueba')),
      expect: () => [
        isA<WeighingLoading>(),
        isA<WeighingAnulado>(),
      ],
    );
  });

  group('WeighingBloc list', () {
    blocTest<WeighingBloc, WeighingState>(
      'list emite ListLoaded',
      build: () => _bloc(null),
      act: (b) => b.add(const ListWeighingsEvent(estado: 'PENDIENTE')),
      expect: () => [
        isA<WeighingLoading>(),
        isA<WeighingListLoaded>(),
      ],
    );
  });

  group('WeighingBloc sync', () {
    blocTest<WeighingBloc, WeighingState>(
      'sync emite SyncComplete',
      build: () => _bloc(null),
      act: (b) => b.add(SyncWeighingsEvent()),
      expect: () => [
        isA<WeighingSyncing>(),
        isA<WeighingSyncComplete>(),
      ],
    );
  });
}