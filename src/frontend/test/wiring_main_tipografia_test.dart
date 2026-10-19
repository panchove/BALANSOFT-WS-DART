import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guardas de cableado de `main.dart` para T9 (spec 001).
///
/// Por qué existe: el resto de T9 prueba el *comportamiento* del escalador, del
/// tema y del scope, pero montarlos de verdad exigiría levantar `BalansoftApp`,
/// que arrastra `windowManager`, el `WServer` y toda la cadena de DI. El punto
/// que queda sin cubrir es si `main.dart` **escucha** al controlador y le pasa
/// la familia a los dos temas, y una mutación ahí (sacar `_typography` del
/// `Listenable.merge`) dejaba la suite entera en verde: el error se habría
/// visto recién en la estación, como un ajuste que no se aplica.
///
/// Se comprueba el cableado leyendo el fuente, no ejecutándolo. Es una prueba
/// de estructura, no de comportamiento: por eso mira la llamada concreta que
/// debe existir y no detalles de formato.
void main() {
  late String mainDart;

  setUpAll(() {
    mainDart = File('lib/main.dart').readAsStringSync();
  });

  group('main.dart aplica el ajuste de tipografía a toda la app', () {
    test('el controlador sale del contenedor de dependencias', () {
      expect(
        mainDart,
        contains('TypographyController>'),
        reason: 'sin resolver el singleton de DI, Ajustes y la app usarían '
            'instancias distintas y el cambio no se vería fuera de la pantalla',
      );
    });

    test('el controlador está en el Listenable.merge del MaterialApp', () {
      // Sin esto el cambio no llega al tema sin reiniciar (REQ-FN-004).
      final merge = RegExp(
        r'Listenable\.merge\((?:[^()]*|\([^()]*\))*\)',
        dotAll: true,
      ).firstMatch(mainDart);
      expect(merge, isNotNull,
          reason: 'no se encontró el Listenable.merge que envuelve al MaterialApp');
      expect(
        merge!.group(0),
        contains('_typography'),
        reason: 'el MaterialApp no se reconstruye al cambiar el ajuste',
      );
    });

    test('la familia y el factor de iconos llegan a los dos temas', () {
      // Los dos, no solo el claro: una pantalla en modo oscuro con la familia
      // sin aplicar es exactamente el tipo de bug que no se ve en desarrollo.
      final temas = RegExp(r'build(?:Light|Dark)Theme\(').allMatches(mainDart);
      expect(temas, hasLength(2),
          reason: 'se esperaban los dos temas con los mismos parámetros');
      for (final tema in temas) {
        final llamada = mainDart.substring(
          tema.start,
          mainDart.indexOf(')', tema.start),
        );
        expect(llamada, contains('familia:'),
            reason: 'el tema ${tema.group(0)} no recibe la familia');
        expect(llamada, contains('factorIconos:'),
            reason: 'el tema ${tema.group(0)} no recibe el factor de iconos');
      }
    });

    test('el ajuste de tamaño entra por el builder del MaterialApp', () {
      expect(
        mainDart,
        contains('TipografiaScope('),
        reason: 'el factor debe aplicarse en el builder, el único punto por '
            'encima de rutas, diálogos y showDialog',
      );
    });

    test('el ajuste persistido se carga al arrancar', () {
      expect(mainDart, contains('_typography.load()'),
          reason: 'sin la carga inicial el valor guardado no se restituye '
              '(REQ-FN-005)');
    });
  });
}
