// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 17025 / OIML R 76-1 / ISO/IEC 25010
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

part of 'kardex_bloc.dart';

/// Clase base abstracta de estados para el BLoC de Kardex.
abstract class KardexState extends Equatable {
  const KardexState();
  @override
  List<Object?> get props => [];
}

/// Estado inicial previo a la primera consulta de movimientos.
class KardexInitial extends KardexState {}

/// Estado indicativo de petición en progreso hacia el backend.
class KardexLoading extends KardexState {}

/// Estado de éxito con la información de balance y movimientos cargada.
class KardexLoaded extends KardexState {
  final KardexDetalle detalle;

  /// Crea el estado conteniendo el [detalle] de Kardex consultado.
  const KardexLoaded(this.detalle);

  @override
  List<Object?> get props => [detalle];
}

/// Estado de fallo al consultar movimientos o comunicarse con el servidor.
class KardexError extends KardexState {
  final String message;

  /// Crea el estado conteniendo el mensaje o código de error descriptivo.
  const KardexError(this.message);

  @override
  List<Object?> get props => [message];
}