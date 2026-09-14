/// T3.3 — UI exportación Excel.
///
/// Verifica que `ApiClient.exportExcel()` llama al endpoint correcto
/// (`/api/v1/reports/export/excel`) con los filtros de fecha.
library;

import 'dart:typed_data';

import 'package:balansoft_ws/data/datasources/remote/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecorderAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;
  final Uint8List returnBody;

  _RecorderAdapter(this.returnBody);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromBytes(
      returnBody,
      200,
      headers: {
        Headers.contentTypeHeader: [
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('exportExcel() llama al endpoint correcto y devuelve los bytes', () async {
    final adapter = _RecorderAdapter(Uint8List.fromList([1, 2, 3, 4]));
    final dio = Dio();
    dio.httpClientAdapter = adapter;
    final api = ApiClient(dio: dio);

    final response = await api.exportExcel({'fecha': '2026-09-08'});

    expect(adapter.lastRequest, isNotNull);
    expect(adapter.lastRequest!.path, contains('/reports/export/excel'));
    expect(adapter.lastRequest!.queryParameters['fecha'], '2026-09-08');
    expect(response.statusCode, 200);
    expect(response.data, isA<List<int>>());
  });
}