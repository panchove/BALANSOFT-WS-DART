// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 17025 / OIML R 76-1 / ISO/IEC 25010
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../domain/entities/weighing.dart';
import '../../../../domain/usecases/weighing_usecases.dart';

part 'weighing_event.dart';
part 'weighing_state.dart';

/// BLoC central para la gestión del ciclo de vida metrológico de pesajes industriales.
///
/// Coordina la captura de peso de entrada, salida, anulación, consultas y sincronización
/// offline según las normas ISO/IEC 17025 y OIML R 76-1.
class WeighingBloc extends Bloc<WeighingEvent, WeighingState> {
  final CreateWeighingUseCase _createUseCase;
  final CloseWeighingUseCase _closeUseCase;
  final AnularWeighingUseCase _anularUseCase;
  final GetWeighingUseCase _getUseCase;
  final ListWeighingsUseCase _listUseCase;
  final SyncWeighingsUseCase _syncUseCase;
  final GetFailedWeighingsCountUseCase? _failedCountUseCase;

  /// Crea el BLoC inyectando todos los casos de uso requeridos para la operación metrológica.
  WeighingBloc({
    required CreateWeighingUseCase createUseCase,
    required CloseWeighingUseCase closeUseCase,
    required AnularWeighingUseCase anularUseCase,
    required GetWeighingUseCase getUseCase,
    required ListWeighingsUseCase listUseCase,
    required SyncWeighingsUseCase syncUseCase,
    GetFailedWeighingsCountUseCase? failedCountUseCase,
  })  : _createUseCase = createUseCase,
        _closeUseCase = closeUseCase,
        _anularUseCase = anularUseCase,
        _getUseCase = getUseCase,
        _listUseCase = listUseCase,
        _syncUseCase = syncUseCase,
        _failedCountUseCase = failedCountUseCase,
        super(WeighingInitial()) {
    on<CreateWeighingEvent>(_onCreate);
    on<CloseWeighingEvent>(_onClose);
    on<AnularWeighingEvent>(_onAnular);
    on<ListWeighingsEvent>(_onList);
    on<GetWeighingEvent>(_onGet);
    on<SyncWeighingsEvent>(_onSync);
  }

  /// Maneja el registro inicial de una pesada (`CreateWeighingEvent`).
  Future<void> _onCreate(
      CreateWeighingEvent event, Emitter<WeighingState> emit) async {
    emit(WeighingLoading());
    try {
      final weighing =
          await _createUseCase.execute(event.weighing, event.adicionales);
      emit(WeighingCreated(weighing));
    } catch (e) {
      emit(WeighingError(e.toString()));
    }
  }

  /// Maneja el cierre definitivo de un boleto capturando pesada de salida (`CloseWeighingEvent`).
  Future<void> _onClose(
      CloseWeighingEvent event, Emitter<WeighingState> emit) async {
    emit(WeighingLoading());
    try {
      final weighing =
          await _closeUseCase.execute(event.boleto, event.closeData);
      emit(WeighingClosed(weighing));
    } catch (e) {
      emit(WeighingError(e.toString()));
    }
  }

  /// Maneja la anulación justificada de un boleto (`AnularWeighingEvent`).
  Future<void> _onAnular(
      AnularWeighingEvent event, Emitter<WeighingState> emit) async {
    emit(WeighingLoading());
    try {
      final weighing =
          await _anularUseCase.execute(event.boleto, event.motivo);
      emit(WeighingAnulado(weighing));
    } catch (e) {
      emit(WeighingError(e.toString()));
    }
  }

  /// Maneja la consulta paginada y filtrada de boletos (`ListWeighingsEvent`).
  Future<void> _onList(
      ListWeighingsEvent event, Emitter<WeighingState> emit) async {
    emit(WeighingLoading());
    try {
      final weighings = await _listUseCase.execute(
        dateFrom: event.dateFrom,
        dateTo: event.dateTo,
        vehicleId: event.vehicleId,
        estado: event.estado,
      );
      emit(WeighingListLoaded(weighings));
    } catch (e) {
      emit(WeighingError(e.toString()));
    }
  }

  /// Maneja la consulta del detalle de un boleto específico (`GetWeighingEvent`).
  Future<void> _onGet(
      GetWeighingEvent event, Emitter<WeighingState> emit) async {
    emit(WeighingLoading());
    try {
      final weighing = await _getUseCase.execute(event.boleto);
      if (weighing != null) {
        emit(WeighingDetail(weighing));
      } else {
        emit(const WeighingError('Pesaje no encontrado'));
      }
    } catch (e) {
      emit(WeighingError(e.toString()));
    }
  }

  /// Maneja la sincronización hacia el servidor de boletos pendientes (`SyncWeighingsEvent`).
  Future<void> _onSync(
      SyncWeighingsEvent event, Emitter<WeighingState> emit) async {
    emit(WeighingSyncing());
    try {
      final count = await _syncUseCase.execute();
      final failed = await _failedCountUseCase?.execute() ?? 0;
      emit(WeighingSyncComplete(count, failedCount: failed));
      // Tras sincronizar se recarga el listado: si el bloque queda en
      // WeighingSyncComplete, las pantallas que solo renderizan con
      // WeighingListLoaded (Dashboard, listado recién abierto) se quedarían
      // en el spinner infinito hasta que se reingresara al módulo.
      add(const ListWeighingsEvent());
    } catch (e) {
      emit(WeighingError('Error en sincronización: $e'));
    }
  }
}
