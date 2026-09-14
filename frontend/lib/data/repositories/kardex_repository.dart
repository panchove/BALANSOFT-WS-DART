import 'package:dio/dio.dart';

import '../../domain/entities/kardex.dart';
import '../../domain/repositories/i_kardex_repository.dart';
import '../datasources/remote/api_client.dart';

class KardexRepository implements IKardexRepository {
  final ApiClient _api;

  KardexRepository({required ApiClient apiClient}) : _api = apiClient;

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

  @override
  Future<Response> exportPdf({
    required DateTime desde,
    required DateTime hasta,
    String? idProducto,
    String? idAlmacen,
  }) =>
      _api.kardexExportPdf(<String, dynamic>{
        'fecha_desde': _fecha(desde),
        'fecha_hasta': _fecha(hasta),
        if (idProducto != null && idProducto.isNotEmpty)
          'id_producto': idProducto,
        if (idAlmacen != null && idAlmacen.isNotEmpty) 'id_almacen': idAlmacen,
      });

  String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}T00:00:00';

  String _fecha(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}