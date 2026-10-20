// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 25010 / ISO/IEC 27001
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

import '../entities/catalogs.dart';
import '../repositories/i_catalog_repository.dart';

class SyncCatalogsUseCase {
  final ICatalogRepository _repo;
  SyncCatalogsUseCase(this._repo);

  Future<CatalogData> execute() => _repo.syncCatalogs();
}

class GetCachedCatalogsUseCase {
  final ICatalogRepository _repo;
  GetCachedCatalogsUseCase(this._repo);

  Future<CatalogData?> execute() => _repo.getCachedCatalogs();
}