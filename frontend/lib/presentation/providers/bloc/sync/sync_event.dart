part of 'sync_bloc.dart';

abstract class SyncEvent extends Equatable {
  const SyncEvent();
  @override
  List<Object?> get props => [];
}

class SyncWeighingsEvent extends SyncEvent {}

class SyncStatusEvent extends SyncEvent {}

class HealthCheckEvent extends SyncEvent {}
