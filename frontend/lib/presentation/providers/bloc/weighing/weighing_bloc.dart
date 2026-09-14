import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../domain/entities/weighing.dart';
import '../../../../domain/usecases/weighing_usecases.dart';

part 'weighing_event.dart';
part 'weighing_state.dart';

class WeighingBloc extends Bloc<WeighingEvent, WeighingState> {
  final CreateWeighingUseCase _createUseCase;
  final CloseWeighingUseCase _closeUseCase;
  final AnularWeighingUseCase _anularUseCase;
  final GetWeighingUseCase _getUseCase;
  final ListWeighingsUseCase _listUseCase;
  final SyncWeighingsUseCase _syncUseCase;
  final GetFailedWeighingsCountUseCase? _failedCountUseCase;

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

  Future<void> _onSync(
      SyncWeighingsEvent event, Emitter<WeighingState> emit) async {
    emit(WeighingSyncing());
    try {
      final count = await _syncUseCase.execute();
      final failed = await _failedCountUseCase?.execute() ?? 0;
      emit(WeighingSyncComplete(count, failedCount: failed));
    } catch (e) {
      emit(WeighingError('Error en sincronización: $e'));
    }
  }
}
