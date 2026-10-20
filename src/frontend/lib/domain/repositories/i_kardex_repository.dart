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

/// Contrato del repositorio de Kardex y balance de masa.
///
/// Gestiona movimientos de inventario de pesaje según ISO/IEC 17025 y OIML R 76-1:
/// - Código 10: Ingreso / Recepción (aumento de inventario).
/// - Código 60: Despacho / Salida (reducción de inventario).
abstract class IKardexRepository {
  /// Consulta el balance de movimientos de inventario entre dos fechas.
  ///
  /// Precondiciones:
  /// - [desde] debe ser anterior o igual a [hasta].
  ///
  /// Poscondiciones:
  /// - Retorna una entidad [KardexDetalle] con los movimientos, stock inicial y final.
  Future<KardexDetalle> detalle({
    required DateTime desde,
    required DateTime hasta,
    String? idProducto,
    String? idAlmacen,
  });

  /// Genera y descarga el reporte de Kardex en formato Microsoft Excel (.xlsx).
  ///
  /// Precondiciones:
  /// - [desde] <= [hasta].
  ///
  /// Poscondiciones:
  /// - Retorna un [Response] HTTP con el stream binario del archivo generado.
  Future<Response> exportExcel({
    required DateTime desde,
    required DateTime hasta,
    String? idProducto,
    String? idAlmacen,
  });

  /// Genera y descarga el reporte de Kardex en formato PDF para archivo metrológico.
  ///
  /// Precondiciones:
  /// - [desde] <= [hasta].
  /// - [orientacion] debe ser `'V'` (Vertical/Portrait) o `'H'` (Horizontal/Landscape).
  ///
  /// Poscondiciones:
  /// - Retorna un [Response] HTTP con el stream del PDF.
  Future<Response> exportPdf({
    required DateTime desde,
    required DateTime hasta,
    String? idProducto,
    String? idAlmacen,
    String orientacion = 'V',
  });
}