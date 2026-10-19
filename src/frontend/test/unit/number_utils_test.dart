import 'package:flutter_test/flutter_test.dart';
import 'package:balansoft_ws/core/utils/number_utils.dart';

void main() {
  group('NumberUtils.formatWeight', () {
    test('null -> 0.00', () {
      expect(NumberUtils.formatWeight(null), '0.00');
    });

    test('deja dos decimales', () {
      expect(NumberUtils.formatWeight(53000), '53.000,00');
      expect(NumberUtils.formatWeight(5000.5), '5.000,50');
    });
  });

  group('NumberUtils.formatKg', () {
    test('agrega sufijo kg', () {
      expect(NumberUtils.formatKg(45000), '45.000,00 kg');
    });
  });

  group('NumberUtils.formatTons', () {
    test('divide entre 1000 y usa 3 decimales', () {
      expect(NumberUtils.formatTons(53000), '53.000 t');
      expect(NumberUtils.formatTons(null), '0.000 t');
    });
  });

  group('NumberUtils.formatPercent', () {
    test('porcentaje simple', () {
      expect(NumberUtils.formatPercent(5.5), '5.50%');
      expect(NumberUtils.formatPercent(null), '0.00%');
    });
  });

  group('NumberUtils.formatCurrency', () {
    test('formato bolívares', () {
      expect(NumberUtils.formatCurrency(1234.5), 'Bs. 1.234,50');
      expect(NumberUtils.formatCurrency(null), 'Bs. 0,00');
    });
  });

  group('NumberUtils.formatInt', () {
    test('entero con separador de miles', () {
      expect(NumberUtils.formatInt(12345), '12.345');
      expect(NumberUtils.formatInt(null), '0');
    });
  });
}