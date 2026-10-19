/// T3.1 — Health check del frontend.
///
/// Verifica que `ApiClient.health()` devuelve `true` con backend OK y `false`
/// ante error HTTP o de conexión (sin red real: adapter stub).
library;

import 'dart:typed_data';

import 'package:balansoft_ws/data/datasources/remote/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter({this.status = 200, this.throwDioException = false});

  int status;
  final bool throwDioException;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (throwDioException) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    return ResponseBody.fromString(
      '{"status": "healthy"}',
      status,
      headers: {Headers.contentTypeHeader: ['application/json']},
    );
  }

  @override
  void close({bool force = false}) {}
}

ApiClient _client(int status, {bool throwDioException = false}) {
  final dio = Dio();
  dio.httpClientAdapter =
      _StubAdapter(status: status, throwDioException: throwDioException);
  return ApiClient(dio: dio);
}

void main() {
  test('health() devuelve true con backend OK', () async {
    expect(await _client(200).health(), isTrue);
  });

  test('health() devuelve false con error HTTP (500)', () async {
    expect(await _client(500).health(), isFalse);
  });

  test('health() devuelve false con error de conexión', () async {
    expect(
      await _client(0, throwDioException: true).health(),
      isFalse,
    );
  });
}