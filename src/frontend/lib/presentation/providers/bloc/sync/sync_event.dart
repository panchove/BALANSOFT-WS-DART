part of 'sync_bloc.dart';

abstract class SyncEvent extends Equatable {
  const SyncEvent();
  @override
  List<Object?> get props => [];
}

class SyncWeighingsEvent extends SyncEvent {}

class SyncStatusEvent extends SyncEvent {}

class HealthCheckEvent extends SyncEvent {}

/// Habilita o deshabilita la sincronización automática por timer.
class SetAutoSyncEnabledEvent extends SyncEvent {
  final bool enabled;
  const SetAutoSyncEnabledEvent(this.enabled);

  @override
  List<Object?> get props => [enabled];
}
