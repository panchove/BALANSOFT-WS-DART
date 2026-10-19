part of 'sync_bloc.dart';

abstract class SyncState extends Equatable {
  final bool isOnline;
  const SyncState({this.isOnline = true});

  @override
  List<Object?> get props => [isOnline];
}

class SyncInitial extends SyncState {
  const SyncInitial({super.isOnline = true});
}

class SyncInProgress extends SyncState {
  const SyncInProgress({super.isOnline = true});
}

class SyncComplete extends SyncState {
  final int syncedCount;
  final int failedCount;

  const SyncComplete({
    required this.syncedCount,
    required this.failedCount,
    super.isOnline = true,
  });

  @override
  List<Object?> get props => [syncedCount, failedCount, isOnline];
}

class SyncError extends SyncState {
  final String message;

  const SyncError(this.message, {super.isOnline = false});

  @override
  List<Object?> get props => [message, isOnline];
}

class SyncStatusLoaded extends SyncState {
  final int pendingCount;
  final DateTime? lastSyncTime;

  const SyncStatusLoaded({
    required this.pendingCount,
    this.lastSyncTime,
    super.isOnline = true,
  });

  @override
  List<Object?> get props => [pendingCount, lastSyncTime, isOnline];
}

class HealthOnline extends SyncState {
  final DateTime checkedAt;

  const HealthOnline(this.checkedAt) : super(isOnline: true);

  @override
  List<Object?> get props => [checkedAt, isOnline];
}

class HealthOffline extends SyncState {
  final DateTime checkedAt;

  const HealthOffline(this.checkedAt) : super(isOnline: false);

  @override
  List<Object?> get props => [checkedAt, isOnline];
}
