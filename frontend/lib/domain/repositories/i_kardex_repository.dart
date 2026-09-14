import 'package:dio/dio.dart';

import '../entities/kardex.dart';

abstract class IKardexRepository {
  Future<KardexDetalle> detalle({
    required DateTime desde,
    required DateTime hasta,
    String? idProducto,
    String? idAlmacen,
  });

  Future<Response> exportExcel({
    required DateTime desde,
    required DateTime hasta,
    String? idProducto,
    String? idAlmacen,
  });

  Future<Response> exportPdf({
    required DateTime desde,
    required DateTime hasta,
    String? idProducto,
    String? idAlmacen,
  });
}