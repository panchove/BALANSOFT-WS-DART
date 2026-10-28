import 'package:flutter_test/flutter_test.dart';

import 'package:balansoft_ws/domain/entities/kardex.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────
  // Tests del modelo KardexMovimiento (no requieren mocks ni DI).
  // Verifican que los 4 campos nuevos del backend se parseen bien.
  // ─────────────────────────────────────────────────────────────────
  group('KardexMovimiento.fromJson', () {
    test('parsea los 4 campos nuevos del backend', () {
      final json = {
        'id_kardex': 'abc-123',
        'fecha': '2026-10-27T08:00:00',
        'id_movimiento': 10,
        'concepto_nombre': 'Ingreso por báscula',
        'concepto_signo': 'positivo',
        'concepto_es_sistema': true,
        'origen': 'Báscula',
        'id_producto': 'P1',
        'nombre_producto': 'Maíz',
        'codigo_producto': 'MAI',
        'id_almacen': 'A1',
        'valor': 12450.0,
        'stock': 12450.0,
      };
      final m = KardexMovimiento.fromJson(json);
      expect(m.idKardex, 'abc-123');
      expect(m.idMovimiento, 10);
      expect(m.conceptoNombre, 'Ingreso por báscula');
      expect(m.conceptoSigno, 'positivo');
      expect(m.conceptoEsSistema, true);
      expect(m.origen, 'Báscula');
      expect(m.valor, 12450.0);
      expect(m.stock, 12450.0);
      expect(m.esIngreso, true);
    });

    test('origen null si falta en el JSON', () {
      final json = {
        'id_kardex': 'x',
        'fecha': '2026-10-27',
        'id_movimiento': 60,
        'id_producto': 'P1',
        'id_almacen': 'A1',
        'valor': 300.0,
        'stock': 1200.0,
      };
      final m = KardexMovimiento.fromJson(json);
      expect(m.origen, isNull);
      expect(m.conceptoNombre, isNull);
      expect(m.conceptoEsSistema, false);
      expect(m.esIngreso, false);
    });

    test('concepto del sistema 0 es saldo inicial', () {
      final json = {
        'id_kardex': 'y',
        'fecha': '2026-10-01',
        'id_movimiento': 0,
        'concepto_nombre': 'Saldo inicial',
        'concepto_signo': 'inicial',
        'concepto_es_sistema': true,
        'origen': 'Sistema',
        'id_producto': 'P1',
        'id_almacen': 'A1',
        'valor': 1000.0,
        'stock': 1000.0,
      };
      final m = KardexMovimiento.fromJson(json);
      expect(m.idMovimiento, 0);
      expect(m.conceptoNombre, 'Saldo inicial');
      expect(m.conceptoSigno, 'inicial');
      expect(m.conceptoEsSistema, true);
      expect(m.origen, 'Sistema');
      expect(m.esIngreso, true); // 0 < 50
    });

    test('concepto manual 5 es positivo (esIngreso)', () {
      final json = {
        'id_kardex': 'z',
        'fecha': '2026-10-15',
        'id_movimiento': 5,
        'concepto_nombre': 'Compra',
        'concepto_signo': 'positivo',
        'concepto_es_sistema': false,
        'origen': 'Manual',
        'id_producto': 'P1',
        'id_almacen': 'A1',
        'documento': 'AJUSTE-001',
        'valor': 200.0,
        'stock': 1700.0,
      };
      final m = KardexMovimiento.fromJson(json);
      expect(m.idMovimiento, 5);
      expect(m.conceptoNombre, 'Compra');
      expect(m.conceptoEsSistema, false);
      expect(m.origen, 'Manual');
      expect(m.documento, 'AJUSTE-001');
      expect(m.esIngreso, true);
    });

    test('concepto 60 es despacho (no esIngreso)', () {
      final json = {
        'id_kardex': 'w',
        'fecha': '2026-10-10',
        'id_movimiento': 60,
        'concepto_nombre': 'Despacho por báscula',
        'concepto_signo': 'negativo',
        'concepto_es_sistema': true,
        'origen': 'Báscula',
        'id_producto': 'P1',
        'id_almacen': 'A1',
        'numero_boleto': 'TA-00000002',
        'valor': 300.0,
        'stock': 1200.0,
      };
      final m = KardexMovimiento.fromJson(json);
      expect(m.idMovimiento, 60);
      expect(m.esIngreso, false);
      expect(m.numeroBoleto, 'TA-00000002');
    });
  });

  // ─────────────────────────────────────────────────────────────────
  // Tests del modelo KardexDetalle.
  // ─────────────────────────────────────────────────────────────────
  group('KardexDetalle.fromJson', () {
    test('parsea saldos y lista de movimientos', () {
      final json = {
        'fecha_desde': '2026-10-01',
        'fecha_hasta': '2026-10-27',
        'saldo_inicial': 1000.0,
        'saldo_actual': 1200.0,
        'movimientos': [
          {
            'id_kardex': '1',
            'fecha': '2026-10-01',
            'id_movimiento': 10,
            'id_producto': 'P1',
            'id_almacen': 'A1',
            'valor': 500.0,
            'stock': 1500.0,
          },
        ],
      };
      final d = KardexDetalle.fromJson(json);
      expect(d.saldoInicial, 1000.0);
      expect(d.saldoActual, 1200.0);
      expect(d.movimientos.length, 1);
      expect(d.movimientos.first.idMovimiento, 10);
    });

    test('lista vacía si no hay movimientos', () {
      final json = {
        'fecha_desde': '2026-10-01',
        'fecha_hasta': '2026-10-27',
        'saldo_inicial': 0.0,
        'saldo_actual': 0.0,
        'movimientos': [],
      };
      final d = KardexDetalle.fromJson(json);
      expect(d.movimientos, isEmpty);
    });
  });
}