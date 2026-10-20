// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 25010 / ISO/IEC 27001
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

part of 'catalog_bloc.dart';

abstract class CatalogEvent extends Equatable {
  const CatalogEvent();
  @override
  List<Object?> get props => [];
}

class FetchCatalogsEvent extends CatalogEvent {
  const FetchCatalogsEvent();
}