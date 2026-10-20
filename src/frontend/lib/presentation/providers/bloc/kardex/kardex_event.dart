// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 17025 / OIML R 76-1 / ISO/IEC 25010
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

part of 'kardex_bloc.dart';

/// Clase base abstracta de eventos para el BLoC de Kardex.
abstract class KardexEvent extends Equatable {
  const KardexEvent();
  @override
  List<Object?> get props => [];
}

/// Evento para disparar la carga de movimientos de Kardex entre dos fechas.
class LoadKardexEvent extends KardexEvent {
  final DateTime desde;
  final DateTime hasta;
  final String? idProducto;
  final String? idAlmacen;

  /// Crea el evento con el intervalo temporal y filtros opcionales de producto y almacén.
  const LoadKardexEvent({
    required this.desde,
    required this.hasta,
    this.idProducto,
    this.idAlmacen,
  });

  @override
  List<Object?> get props => [desde, hasta, idProducto, idAlmacen];
}