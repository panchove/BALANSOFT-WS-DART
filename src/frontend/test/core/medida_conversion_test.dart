import 'package:balansoft_ws/core/utils/medida_conversion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConversionMedida.calcular', () {
    const densidadPalma = 0.92;
    const pesoSacoMaiz = 50.0;

    test('Kilogramos devuelve el peso neto tal cual', () {
      expect(
        ConversionMedida.calcular(pesoNetoKg: 18000, medida: UnidadMedida.kg),
        18000,
      );
    });

    test('Litros = PNT / densidad (ejemplo del aceite de palma)', () {
      final litros = ConversionMedida.calcular(
        pesoNetoKg: 18000,
        medida: UnidadMedida.litros,
        densidad: densidadPalma,
      );
      expect(litros, closeTo(19565.217391, 0.001));
      expect(ConversionMedida.formatear(litros), '19565.22');
    });

    test('Galones = Litros / 3.78541', () {
      final galones = ConversionMedida.calcular(
        pesoNetoKg: 18000,
        medida: UnidadMedida.galones,
        densidad: densidadPalma,
      );
      final litros = ConversionMedida.calcular(
        pesoNetoKg: 18000,
        medida: UnidadMedida.litros,
        densidad: densidadPalma,
      );
      expect(galones, closeTo(litros! / 3.78541, 0.0001));
      expect(galones, closeTo(5168.58, 0.01));
    });

    test('Toneladas = PNT / 1000', () {
      expect(
        ConversionMedida.calcular(
            pesoNetoKg: 25000, medida: UnidadMedida.toneladas),
        25,
      );
    });

    test('Unidades = PNT / peso unitario del producto', () {
      expect(
        ConversionMedida.calcular(
          pesoNetoKg: 20000,
          medida: UnidadMedida.unidades,
          pesoUnidad: pesoSacoMaiz,
        ),
        400,
      );
    });

    test('devuelve null si falta el factor requerido', () {
      expect(
        ConversionMedida.calcular(
            pesoNetoKg: 18000, medida: UnidadMedida.litros),
        isNull,
      );
      expect(
        ConversionMedida.calcular(
          pesoNetoKg: 18000,
          medida: UnidadMedida.litros,
          densidad: 0,
        ),
        isNull,
      );
      expect(
        ConversionMedida.calcular(
          pesoNetoKg: 20000,
          medida: UnidadMedida.unidades,
        ),
        isNull,
      );
    });

    test('devuelve null con peso neto cero o negativo', () {
      for (final medida in UnidadMedida.values) {
        expect(
          ConversionMedida.calcular(
            pesoNetoKg: 0,
            medida: medida,
            densidad: 0.92,
            pesoUnidad: 50,
          ),
          isNull,
          reason: 'debe ser null para $medida',
        );
      }
    });

    test('no divide por cero cuando la densidad es negativa', () {
      expect(
        ConversionMedida.calcular(
          pesoNetoKg: 1000,
          medida: UnidadMedida.litros,
          densidad: -2,
        ),
        isNull,
      );
    });
  });

  group('ConversionMedida.litros', () {
    test('calcula litros para persistir en el boleto', () {
      expect(ConversionMedida.litros(pesoNetoKg: 9200, densidad: 0.92), 10000);
      expect(ConversionMedida.litros(pesoNetoKg: 9200), isNull);
    });
  });

  group('desdeUnidadProducto', () {
    test('mapea las unidades del catálogo de productos', () {
      expect(
          ConversionMedida.desdeUnidadProducto('TON'), UnidadMedida.toneladas);
      expect(ConversionMedida.desdeUnidadProducto('UN'), UnidadMedida.unidades);
      expect(ConversionMedida.desdeUnidadProducto('KG'), UnidadMedida.kg);
      expect(ConversionMedida.desdeUnidadProducto('LBS'), UnidadMedida.kg);
      expect(
          ConversionMedida.desdeUnidadProducto('LITROS'), UnidadMedida.litros);
      expect(ConversionMedida.desdeUnidadProducto('GAL'), UnidadMedida.galones);
      expect(ConversionMedida.desdeUnidadProducto(null), UnidadMedida.kg);
      expect(ConversionMedida.desdeUnidadProducto('xyz'), UnidadMedida.kg);
    });
  });

  group('desdeTexto (boletos legados)', () {
    test('interpreta el texto libre guardado en measure', () {
      expect(ConversionMedida.desdeTexto('Litros'), UnidadMedida.litros);
      expect(ConversionMedida.desdeTexto('GALONES'), UnidadMedida.galones);
      expect(ConversionMedida.desdeTexto('Toneladas'), UnidadMedida.toneladas);
      expect(ConversionMedida.desdeTexto('Sacos'), UnidadMedida.unidades);
      expect(ConversionMedida.desdeTexto('  KG  '), UnidadMedida.kg);
      expect(ConversionMedida.desdeTexto(null), isNull);
      expect(ConversionMedida.desdeTexto(''), isNull);
    });
  });

  group('UnidadMedida', () {
    test('solo líquidos requieren densidad', () {
      expect(UnidadMedida.litros.requiereDensidad, isTrue);
      expect(UnidadMedida.galones.requiereDensidad, isTrue);
      expect(UnidadMedida.kg.requiereDensidad, isFalse);
      expect(UnidadMedida.toneladas.requiereDensidad, isFalse);
      expect(UnidadMedida.unidades.requiereDensidad, isFalse);
    });

    test('solo unidades requieren peso unitario', () {
      expect(UnidadMedida.unidades.requierePesoUnidad, isTrue);
      expect(UnidadMedida.litros.requierePesoUnidad, isFalse);
    });

    test('la etiqueta persistida es estable por medida', () {
      expect(UnidadMedida.litros.etiquetaPersistida, 'Litros');
      expect(UnidadMedida.galones.etiquetaPersistida, 'Galones');
      expect(UnidadMedida.toneladas.etiquetaPersistida, 'Toneladas');
      expect(UnidadMedida.unidades.etiquetaPersistida, 'Unidades');
      expect(UnidadMedida.kg.etiquetaPersistida, 'Kilogramos');
    });
  });
}
