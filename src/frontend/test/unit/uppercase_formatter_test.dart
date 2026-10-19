import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:balansoft_ws/core/utils/uppercase_formatter.dart';

void main() {
  const formatter = UpperCaseTextFormatter();

  TextEditingValue editar(String nuevo) => formatter.formatEditUpdate(
        const TextEditingValue(text: ''),
        TextEditingValue(
          text: nuevo,
          selection: TextSelection.collapsed(offset: nuevo.length),
        ),
      );

  group('UpperCaseTextFormatter', () {
    test('convierte minúsculas a mayúsculas al teclear', () {
      final result = editar('abc');
      expect(result.text, 'ABC');
    });

    test('no modifica (misma instancia) texto ya en mayúsculas', () {
const input = TextEditingValue(
        text: 'ABC-123',
        selection: TextSelection.collapsed(offset: 7),
      );
      final result = formatter.formatEditUpdate(input, input);
      expect(identical(result, input), isTrue,
          reason: 'un nuevo objeto provocaría rebuilds innecesarios');
    });

    test('mantiene el caret al final tras convertir', () {
      final result = editar('ABc');
      expect(result.text, 'ABC');
      expect(result.selection.baseOffset, 3);
      expect(result.selection.extentOffset, 3);
    });

    test('aplica también al editar en medio del texto', () {
      final result = formatter.formatEditUpdate(
        const TextEditingValue(
            text: 'AB', selection: TextSelection.collapsed(offset: 1)),
        const TextEditingValue(
            text: 'AxB', selection: TextSelection.collapsed(offset: 2)),
      );
      expect(result.text, 'AXB');
      expect(result.selection.baseOffset, 2);
    });

    test('respeta mayúsculas con acentos', () {
      final result = editar('cañon');
      expect(result.text, 'CAÑON');
    });
  });
}