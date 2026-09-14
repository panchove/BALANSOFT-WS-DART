part of 'kardex_bloc.dart';

abstract class KardexEvent extends Equatable {
  const KardexEvent();
  @override
  List<Object?> get props => [];
}

class LoadKardexEvent extends KardexEvent {
  final DateTime desde;
  final DateTime hasta;
  final String? idProducto;
  final String? idAlmacen;

  const LoadKardexEvent({
    required this.desde,
    required this.hasta,
    this.idProducto,
    this.idAlmacen,
  });

  @override
  List<Object?> get props => [desde, hasta, idProducto, idAlmacen];
}