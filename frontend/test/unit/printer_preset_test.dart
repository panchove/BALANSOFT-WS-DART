import 'package:flutter_test/flutter_test.dart';
import 'package:balansoft_ws/domain/entities/printer_preset.dart';

void main() {
  group('PrinterPreset Unit Tests', () {
    test('Valores por defecto correctos', () {
      const preset = PrinterPreset();

      expect(preset.nombreImpresora, 'Impresora Térmica POS-80');
      expect(preset.tipoImpresora, 'POS_80');
      expect(preset.tamanoPapel, '80mm');
      expect(preset.orientacion, 'portrait');
      expect(preset.formatoPredeterminado, 'PDF');
      expect(preset.copias, 1);
      expect(preset.boletosPorHoja, 1);
      expect(preset.altoBoletoMm, 0.0);
      expect(preset.mostrarEncabezado, isTrue);
      expect(preset.mostrarDetalles, isTrue);
      expect(preset.margenMm, 5.0);
      expect(preset.anchoCustomMm, isNull);
      expect(preset.altoCustomMm, isNull);
    });

    test('Serialización y deserialización JSON (toJson / fromJson)', () {
      const original = PrinterPreset(
        nombreImpresora: 'HP LaserJet Pro',
        tipoImpresora: 'SISTEMA_PDF',
        tamanoPapel: 'Letter',
        orientacion: 'landscape',
        formatoPredeterminado: 'PDF',
        copias: 2,
        boletosPorHoja: 3,
        altoBoletoMm: 90.0,
        mostrarEncabezado: false,
        mostrarDetalles: true,
        margenMm: 8.0,
        anchoCustomMm: 215.9,
        altoCustomMm: 279.4,
      );

      final json = original.toJson();
      expect(json['nombreImpresora'], 'HP LaserJet Pro');
      expect(json['tipoImpresora'], 'SISTEMA_PDF');
      expect(json['tamanoPapel'], 'Letter');
      expect(json['orientacion'], 'landscape');
      expect(json['copias'], 2);
      expect(json['boletosPorHoja'], 3);
      expect(json['mostrarEncabezado'], isFalse);

      final deserialized = PrinterPreset.fromJson(json);
      expect(deserialized.nombreImpresora, original.nombreImpresora);
      expect(deserialized.tipoImpresora, original.tipoImpresora);
      expect(deserialized.tamanoPapel, original.tamanoPapel);
      expect(deserialized.orientacion, original.orientacion);
      expect(deserialized.formatoPredeterminado, original.formatoPredeterminado);
      expect(deserialized.copias, original.copias);
      expect(deserialized.boletosPorHoja, original.boletosPorHoja);
      expect(deserialized.altoBoletoMm, original.altoBoletoMm);
      expect(deserialized.mostrarEncabezado, original.mostrarEncabezado);
      expect(deserialized.mostrarDetalles, original.mostrarDetalles);
      expect(deserialized.margenMm, original.margenMm);
      expect(deserialized.anchoCustomMm, original.anchoCustomMm);
      expect(deserialized.altoCustomMm, original.altoCustomMm);
    });

    test('fromJson maneja campos ausentes con defaults seguros', () {
      final preset = PrinterPreset.fromJson(const {});

      expect(preset.nombreImpresora, 'Impresora Térmica POS-80');
      expect(preset.tipoImpresora, 'POS_80');
      expect(preset.tamanoPapel, '80mm');
      expect(preset.copias, 1);
      expect(preset.boletosPorHoja, 1);
      expect(preset.mostrarEncabezado, isTrue);
      expect(preset.mostrarDetalles, isTrue);
      expect(preset.margenMm, 5.0);
    });

    test('copyWith clona y actualiza propiedades específicas', () {
      const base = PrinterPreset();
      final modificado = base.copyWith(
        boletosPorHoja: 2,
        tamanoPapel: 'A4',
        mostrarEncabezado: false,
      );

      expect(modificado.boletosPorHoja, 2);
      expect(modificado.tamanoPapel, 'A4');
      expect(modificado.mostrarEncabezado, isFalse);
      expect(modificado.nombreImpresora, base.nombreImpresora);
      expect(modificado.mostrarDetalles, base.mostrarDetalles);
    });
  });
}
