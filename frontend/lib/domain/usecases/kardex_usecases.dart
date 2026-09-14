import 'package:dio/dio.dart';

import '../entities/kardex.dart';
import '../repositories/i_kardex_repository.dart';

class KardexDetalleUseCase {
  final IKardexRepository _repo;
  KardexDetalleUseCase(this._repo);

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

class ExportKardexExcelUseCase {
  final IKardexRepository _repo;
  ExportKardexExcelUseCase(this._repo);

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

class ExportKardexPdfUseCase {
  final IKardexRepository _repo;
  ExportKardexPdfUseCase(this._repo);

  Future<Response> execute({
    required DateTime desde,
    required DateTime hasta,
    String? idProducto,
    String? idAlmacen,
  }) =>
      _repo.exportPdf(
        desde: desde,
        hasta: hasta,
        idProducto: idProducto,
        idAlmacen: idAlmacen,
      );
}