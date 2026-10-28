import 'package:flutter_test/flutter_test.dart';

import 'package:balansoft_ws/core/utils/conceptos_kardex_rules.dart';

void main() {
  group('signoDeRangoKardex', () {
    test('00 es saldo inicial', () {
      expect(signoDeRangoKardex(0), 'inicial');
    });

    test('01-49 son positivos', () {
      for (final id in [1, 5, 15, 49]) {
        expect(signoDeRangoKardex(id), 'positivo', reason: 'ID $id');
      }
    });

    test('50-99 son negativos', () {
      for (final id in [50, 55, 61, 99]) {
        expect(signoDeRangoKardex(id), 'negativo', reason: 'ID $id');
      }
    });
  });

  group('esConceptoSistema', () {
    test('0, 10 y 60 son del sistema', () {
      expect(esConceptoSistema(0), isTrue);
      expect(esConceptoSistema(10), isTrue);
      expect(esConceptoSistema(60), isTrue);
    });

    test('el resto son configurables por el ADMIN', () {
      for (final id in [1, 5, 49, 50, 59, 61, 99]) {
        expect(esConceptoSistema(id), isFalse, reason: 'ID $id');
      }
    });
  });

  group('rangoDeKardex', () {
    test('agrupa cada ID en su rango', () {
      expect(rangoDeKardex(0), '00');
      expect(rangoDeKardex(10), '10');
      expect(rangoDeKardex(60), '60');
      expect(rangoDeKardex(7), '01-49');
      expect(rangoDeKardex(20), '11-49');
      expect(rangoDeKardex(55), '50-59');
      expect(rangoDeKardex(70), '61-99');
    });
  });

  group('idsLibresKardex', () {
    test('nunca ofrece los reservados 10 y 60', () {
      final libres = idsLibresKardex(const []);
      expect(libres.contains(10), isFalse);
      expect(libres.contains(60), isFalse);
      expect(libres.contains(0), isFalse);
    });

    test('excluye los IDs ya ocupados', () {
      final libres = idsLibresKardex(const [0, 5, 10, 60]);
      expect(libres.contains(5), isFalse);
      expect(libres.contains(6), isTrue);
    });

    test('no repite IDs', () {
      final libres = idsLibresKardex(const [3, 3, 7]);
      expect(libres.toSet().length, libres.length);
    });

    test('cubre todo el rango configurable', () {
      final libres = idsLibresKardex(const [0]);
      // 1..99 menos 10 y 60 = 97 huecos.
      expect(libres.length, 97);
    });
  });

  group('etiquetaSignoKardex', () {
    test('traduce el signo a texto de UI', () {
      expect(etiquetaSignoKardex('inicial'), 'Inicial');
      expect(etiquetaSignoKardex('positivo'), 'Positivo (+)');
      expect(etiquetaSignoKardex('negativo'), 'Negativo (-)');
    });
  });

  group('conceptosKardexParaAjuste', () {
    List<Map<String, dynamic>> catalogo() => [
          {
            'id_concepto': 0,
            'nombre': 'Saldo inicial',
            'signo': 'inicial',
            'es_sistema': true,
            'activo': true,
          },
          {
            'id_concepto': 10,
            'nombre': 'Ingreso por báscula',
            'signo': 'positivo',
            'es_sistema': true,
            'activo': true,
          },
          {
            'id_concepto': 60,
            'nombre': 'Despacho por báscula',
            'signo': 'negativo',
            'es_sistema': true,
            'activo': true,
          },
          {
            'id_concepto': 5,
            'nombre': 'Compra',
            'signo': 'positivo',
            'es_sistema': false,
            'activo': true,
          },
          {
            'id_concepto': 55,
            'nombre': 'Merma',
            'signo': 'negativo',
            'es_sistema': false,
            'activo': true,
          },
          {
            'id_concepto': 15,
            'nombre': 'Baja',
            'signo': 'positivo',
            'es_sistema': false,
            'activo': false,
          },
        ];

    test('nunca ofrece los conceptos del sistema', () {
      for (final turno in ['positivo', 'negativo']) {
        final nombres = conceptosKardexParaAjuste(catalogo(), turno)
            .map((c) => c['nombre'])
            .toList();
        expect(nombres.contains('Ingreso por báscula'), isFalse);
        expect(nombres.contains('Despacho por báscula'), isFalse);
        expect(nombres.contains('Saldo inicial'), isFalse);
      }
    });

    test('INGRESO solo ve conceptos positivos y activos', () {
      final items = conceptosKardexParaAjuste(catalogo(), 'positivo');
      expect(items.map((c) => c['nombre']), ['Compra']);
    });

    test('DESPACHO solo ve conceptos negativos y activos', () {
      final items = conceptosKardexParaAjuste(catalogo(), 'negativo');
      expect(items.map((c) => c['nombre']), ['Merma']);
    });

    test('excluye los conceptos inactivos', () {
      final items = conceptosKardexParaAjuste(catalogo(), 'positivo');
      expect(items.map((c) => c['nombre']).contains('Baja'), isFalse);
    });
  });
}
