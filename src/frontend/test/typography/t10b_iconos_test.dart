// T10b · Caso 6 — REQ-FN-003: iconos escalados proporcionalmente.
//
// `test/core/theme/app_theme_tipografia_test.dart` ya cubre el extremo
// superior, la `AppBar`, el `primaryIconTheme` y la independencia de la
// familia; `test/widget/tipografia_escalado_test.dart` ya mide el tamaño
// **renderizado** a 1.0 y a 1.40. Lo que faltaba era lo que este archivo añade:
//
//   * que la escala sea **lineal en todo el rango** [0.85, 1.40], no solo
//     cierta en los dos extremos (una escala con un escalón intermedio
//     pasaría las pruebas de los extremos);
//   * que el extremo **inferior** también llegue a la pantalla (0.85 → 17 px).
//
// La proporcionalidad se exige sobre `tamanoIconoBase`, no sobre un 20 escrito
// a mano: si el tamaño base cambiara, la razón se sigue teniendo que cumplir.

import 'package:balansoft_ws/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('T10b caso 6 · REQ-FN-003', () {
    test('la escala es lineal en todo el rango [0.85, 1.40]', () {
      // 41 muestras: extremo a extremo. Una escala proporcional tiene que
      // cumplir tamano = base × factor en *cada* punto, no solo en 0.85/1.40.
      for (var i = 0; i <= 40; i++) {
        final factor = 0.85 + (1.40 - 0.85) * i / 40;
        expect(
          escalaTamanoIcono(factor),
          closeTo(tamanoIconoBase * factor, 1e-9),
          reason: 'a factor $factor el tamaño debe ser '
              '${tamanoIconoBase * factor}, no ${escalaTamanoIcono(factor)}',
        );
      }
    });

    test('el tema aplica esa misma escala, en claro y en oscuro', () {
      for (final factor in [0.85, 1.0, 1.13, 1.40]) {
        expect(buildLightTheme(factorIconos: factor).iconTheme.size,
            closeTo(tamanoIconoBase * factor, 1e-9),
            reason: 'tema claro a factor $factor');
        expect(buildDarkTheme(factorIconos: factor).iconTheme.size,
            closeTo(tamanoIconoBase * factor, 1e-9),
            reason: 'tema oscuro a factor $factor');
      }
    });

    testWidgets('el extremo inferior llega al icono renderizado',
        (tester) async {
      // 0.85 × 20 = 17 px. Es el extremo que el otro test de renderizado no
      // midió, y el que más se confundiría con "no escaló".
      await tester.pumpWidget(MaterialApp(
        theme: buildLightTheme(factorIconos: 0.85),
        home: const Scaffold(body: Center(child: Icon(Icons.save))),
      ));
      expect(tester.widget<Icon>(find.byType(Icon)).size, isNull,
          reason: 'el Icon no debe fijar tamaño: lo hereda del tema');
      expect(tester.getSize(find.byType(Icon)).width,
          closeTo(tamanoIconoBase * 0.85, 0.01));
    });

    testWidgets('el icono renderizado crece con el factor, no se parte',
        (tester) async {
      final medidas = <double, double>{};
      for (final factor in [0.85, 1.0, 1.40]) {
        await tester.pumpWidget(MaterialApp(
          theme: buildLightTheme(factorIconos: factor),
          home: const Scaffold(body: Center(child: Icon(Icons.save))),
        ));
        await tester.pumpAndSettle();
        medidas[factor] = tester.getSize(find.byType(Icon)).width;
      }
      // Proporcionalidad sobre lo que se ve de verdad.
      expect(medidas[1.40]! / medidas[1.0]!, closeTo(1.40, 0.01));
      expect(medidas[0.85]! / medidas[1.0]!, closeTo(0.85, 0.01));
    });
  });
}
