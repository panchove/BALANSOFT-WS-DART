// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 17025 / OIML R 76-1 / ISO/IEC 25010
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

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
    String orientacion = 'V',
  });
}