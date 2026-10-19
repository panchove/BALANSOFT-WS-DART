part of 'kardex_bloc.dart';

abstract class KardexState extends Equatable {
  const KardexState();
  @override
  List<Object?> get props => [];
}

class KardexInitial extends KardexState {}

class KardexLoading extends KardexState {}

class KardexLoaded extends KardexState {
  final KardexDetalle detalle;
  const KardexLoaded(this.detalle);
  @override
  List<Object?> get props => [detalle];
}

class KardexError extends KardexState {
  final String message;
  const KardexError(this.message);
  @override
  List<Object?> get props => [message];
}