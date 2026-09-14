import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../domain/usecases/weighing_usecases.dart';

part 'sync_event.dart';
part 'sync_state.dart';

/// Sincronización automática: dispara push cada [AppConstants.syncIntervalMinutes]
/// minutos, expone el conteo de pendientes y fallidos, y verifica la salud del
/// backend cada [AppConstants.healthCheckSeconds] segundos.
class SyncBloc extends Bloc<SyncEvent, SyncState> {
  final SyncWeighingsUseCase _syncUseCase;
  final GetPendingWeighingsCountUseCase _pendingCountUseCase;
  final GetFailedWeighingsCountUseCase? _failedCountUseCase;
  final Future<bool> Function()? _healthCheck;
  final Duration _autoSyncInterval;

  Timer? _timer;
  Timer? _healthTimer;

  SyncBloc({
    required SyncWeighingsUseCase syncUseCase,
    required GetPendingWeighingsCountUseCase pendingCountUseCase,
    GetFailedWeighingsCountUseCase? failedCountUseCase,
    Future<bool> Function()? healthCheck,
    Duration? autoSyncInterval,
  })  : _syncUseCase = syncUseCase,
        _pendingCountUseCase = pendingCountUseCase,
        _failedCountUseCase = failedCountUseCase,
        _healthCheck = healthCheck,
        _autoSyncInterval =
            autoSyncInterval ?? const Duration(minutes: AppConstants.syncIntervalMinutes),
        super(SyncInitial()) {
    on<SyncWeighingsEvent>(_onSync);
    on<SyncStatusEvent>(_onStatus);
    on<HealthCheckEvent>(_onHealth);
    _startTimer();
    _startHealthTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(_autoSyncInterval, (_) => add(SyncWeighingsEvent()));
  }

  void _startHealthTimer() {
    if (_healthCheck == null) return;
    add(HealthCheckEvent());
    _healthTimer = Timer.periodic(
      const Duration(seconds: AppConstants.healthCheckSeconds),
      (_) => add(HealthCheckEvent()),
    );
  }

  Future<void> _onSync(
      SyncWeighingsEvent event, Emitter<SyncState> emit) async {
    emit(SyncInProgress());
    try {
      final count = await _syncUseCase.execute();
      final failed = await _failedCountUseCase?.execute() ?? 0;
      emit(SyncComplete(syncedCount: count, failedCount: failed));
    } catch (e) {
      emit(SyncError(e.toString()));
    }
  }

  Future<void> _onStatus(
      SyncStatusEvent event, Emitter<SyncState> emit) async {
    try {
      final count = await _pendingCountUseCase.execute();
      emit(SyncStatusLoaded(pendingCount: count));
    } catch (e) {
      emit(SyncError(e.toString()));
    }
  }

  Future<void> _onHealth(
      HealthCheckEvent event, Emitter<SyncState> emit) async {
    final ok = await _healthCheck?.call() ?? true;
    emit(ok ? HealthOnline(DateTime.now()) : HealthOffline(DateTime.now()));
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    _healthTimer?.cancel();
    return super.close();
  }
}