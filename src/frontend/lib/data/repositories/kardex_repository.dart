// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 17025 / OIML R 76-1 / ISO/IEC 25010
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

import 'package:dio/dio.dart';

import '../../domain/entities/kardex.dart';
import '../../domain/repositories/i_kardex_repository.dart';
import '../datasources/remote/api_client.dart';

/// Implementación del repositorio de Kardex contra el backend REST de la estación.
///
/// Gestiona la interacción con los endpoints `/api/v1/kardex` bajo ISO/IEC 17025 y OIML R 76-1.
class KardexRepository implements IKardexRepository {
  final ApiClient _api;

  /// Crea una instancia inyectando el cliente HTTP [apiClient].
  KardexRepository({required ApiClient apiClient}) : _api = apiClient;

  /// Consulta el balance de movimientos de inventario en el rango de fechas indicado.
  @override
  Future<KardexDetalle> detalle({
    required DateTime desde,
    required DateTime hasta,
    String? idProducto,
    String? idAlmacen,
  }) async {
    final response = await _api.kardexDetalle(<String, dynamic>{
      'fecha_desde': _iso(desde),
      'fecha_hasta': _iso(hasta),
      if (idProducto != null && idProducto.isNotEmpty) 'id_producto': idProducto,
      if (idAlmacen != null && idAlmacen.isNotEmpty) 'id_almacen': idAlmacen,
    });
    return KardexDetalle.fromJson(response.data as Map<String, dynamic>);
  }

  /// Descarga el reporte de Kardex en formato Excel (.xlsx).
  @override
  Future<Response> exportExcel({
    required DateTime desde,
    required DateTime hasta,
    String? idProducto,
    String? idAlmacen,
  }) =>
      _api.kardexExportExcel(<String, dynamic>{
        'fecha_desde': _fecha(desde),
        'fecha_hasta': _fecha(hasta),
        if (idProducto != null && idProducto.isNotEmpty)
          'id_producto': idProducto,
        if (idAlmacen != null && idAlmacen.isNotEmpty) 'id_almacen': idAlmacen,
      });

  /// Descarga el reporte de Kardex en formato imprimible PDF.
  @override
  Future<Response> exportPdf({
    required DateTime desde,
    required DateTime hasta,
    String? idProducto,
    String? idAlmacen,
    String orientacion = 'V',
  }) =>
      _api.kardexExportPdf(<String, dynamic>{
        'fecha_desde': _fecha(desde),
        'fecha_hasta': _fecha(hasta),
        if (idProducto != null && idProducto.isNotEmpty)
          'id_producto': idProducto,
        if (idAlmacen != null && idAlmacen.isNotEmpty) 'id_almacen': idAlmacen,
        'orientacion': orientacion,
      });

  String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}T00:00:00';

  String _fecha(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}