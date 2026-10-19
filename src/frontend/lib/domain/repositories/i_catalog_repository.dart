import '../entities/catalogs.dart';

abstract class ICatalogRepository {
  Future<CatalogData> syncCatalogs();
  Future<CatalogData?> getCachedCatalogs();
}