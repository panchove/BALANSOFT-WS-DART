/// Pruebas del parser multi-marca de tramas de báscula (Dart).
///
/// `lib/data/services/scale_frame_parser.dart` es el gemelo Dart de
/// `backend/app/core/scale_parser.py`: lo usa `ScaleTcpClient` para leer
/// indicadores reales que emiten ASCII continuo (`ST,GS,+00320.00kg`) además
/// del JSON del simulador BSDD. Fija el principio anti-falso-positivo: un
/// número desnudo nunca se acepta como peso.
library;

import 'package:balansoft_ws/data/services/scale_frame_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseWeightFrame · tramas reales', () {
    final casos = <String, (double, String?)>{
      'ST,GS,+00320.00kg': (320.0, 'stable'),
      'ST,GS,+  320.00 kg': (320.0, 'stable'),
      'ST,GS,-00012.50kg': (-12.5, 'stable'),
      '01+000320.0': (320.0, null),
      '01-000015.5': (-15.5, null),
      '  -  12.50KG': (-12.5, null),
      'US,GS,+00100.0kg': (100.0, 'unstable'),
      'ST,GS,    0.00 kg': (0.0, 'stable'),
      '320.00kg': (320.0, null),
      // Yaohua XK3190 (indicadores chinos estilo "="): PC continuo, sin estado.
      '=+000023.5kg': (23.5, null),
      '=+000000.0kg': (0.0, null),
      '=-001234.0kg': (-1234.0, null),
      '= 00023.5 kg': (23.5, null),
      // Torrey LQ / Keli: salida continua estilo Toledo/GSI.
      'ST,GS,+00042.5kg': (42.5, 'stable'),
      'ST,GS,+00320.0kg': (320.0, 'stable'),
      // ETX suelto (como llega tras readuntil(b'\x03')) no rompe el número.
      'ST,GS,320.00kg\x03': (320.0, 'stable'),
      'ST,GS,+00320.00kg\x03': (320.0, 'stable'),
    };

    casos.forEach((linea, esperado) {
      test('"$linea" → ${esperado.$1}', () {
        final r = parseWeightFrame(linea);
        expect(r.peso, esperado.$1);
        expect(r.estado, esperado.$2);
        expect(r.motivo, isNull);
      });
    });
  });

  group('parseWeightFrame · rechazos', () {
    test('número desnudo no es un peso', () {
      expect(parseWeightFrame('1234567890').motivo, 'sin_numero');
      expect(parseWeightFrame('01').motivo, 'sin_numero');
      expect(parseWeightFrame('=000001').motivo, 'sin_numero');
    });

    test('dos números distintos son ambiguos', () {
      final r = parseWeightFrame('123.4 567.8');
      expect(r.peso, isNull);
      expect(r.motivo, 'ambiguo');
    });

    test('sobrecarga', () {
      final r = parseWeightFrame('OL');
      expect(r.peso, isNull);
      expect(r.estado, 'overload');
      expect(r.motivo, 'sobrecarga');
    });

    test('vacío', () {
      expect(parseWeightFrame('').motivo, 'vacio');
      expect(parseWeightFrame('   ').motivo, 'vacio');
    });
  });

  group('parseWeightFrame · checksum y capacidad', () {
    test('checksum válido se acepta', () {
      final r = parseWeightFrame('\u0002ST,GS,+00320.00kg\u00032B',
          validarChecksum: true);
      expect(r.peso, 320.0);
      expect(r.estado, 'stable');
    });

    test('checksum inválido se rechaza', () {
      final r = parseWeightFrame('\u0002ST,GS,+00320.00kg\u000300',
          validarChecksum: true);
      expect(r.peso, isNull);
      expect(r.motivo, 'checksum');
    });

    test('STX/ETX sin checksum también parsea', () {
      expect(parseWeightFrame('\u0002ST,GS,+00320.00kg\u0003').peso, 320.0);
    });

    test('sobre capacidad', () {
      final r = parseWeightFrame('ST,GS,+00320.00kg', capacidadMax: 100);
      expect(r.peso, isNull);
      expect(r.motivo, 'sobre_capacidad');
    });

    test('dentro del margen tolerado', () {
      final r = parseWeightFrame('ST,GS,+00105.00kg', capacidadMax: 100);
      expect(r.peso, 105.0);
    });

    test('precisión excesiva', () {
      expect(parseWeightFrame('ST,GS,+00320.0001kg').motivo, 'precision');
    });
  });

  group('clasificarTrama', () {
    test('detecta JSON del simulador', () {
      expect(clasificarTrama('{"weight_kg": 12.3, "status": "stable"}'), 'json');
    });

    test('JSON sin weight_kg no es JSON', () {
      expect(clasificarTrama('{"action": "get_state"}'), isNull);
    });

    test('detecta ASCII real', () {
      expect(clasificarTrama('ST,GS,+00320.00kg'), 'ascii');
    });

    test('basura', () {
      expect(clasificarTrama('no-es-json'), isNull);
      expect(clasificarTrama(''), isNull);
    });
  });
}
