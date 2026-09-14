part of 'weighing_bloc.dart';

abstract class WeighingState extends Equatable {
  const WeighingState();
  @override
  List<Object?> get props => [];
}

class WeighingInitial extends WeighingState {}
class WeighingLoading extends WeighingState {}

class WeighingCreated extends WeighingState {
  final Weighing weighing;
  const WeighingCreated(this.weighing);
  @override
  List<Object?> get props => [weighing];
}

class WeighingClosed extends WeighingState {
  final Weighing weighing;
  const WeighingClosed(this.weighing);
  @override
  List<Object?> get props => [weighing];
}

class WeighingAnulado extends WeighingState {
  final Weighing weighing;
  const WeighingAnulado(this.weighing);
  @override
  List<Object?> get props => [weighing];
}

class WeighingListLoaded extends WeighingState {
  final List<Weighing> weighings;
  const WeighingListLoaded(this.weighings);
  @override
  List<Object?> get props => [weighings];
}

class WeighingDetail extends WeighingState {
  final Weighing weighing;
  const WeighingDetail(this.weighing);
  @override
  List<Object?> get props => [weighing];
}

class WeighingSyncing extends WeighingState {}

class WeighingSyncComplete extends WeighingState {
  final int syncedCount;
  final int failedCount;
  const WeighingSyncComplete(this.syncedCount, {this.failedCount = 0});
  @override
  List<Object?> get props => [syncedCount, failedCount];
}

class WeighingError extends WeighingState {
  final String message;
  const WeighingError(this.message);
  @override
  List<Object?> get props => [message];
}
