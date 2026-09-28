import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:balansoft_ws/data/repositories/activacion_repository.dart';

/// La pantalla de activación es el primer contacto con el servidor central en
/// campo: el mensaje que ve el instalador tiene que decir qué pasó de verdad.
/// El caso crítico es el 502, que el backend usa para dos cosas distintas
/// (red caída contra el central vs. error propio del central).
void main() {
  DioException excepcionCon({
    int? statusCode,
    Object? body,
    DioExceptionType type = DioExceptionType.badResponse,
  }) {
    return DioException(
      requestOptions: RequestOptions(path: '/api/v1/auth/login-central'),
      type: type,
      response: statusCode == null
          ? null
          : Response(
              requestOptions: RequestOptions(path: '/x'),
              statusCode: statusCode,
              data: body,
            ),
      error: type == DioExceptionType.connectionError
          ? const SocketException('Connection refused')
          : null,
    );
  }

  group('Mensajes de la activación', () {
    test('401 explica que son las credenciales, sin culpar a la red', () {
      final msg = ActivacionRepository.mensajeDe(
        excepcionCon(statusCode: 401, body: {'detail': 'Credenciales inválidas'}),
      );
      expect(msg, contains('Credenciales incorrectas'));
    });

    test('403 muestra el detalle del backend (licencia en otra máquina)', () {
      final msg = ActivacionRepository.mensajeDe(
        excepcionCon(
          statusCode: 403,
          body: {'detail': 'Esta licencia ya está activa en otro equipo.'},
        ),
      );
      expect(msg, 'Esta licencia ya está activa en otro equipo.');
    });

    test('502 conserva el detalle real en vez de un mensaje genérico', () {
      final msg = ActivacionRepository.mensajeDe(
        excepcionCon(
          statusCode: 502,
          body: {'detail': 'No se pudo conectar con el servidor central: ConnectError'},
        ),
      );
      expect(msg, contains('No se pudo conectar con el servidor central'));
      expect(msg, contains('ConnectError'));
    });

    test('sin respuesta del servidor no culpa al central', () {
      final msg = ActivacionRepository.mensajeDe(
        excepcionCon(type: DioExceptionType.connectionError),
      );
      expect(msg, contains('API de esta máquina'));
      expect(msg, isNot(contains('servidor central')));  // no culpa al central
    });
  });
}
