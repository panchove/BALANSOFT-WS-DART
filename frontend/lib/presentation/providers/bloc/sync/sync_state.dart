part of 'sync_bloc.dart';

abstract class SyncState extends Equatable {
  const SyncState();
  @override
  List<Object?> get props => [];
}

class SyncInitial extends SyncState {}
class SyncInProgress extends SyncState {}

class SyncComplete extends SyncState {
  final int syncedCount;
  final int failedCount;
  const SyncComplete({required this.syncedCount, required this.failedCount});
  @override
  List<Object?> get props => [syncedCount, failedCount];
}

class SyncError extends SyncState {
  final String message;
  const SyncError(this.message);
  @override
  List<Object?> get props => [message];
}

class SyncStatusLoaded extends SyncState {
  final int pendingCount;
  final DateTime? lastSyncTime;
  const SyncStatusLoaded({required this.pendingCount, this.lastSyncTime});
  @override
  List<Object?> get props => [pendingCount, lastSyncTime];
}

class HealthOnline extends SyncState {
  final DateTime checkedAt;
  const HealthOnline(this.checkedAt);
  @override
  List<Object?> get props => [checkedAt];
}

class HealthOffline extends SyncState {
  final DateTime checkedAt;
  const HealthOffline(this.checkedAt);
  @override
  List<Object?> get props => [checkedAt];
}
