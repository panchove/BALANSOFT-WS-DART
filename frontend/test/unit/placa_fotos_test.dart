import 'package:flutter_test/flutter_test.dart';

import 'package:balansoft_ws/core/utils/placa_fotos.dart';

/// Reglas de las fotos de placa (config por empresa, migración 027).
///
/// La decisión vive en funciones puras: se prueba sin montar el formulario de
/// pesaje (que exige BLoC, catálogos y red).
void main() {
  group('debeCapturarPlaca', () {
    test('se ofrece cuando la empresa las activa y el boleto no las tiene', () {
      expect(
        debeCapturarPlaca(activas: true, yaTomadas: false),
        isTrue,
      );
    });

    test('no se ofrece si la empresa no las activó', () {
      expect(
        debeCapturarPlaca(activas: false, yaTomadas: false),
        isFalse,
      );
    });

    test('no se vuelve a pedir si el boleto ya las tiene (una vez por boleto)',
        () {
      expect(
        debeCapturarPlaca(activas: true, yaTomadas: true),
        isFalse,
      );
    });
  });

  group('exigeFotosPlacaAlGuardar', () {
    test('bloquea con obligatorias, activas y sin fotos', () {
      expect(
        exigeFotosPlacaAlGuardar(
          activas: true,
          obligatorias: true,
          yaTomadas: false,
          hayFotos: false,
        ),
        isTrue,
      );
    });

    test('no bloquea si ya hay fotos capturadas', () {
      expect(
        exigeFotosPlacaAlGuardar(
          activas: true,
          obligatorias: true,
          yaTomadas: false,
          hayFotos: true,
        ),
        isFalse,
      );
    });

    test('no bloquea si el boleto ya trae las fotos de la otra pesada', () {
      expect(
        exigeFotosPlacaAlGuardar(
          activas: true,
          obligatorias: true,
          yaTomadas: true,
          hayFotos: false,
        ),
        isFalse,
      );
    });

    test('no bloquea si son opcionales', () {
      expect(
        exigeFotosPlacaAlGuardar(
          activas: true,
          obligatorias: false,
          yaTomadas: false,
          hayFotos: false,
        ),
        isFalse,
      );
    });

    test('no bloquea si la empresa no las activó', () {
      expect(
        exigeFotosPlacaAlGuardar(
          activas: false,
          obligatorias: true,
          yaTomadas: false,
          hayFotos: false,
        ),
        isFalse,
      );
    });
  });

  group('sufijosPlacaRequeridos', () {
    test('sin remolque pide placa trasera y frente', () {
      expect(sufijosPlacaRequeridos(remolque: false),
          ['placa_trasera', 'frente']);
    });

    test('con remolque mantiene los mismos sufijos de la API', () {
      expect(
        sufijosPlacaRequeridos(remolque: true),
        ['placa_trasera', 'frente'],
      );
    });
  });

  group('nombresPlacaLocal', () {
    test('asigna los sufijos en orden', () {
      expect(nombresPlacaLocal(2, remolque: false),
          ['placa_trasera.jpg', 'frente.jpg']);
    });

    test('los sobrantes caen a placa_N sin romper', () {
      expect(nombresPlacaLocal(3, remolque: false),
          ['placa_trasera.jpg', 'frente.jpg', 'placa_3.jpg']);
    });

    test('cero fotos devuelve lista vacía', () {
      expect(nombresPlacaLocal(0, remolque: true), isEmpty);
    });
  });
}
