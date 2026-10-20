// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 17025 / OIML R 76-1 / ISO/IEC 25010
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

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