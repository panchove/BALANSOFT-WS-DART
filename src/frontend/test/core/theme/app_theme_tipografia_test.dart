import 'package:flutter_test/flutter_test.dart';

import 'package:balansoft_ws/core/theme/app_theme.dart';

void main() {
  group('familia tipográfica en el TextTheme (REQ-FN-001)', () {
    test('la familia elegida llega a todos los estilos del TextTheme', () {
      for (final familia in ['sans-serif', 'serif', 'monospace', 'Roboto']) {
        final claro = buildLightTheme(familia: familia);
        final oscuro = buildDarkTheme(familia: familia);

        expect(claro.textTheme.bodyMedium?.fontFamily, equals(familia),
            reason: 'tema claro, familia $familia');
        expect(claro.textTheme.titleLarge?.fontFamily, equals(familia),
            reason: 'tema claro, familia $familia');
        expect(oscuro.textTheme.bodyMedium?.fontFamily, equals(familia),
            reason: 'tema oscuro, familia $familia');
        expect(oscuro.textTheme.displaySmall?.fontFamily, equals(familia),
            reason: 'tema oscuro, familia $familia');
      }
    });

    test('sin familia el TextTheme queda como hoy (no-regresión)', () {
      // `buildLightTheme()` y `buildDarkTheme()` se siguen llamando sin
      // argumentos en 4 tests del repo y deben quedar exactamente igual: pasar
      // `familia: null` no puede cambiar nada. Ojo: el `fontFamily` **no** es
      // `null` en este caso, sino el que trae la tipografía base de Material
      // (`Roboto` en esta plataforma), y es lo que hay que comparar.
      final porDefecto = buildLightTheme().textTheme.bodyMedium?.fontFamily;
      expect(buildLightTheme(familia: null).textTheme.bodyMedium?.fontFamily,
          equals(porDefecto));
      expect(buildDarkTheme(familia: null).textTheme.bodyMedium?.fontFamily,
          equals(buildDarkTheme().textTheme.bodyMedium?.fontFamily));

      // Y elegir una familia sí lo cambia.
      expect(buildLightTheme(familia: 'serif').textTheme.bodyMedium?.fontFamily,
          equals('serif'));
    });

    test('la familia no cambia el color del texto', () {
      // El ajuste de tipografía es ortogonal al del tema: activar una familia no
      // puede repintar la pantalla.
      final base = buildLightTheme();
      final conFamilia = buildLightTheme(familia: 'Roboto');
      expect(conFamilia.textTheme.bodyMedium?.color,
          equals(base.textTheme.bodyMedium?.color));
      expect(conFamilia.colorScheme.primary, equals(base.colorScheme.primary));
    });
  });

  group('REQ-FN-006 — familia no instalada', () {
    test('una familia inexistente se aplica sin fallar ni lanzar', () {
      // Flutter no valida el nombre: si la fuente no está, el motor cae a la
      // siguiente de su lista de fuentes. Lo que exige el requisito es que no
      // haya excepción ni aviso, y eso se comprueba en el test de widget.
      final tema = buildLightTheme(familia: 'FuenteQueNoExiste_0000');
      expect(tema.textTheme.bodyMedium?.fontFamily,
          equals('FuenteQueNoExiste_0000'));
    });

    test('el tamaño del texto no depende de que la familia exista', () {
      final conFuente = buildLightTheme(familia: 'FuenteQueNoExiste_0000');
      final sinFuente = buildLightTheme();
      expect(conFuente.textTheme.bodyMedium?.fontSize,
          equals(sinFuente.textTheme.bodyMedium?.fontSize));
    });
  });

  group('escala de iconos (REQ-FN-003)', () {
    test('el factor 1.0 reproduce el tamaño de icono actual (20 px)', () {
      // No-regresión: el tema fijaba `IconThemeData(size: 20)` fijo.
      expect(tamanoIconoBase, closeTo(20.0, 1e-9));
      expect(buildLightTheme().iconTheme.size, closeTo(20, 1e-9));
      expect(buildDarkTheme().iconTheme.size, closeTo(20, 1e-9));
      expect(escalaTamanoIcono(1.0), closeTo(20, 1e-9));
    });

    test('el icono escala con el factor del operador en los dos extremos', () {
      // 0.85 × 20 = 17 y 1.40 × 20 = 28.
      expect(escalaTamanoIcono(0.85), closeTo(17, 1e-9));
      expect(escalaTamanoIcono(1.40), closeTo(28, 1e-9));

      expect(buildLightTheme(factorIconos: 0.85).iconTheme.size,
          closeTo(17, 1e-9));
      expect(buildLightTheme(factorIconos: 1.40).iconTheme.size,
          closeTo(28, 1e-9));
      expect(buildDarkTheme(factorIconos: 1.40).iconTheme.size,
          closeTo(28, 1e-9));
    });

    test('escala también el iconTheme de la AppBar y el primaryIconTheme', () {
      // AppBar, `FilledButton` y los iconos de navegación heredan de aquí: es
      // lo que cubre REQ-FN-003 sin tocar un solo `Icon` a mano.
      final claro = buildLightTheme(factorIconos: 1.40);
      final oscuro = buildDarkTheme(factorIconos: 1.40);

      expect(claro.appBarTheme.iconTheme?.size, closeTo(28, 1e-9));
      expect(oscuro.appBarTheme.iconTheme?.size, closeTo(28, 1e-9));
      expect(claro.primaryIconTheme.size, closeTo(28, 1e-9));
      expect(oscuro.primaryIconTheme.size, closeTo(28, 1e-9));
    });

    test('la escala de iconos es independiente de la familia', () {
      final a = buildLightTheme(familia: 'serif', factorIconos: 1.40);
      final b = buildLightTheme(familia: 'monospace', factorIconos: 1.40);
      expect(a.iconTheme.size, equals(b.iconTheme.size));
      expect(a.textTheme.bodyMedium?.fontFamily, isNot(equals(b.textTheme.bodyMedium?.fontFamily)));
    });

    test('el factor de iconos no toca el tamaño del texto del tema', () {
      // El texto lo escala el `textScaler` del `MediaQuery`, no el tema: si el
      // tema también multiplicara el tamaño, el factor se aplicaría dos veces.
      // (En el `TextTheme` base el `fontSize` va en `null` a propósito: lo
      // resuelve el `Text` al pintar, ya con el `textScaler` aplicado.)
      final base = buildLightTheme();
      final escalado = buildLightTheme(factorIconos: 1.40);
      expect(escalado.textTheme.bodyMedium?.fontSize,
          equals(base.textTheme.bodyMedium?.fontSize));
      expect(escalado.iconTheme.size, isNot(equals(base.iconTheme.size)));
    });
  });
}