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
import '../repositories/i_kardex_repository.dart';

/// Caso de uso para consultar el balance de masa detallado en Kardex.
class KardexDetalleUseCase {
  final IKardexRepository _repo;
  KardexDetalleUseCase(this._repo);

  /// Ejecuta la consulta del detalle de Kardex.
  ///
  /// Precondiciones:
  /// - [desde] <= [hasta].
  ///
  /// Poscondiciones:
  /// - Retorna [KardexDetalle] con movimientos, saldo inicial y actual.
  Future<KardexDetalle> execute({
    required DateTime desde,
    required DateTime hasta,
    String? idProducto,
    String? idAlmacen,
  }) =>
      _repo.detalle(
        desde: desde,
        hasta: hasta,
        idProducto: idProducto,
        idAlmacen: idAlmacen,
      );
}

/// Caso de uso para exportar el Kardex a formato Microsoft Excel (.xlsx).
class ExportKardexExcelUseCase {
  final IKardexRepository _repo;
  ExportKardexExcelUseCase(this._repo);

  /// Ejecuta la generación y descarga del reporte Excel.
  ///
  /// Precondiciones:
  /// - [desde] <= [hasta].
  ///
  /// Poscondiciones:
  /// - Retorna [Response] con el stream binario de la hoja de cálculo.
  Future<Response> execute({
    required DateTime desde,
    required DateTime hasta,
    String? idProducto,
    String? idAlmacen,
  }) =>
      _repo.exportExcel(
        desde: desde,
        hasta: hasta,
        idProducto: idProducto,
        idAlmacen: idAlmacen,
      );
}

/// Caso de uso para exportar el Kardex a formato imprimible PDF.
class ExportKardexPdfUseCase {
  final IKardexRepository _repo;
  ExportKardexPdfUseCase(this._repo);

  /// Ejecuta la generación y descarga del reporte PDF.
  ///
  /// Precondiciones:
  /// - [desde] <= [hasta].
  /// - [orientacion] debe ser `'V'` (Vertical) o `'H'` (Horizontal).
  ///
  /// Poscondiciones:
  /// - Retorna [Response] con el archivo PDF listo para visualización o archivo metrológico.
  Future<Response> execute({
    required DateTime desde,
    required DateTime hasta,
    String? idProducto,
    String? idAlmacen,
    String orientacion = 'V',
  }) =>
      _repo.exportPdf(
        desde: desde,
        hasta: hasta,
        idProducto: idProducto,
        idAlmacen: idAlmacen,
        orientacion: orientacion,
      );
}