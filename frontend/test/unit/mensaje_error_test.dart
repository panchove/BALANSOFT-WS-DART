import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:balansoft_ws/core/utils/mensaje_error.dart';

DioException _error(int status, Object data) {
  final opciones = RequestOptions(path: '/api/v1/auth/login');
  return DioException(
    requestOptions: opciones,
    response: Response(
      requestOptions: opciones,
      statusCode: status,
      data: data,
    ),
    type: DioExceptionType.badResponse,
  );
}

void main() {
  group('esErrorEquipoSinAprobar', () {
    test('detecta el 403 de equipo pendiente de aprobación', () {
      final e = _error(403, {
        'detail':
            'Este equipo está pendiente de aprobación por el administrador de '
            'la cuenta: apruébelo desde el equipo titular.',
      });
      expect(esErrorEquipoSinAprobar(e), isTrue);
    });

    test('detecta el 403 de equipo rechazado', () {
      final e = _error(403, {
        'detail': 'Este equipo fue rechazado por el administrador de la cuenta.',
      });
      expect(esErrorEquipoSinAprobar(e), isTrue);
    });

    test('el 403 de límite de sesiones NO es de aprobación', () {
      final e = _error(403, {
        'detail': 'La cuenta supera el límite de sesiones de la licencia (3).',
      });
      expect(esErrorEquipoSinAprobar(e), isFalse);
    });

    test('otros estados y errores no cuentan', () {
      expect(esErrorEquipoSinAprobar(_error(401, {'detail': 'no'})), isFalse);
      expect(esErrorEquipoSinAprobar(StateError('sin credencial')), isFalse);
      expect(esErrorEquipoSinAprobar(_error(403, 'texto plano')), isFalse);
    });
  });

  group('mensajeDeError', () {
    test('prefiere el detail del backend', () {
      expect(
        mensajeDeError(_error(400, {'detail': 'Credenciales inválidas'})),
        'Credenciales inválidas',
      );
    });

    test('usa el fallback cuando no hay respuesta', () {
      final e = DioException(
        requestOptions: RequestOptions(path: '/'),
        type: DioExceptionType.connectionError,
      );
      expect(mensajeDeError(e, fallback: 'X'), contains('No se pudo conectar'));
    });
  });

  group('parsearErrorTitular', () {
    test('extrae titular, nombre y la huella recibida del 403', () {
      final e = _error(403, {
        'detail': 'La cuenta ADMIN está activada en otro equipo titular.',
        'hardware_titular': 'HW-TITULAR-001',
        'hardware_recibido': 'HW-ESTE-EQUIPO',
        'nombre_equipo_titular': 'PC-Titular',
      });
      final info = parsearErrorTitular(e);
      expect(info.hardwareTitular, 'HW-TITULAR-001');
      expect(info.hardwareRecibido, 'HW-ESTE-EQUIPO');
      expect(info.nombreEquipoTitular, 'PC-Titular');
      expect(info.mensaje, contains('otro equipo titular'));
    });

    test('hardware_recibido ausente queda en null (central anterior)', () {
      final e = _error(403, {
        'detail': 'La cuenta ADMIN está activada en otro equipo titular.',
        'hardware_titular': 'HW-TITULAR-001',
      });
      final info = parsearErrorTitular(e);
      expect(info.hardwareTitular, 'HW-TITULAR-001');
      expect(info.hardwareRecibido, isNull);
    });

    test('un 403 sin hardware_titular no es de titular', () {
      final e = _error(403, {'detail': 'Equipo pendiente de aprobación.'});
      final info = parsearErrorTitular(e);
      expect(info.hardwareTitular, isNull);
      expect(info.hardwareRecibido, isNull);
    });
  });
}
