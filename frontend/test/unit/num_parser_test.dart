import 'package:flutter_test/flutter_test.dart';
import 'package:balansoft_ws/core/utils/num_parser.dart';

void main() {
  group('NumParser.toDouble', () {
    test('acepta num directo', () {
      expect(NumParser.toDouble(53000), 53000.0);
      expect(NumParser.toDouble(53000.5), 53000.5);
    });

    test('parsea string decimal del backend "53000.00"', () {
      expect(NumParser.toDouble('53000.00'), 53000.0);
      expect(NumParser.toDouble('5000.00'), 5000.0);
    });

    test('parsea string con coma como separador decimal', () {
      expect(NumParser.toDouble('53000,50'), 53000.5);
      expect(NumParser.toDouble('50,5'), 50.5);
    });

    test('null e inválidos usan el fallback', () {
      expect(NumParser.toDouble(null), 0);
      expect(NumParser.toDouble('' ), 0);
      expect(NumParser.toDouble('abc'), 0);
      expect(NumParser.toDouble('abc', 42), 42);
    });

    test('string vacío usa fallback por defecto', () {
      expect(NumParser.toDouble('  '), 0);
    });
  });

  group('NumParser.toDoubleOrNull', () {
    test('devuelve double para num y string', () {
      expect(NumParser.toDoubleOrNull(10), 10.0);
      expect(NumParser.toDoubleOrNull('10.50'), 10.50);
    });

    test('devuelve null para null, vacío e inválido', () {
      expect(NumParser.toDoubleOrNull(null), isNull);
      expect(NumParser.toDoubleOrNull(''), isNull);
      expect(NumParser.toDoubleOrNull('texto'), isNull);
    });
  });
}