// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 25010 / ISO/IEC 27001
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

import '../entities/catalogs.dart';

/// Contrato del repositorio para la sincronización y consulta de catálogos maestros.
///
/// Soporta la arquitectura offline-first asegurando la disponibilidad de datos
/// operativos en la estación de pesaje local.
abstract class ICatalogRepository {
  /// Sincroniza los catálogos maestros desde el servidor central o backend local.
  ///
  /// Poscondiciones:
  /// - Retorna una entidad [CatalogData] con clientes, productos, conductores, vehículos y series.
  /// - Actualiza la caché local de catálogos para permitir operación offline.
  Future<CatalogData> syncCatalogs();

  /// Recupera los catálogos maestros almacenados previamente en la caché local.
  ///
  /// Poscondiciones:
  /// - Retorna [CatalogData] si existen catálogos en caché, o `null` si no se han descargado.
  Future<CatalogData?> getCachedCatalogs();
}