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