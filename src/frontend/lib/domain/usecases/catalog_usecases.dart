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

/// Caso de uso para sincronizar catálogos maestros desde el servidor/WServer.
class SyncCatalogsUseCase {
  final ICatalogRepository _repo;
  SyncCatalogsUseCase(this._repo);

  /// Ejecuta la sincronización completa de catálogos.
  ///
  /// Poscondiciones:
  /// - Retorna [CatalogData] actualizado y refresca la caché local.
  Future<CatalogData> execute() => _repo.syncCatalogs();
}

/// Caso de uso para obtener los catálogos almacenados en la caché local para operación offline.
class GetCachedCatalogsUseCase {
  final ICatalogRepository _repo;
  GetCachedCatalogsUseCase(this._repo);

  /// Ejecuta la lectura de catálogos desde almacenamiento persistente.
  ///
  /// Poscondiciones:
  /// - Retorna [CatalogData] si existe caché disponible, o `null`.
  Future<CatalogData?> execute() => _repo.getCachedCatalogs();
}