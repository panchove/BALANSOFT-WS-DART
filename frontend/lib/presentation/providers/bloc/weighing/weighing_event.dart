part of 'weighing_bloc.dart';

abstract class WeighingEvent extends Equatable {
  const WeighingEvent();
  @override
  List<Object?> get props => [];
}

class CreateWeighingEvent extends WeighingEvent {
  final Weighing weighing;
  final Map<String, dynamic>? adicionales;
  const CreateWeighingEvent(this.weighing, {this.adicionales});
  @override
  List<Object?> get props => [weighing, adicionales];
}

class CloseWeighingEvent extends WeighingEvent {
  final String boleto;
  final Map<String, dynamic> closeData;
  const CloseWeighingEvent(this.boleto, this.closeData);
  @override
  List<Object?> get props => [boleto, closeData];
}

class AnularWeighingEvent extends WeighingEvent {
  final String boleto;
  final String motivo;
  const AnularWeighingEvent(this.boleto, this.motivo);
  @override
  List<Object?> get props => [boleto, motivo];
}

class ListWeighingsEvent extends WeighingEvent {
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String? vehicleId;
  final String? estado;
  const ListWeighingsEvent({
    this.dateFrom,
    this.dateTo,
    this.vehicleId,
    this.estado,
  });
  @override
  List<Object?> get props => [dateFrom, dateTo, vehicleId, estado];
}

class GetWeighingEvent extends WeighingEvent {
  final String boleto;
  const GetWeighingEvent(this.boleto);
  @override
  List<Object?> get props => [boleto];
}

class SyncWeighingsEvent extends WeighingEvent {}
