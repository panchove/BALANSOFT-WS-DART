import 'package:flutter_test/flutter_test.dart';
import 'package:balansoft_ws/domain/entities/weighing.dart';

Map<String, dynamic> _json({Map<String, dynamic>? overrides}) => {
      'boleto': 'b1b2b3b4-b5b6-4b7b-8b9b-babbbcbdbebf',
      'id_vehiculo': 'ABC123',
      'remolque': false,
      'fecha_hora_entrada': '2026-09-08T08:30:00.000Z',
      'peso_entrada_vehiculo': '53000.00',
      'peso_entrada_remolque': null,
      'peso_neto': '5000.00',
      'peso_neto_declarado': '5000.00',
      'peso_diferencia': '0.00',
      'porcentaje_desviacion': '0.0000',
      'densidad': '1.6000',
      'litros': '3125.00',
      'fecha_hora_salida': '2026-09-08T10:00:00.000Z',
      'peso_salida_vehiculo': '48000.00',
      'peso_salida_remolque': null,
      'documento': 'G-001',
      'estado_boleto': 'CERRADO',
      'numero_boleto': 'TA-00000001',
      'sincronizado': false,
      'created_at': '2026-09-08T08:30:00.000Z',
      'updated_at': '2026-09-08T10:00:00.000Z',
      ...?overrides,
    };

void main() {
  group('Weighing.fromJson', () {
    test('parsea pesos como string (Decimal de FastAPI)', () {
      final w = Weighing.fromJson(_json());
      expect(w.pesoEntradaVehiculo, 53000.0);
      expect(w.pesoSalidaVehiculo, 48000.0);
      expect(w.pesoNeto, 5000.0);
      expect(w.densidad, 1.6);
      expect(w.litros, 3125.0);
    });

    test('pesoTotalEntrada suma remolque', () {
      final w = Weighing.fromJson(
        _json(overrides: {
          'remolque': true,
          'peso_entrada_vehiculo': '52000.00',
          'peso_entrada_remolque': '7500.00',
          'peso_salida_vehiculo': '41500.00',
          'peso_salida_remolque': '7500.00',
        }),
      );
      expect(w.pesoTotalEntrada, 59500.0);
      expect(w.pesoTotalSalida, 49000.0);
      expect(w.remolque, isTrue);
    });

    test('estado y flags', () {
      final abierto = Weighing.fromJson(_json(overrides: {'estado_boleto': 'PENDIENTE'}));
      final anulado = Weighing.fromJson(_json(overrides: {'estado_boleto': 'ANULADO'}));
      final cerrado = Weighing.fromJson(_json());

      expect(abierto.isOpen, isTrue);
      expect(cerrado.isClosed, isTrue);
      expect(anulado.isAnulado, isTrue);
      expect(abierto.isClosed, isFalse);
      expect(cerrado.isOpen, isFalse);
    });

    test('defectos: remolque/estados no presentes', () {
      final w = Weighing.fromJson(_json(overrides: {'estado_boleto': null, 'remolque': null}));
      expect(w.remolque, isFalse);
      expect(w.estadoBoleto, 'PENDIENTE');
    });

    test('pendiente de sync', () {
      final w = Weighing.fromJson(_json(overrides: {'sincronizado': false}));
      expect(w.isPendingSync, isTrue);
    });
  });

  group('Weighing.toJson', () {
    test('round-trip conserva valores', () {
      final w = Weighing.fromJson(_json());
      final json = w.toJson();
      expect(json['boleto'], w.boleto);
      expect(json['peso_entrada_vehiculo'], 53000.0);
      expect(json['estado_boleto'], 'CERRADO');
    });
  });
}