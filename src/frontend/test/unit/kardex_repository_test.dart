/// T3.4 — UI Kardex (repositorio).
///
/// Verifica que `KardexRepository` llama a los endpoints correctos
/// (`/reports/kardex/detalle`, `/reports/export/kardex/excel`) con sus filtros.
library;

import 'dart:typed_data';

import 'package:balansoft_ws/data/datasources/remote/api_client.dart';
import 'package:balansoft_ws/data/repositories/kardex_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecorderAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    if (options.responseType == ResponseType.bytes) {
      return ResponseBody.fromBytes(
        Uint8List.fromList([1, 2, 3]),
        200,
        headers: {Headers.contentTypeHeader: ['application/octet-stream']},
      );
    }
    return ResponseBody.fromString(
      '{"fecha_desde":"2026-09-01T00:00:00","fecha_hasta":"2026-09-08T00:00:00",'
      '"saldo_inicial":1000.0,"saldo_actual":1300.0,'
      '"movimientos":['
      '{"id_kardex":"k1","fecha":"2026-09-02T12:00:00","id_movimiento":10,'
      '"id_producto":"P-01","id_almacen":"A-01","documento":"DOC",'
      '"boleto":"b1","valor":500.0,"stock":1500.0},'
      '{"id_kardex":"k2","fecha":"2026-09-03T12:00:00","id_movimiento":60,'
      '"id_producto":"P-01","id_almacen":"A-01","documento":"DOC",'
      '"boleto":"b2","valor":200.0,"stock":1300.0}]}',
      200,
      headers: {Headers.contentTypeHeader: ['application/json']},
    );
  }

  @override
  void close({bool force = false}) {}
}

KardexRepository _repo(_RecorderAdapter adapter) {
  final dio = Dio();
  dio.httpClientAdapter = adapter;
  return KardexRepository(apiClient: ApiClient(dio: dio));
}

void main() {
  test('detalle() llama a /reports/kardex/detalle con filtros y parsea', () async {
    final adapter = _RecorderAdapter();
    final repo = _repo(adapter);

    final detalle = await repo.detalle(
      desde: DateTime(2026, 9, 1),
      hasta: DateTime(2026, 9, 8),
      idProducto: 'P-01',
      idAlmacen: 'A-01',
    );

    expect(adapter.lastRequest!.path, contains('/reports/kardex/detalle'));
    expect(adapter.lastRequest!.queryParameters['id_producto'], 'P-01');
    expect(adapter.lastRequest!.queryParameters['id_almacen'], 'A-01');
    expect(detalle.saldoInicial, 1000.0);
    expect(detalle.saldoActual, 1300.0);
    expect(detalle.movimientos, hasLength(2));
    expect(detalle.movimientos.first.esIngreso, isTrue);
    expect(detalle.movimientos.first.stock, 1500.0);
  });

  test('exportExcel() llama a /reports/export/kardex/excel y devuelve bytes', () async {
    final adapter = _RecorderAdapter();
    final repo = _repo(adapter);

    final response = await repo.exportExcel(
      desde: DateTime(2026, 9, 1),
      hasta: DateTime(2026, 9, 8),
    );

    expect(adapter.lastRequest!.path, contains('/reports/export/kardex/excel'));
    expect(adapter.lastRequest!.queryParameters['fecha_desde'], '2026-09-01');
    expect(adapter.lastRequest!.queryParameters['fecha_hasta'], '2026-09-08');
    expect(response.data, isA<List<int>>());
  });
}