import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:balansoft_ws/core/utils/clamped_text_scaler.dart';

/// Equivalente const de `TextScaler.linear(f)`: permite escribir
/// `const _Linear(2.0)` sin que el linter pida el mismo `const` en diez sitios.
class _Linear extends TextScaler {
  const _Linear(this.f);

  final double f;

  @override
  double scale(double fontSize) => fontSize * f;

  // ignore: deprecated_member_use
  @override
  double get textScaleFactor => f;
}

/// Escalador **no lineal** de mentira, para comprobar que la composición no
/// aplana el escalado real del sistema operativo (spec 001, `plan.md §5.2`,
/// opción A). Antes de 10 px crece al 100% y a partir de ahí al 120%.
///
/// `textScaleFactor` miente a propósito (1.10): es el valor "estimado" que
/// habría que leer para multiplicar a mano, y no sirve, porque el escalado real
/// no es lineal.
class _NoLineal extends TextScaler {
  const _NoLineal();

  @override
  double scale(double fontSize) {
    assert(fontSize >= 0);
    return fontSize <= 10 ? fontSize : fontSize * 1.2;
  }

  // ignore: deprecated_member_use
  @override
  double get textScaleFactor => 1.10;
}

void main() {
  group('escalarTexto — clamp técnico de REQ-FN-002b', () {
    test('un factor externo de 2.0 queda acotado a 1.60', () {
      final scaler = escalarTexto(
        externo: const _Linear(2.0),
        factorOperador: 1.0,
      );

      // 16 px del código escalados: 16 × 1.60 = 25,6 y no 16 × 2,0 = 32.
      expect(scaler.scale(16), closeTo(25.6, 1e-9));
      expect(scaler.scale(16) / 16, closeTo(1.60, 1e-9));
    });

    test('un factor externo enorme también queda acotado a 1.60', () {
      for (final externo in [3.0, 10.0, 1000.0]) {
        final scaler =
            escalarTexto(externo: _Linear(externo), factorOperador: 1.0);
        expect(scaler.scale(16) / 16, closeTo(1.60, 1e-9),
            reason: 'con factor externo $externo');
      }
    });

    test('un factor externo demasiado pequeño queda acotado a 0.85', () {
      final scaler =
          escalarTexto(externo: const _Linear(0.3), factorOperador: 1.0);
      expect(scaler.scale(16) / 16, closeTo(0.85, 1e-9));
    });

    test('el techo del clamp es 1.60, no 1.50', () {
      expect(ClampedTextScaler.maxPorDefecto, closeTo(1.60, 1e-9));
      expect(ClampedTextScaler.minPorDefecto, closeTo(0.85, 1e-9));

      // Con el techo viejo (1.50) este valor daba 24 y no 25,6.
      final scaler = ClampedTextScaler(
        1.0,
        interno: const _Linear(2.0).clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: ClampedTextScaler.maxPorDefecto,
            ),
      );
      expect(scaler.scale(16), closeTo(25.6, 1e-9));
    });
  });

  group('escalarTexto — el clamp NO limita lo que eligió el operador', () {
    test('el factor del operador llega a 1.40 sin recortarse', () {
      final scaler = escalarTexto(
        externo: const _Linear(1.0),
        factorOperador: 1.40,
      );
      expect(scaler.scale(16) / 16, closeTo(1.40, 1e-9));
      expect(scaler.scale(16), closeTo(22.4, 1e-9));
    });

    test('si se componen los dos, el factor efectivo tampoco pasa de 1.60', () {
      // SO a 1.20 y operador a 1.40 darían 1.68: por encima del techo del clamp
      // técnico, así que se acota a 1.60. Lo que no puede pasar nunca es que el
      // escalado total se vaya de [0.85, 1.60].
      final scaler = escalarTexto(
        externo: const _Linear(1.20),
        factorOperador: 1.40,
      );
      expect(scaler.scale(10) / 10, closeTo(1.60, 1e-9));
    });

    test('con el SO a tope y el operador a tope sigue sin pasar de 1.60', () {
      final scaler = escalarTexto(
        externo: const _Linear(2.0),
        factorOperador: 1.40,
      );
      expect(scaler.scale(16) / 16, closeTo(1.60, 1e-9));
    });

    test('el factor del operador llega a 0.85 sin recortarse', () {
      final scaler = escalarTexto(
        externo: const _Linear(1.0),
        factorOperador: 0.85,
      );
      expect(scaler.scale(16) / 16, closeTo(0.85, 1e-9));
    });

    test('factor 1.0 reproduce el comportamiento actual (no-regresión)', () {
      final scaler = escalarTexto(
        externo: const _Linear(1.0),
        factorOperador: 1.0,
      );
      expect(scaler.scale(16), closeTo(16, 1e-9));
      expect(scaler.scale(13), closeTo(13, 1e-9));
    });
  });

  group('ClampedTextScaler —REQ-FN-002c', () {
    test('implementa scale, clamp y textScaleFactor', () {
      const scaler = ClampedTextScaler(1.0);
      expect(scaler, isA<TextScaler>());
      expect(scaler.scale(10), closeTo(10, 1e-9));
      expect(scaler.clamp(minScaleFactor: 0.5, maxScaleFactor: 2.0),
          isA<TextScaler>());
    });

    test('clamp respeta el contrato de TextScaler.clamp', () {
      // Lo que varios widgets de Material piden sobre el `textScaler` heredado
      // (`NavigationBar` a 1.3, `AppBar`, `Slider`). El escalador compuesto debe
      // caer dentro de [min × fs, max × fs] **con el factor del operador incluido**.
      final scaler = escalarTexto(
        externo: const _Linear(2.0),
        factorOperador: 1.40,
      );

      // Techo 1.3 (NavigationBar) por debajo del factor efectivo de 1.60: sí se
      // nota, o sea que el clamp no es un adorno.
      final acotado = scaler.clamp(maxScaleFactor: 1.3);
      expect(acotado.scale(16), closeTo(16 * 1.3, 1e-9));

      // Piso 1.0 con el factor efectivo en 1.60: no puede bajar de ahí, pero
      // tampoco baja del piso que se le pidió.
      final conPiso = scaler.clamp(minScaleFactor: 1.0);
      expect(conPiso.scale(16), greaterThanOrEqualTo(16 * 1.0));

      final ventana = scaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.2);
      expect(ventana.scale(16), closeTo(16 * 1.2, 1e-9));
      expect(ventana.scale(16), greaterThanOrEqualTo(16 * 1.0));
    });

    test('clamp no rompe el factor externo que ya está acotado', () {
      // Doble acotado: 1.60 (técnico) y luego 2.0 (el de `NavigationBar`).
      final scaler = escalarTexto(
        externo: const _Linear(2.0),
        factorOperador: 1.0,
      );
      expect(scaler.clamp(maxScaleFactor: 2.0).scale(16),
          closeTo(16 * 1.60, 1e-9));
    });

    test('conserva el escalado no lineal del escalador interno', () {
      // Aplanar el escalador (leyendo su factor "estimado") daría 1.10 × 1.20 =
      // 1.32 para **todo** tamaño. Componiendo se conservan los saltos del
      // escalador interno, que es justo lo que la opción (A) de `plan.md §5.2`
      // compra frente a multiplicar los números.
      final scaler = escalarTexto(externo: const _NoLineal(), factorOperador: 1.20);

      expect(scaler.scale(10) / 10, closeTo(1.20, 1e-9)); // 1.00 × 1.20
      expect(scaler.scale(20) / 20, closeTo(1.44, 1e-9)); // 1.20 × 1.20
      expect(scaler.scale(20) / 20, isNot(closeTo(1.32, 1e-9)));
    });

    test('sin escalador interno sigue siendo un escalador lineal', () {
      const scaler = ClampedTextScaler(1.25);
      expect(scaler.interno, isNull);
      expect(scaler.scale(16), closeTo(20, 1e-9));
      expect(scaler.clampValue(2.0), closeTo(1.60, 1e-9));
      expect(scaler.clampValue(0.10), closeTo(0.85, 1e-9));
    });
  });
}