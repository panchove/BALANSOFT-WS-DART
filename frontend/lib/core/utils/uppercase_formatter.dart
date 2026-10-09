import 'package:flutter/services.dart';

/// Convierte la entrada del usuario a MAYÚSCULAS en caliente: al teclear,
/// pegar desde el portapapeles o autocompletar.
///
/// Se aplica a los campos de datos de negocio (placa, conductor, documentos,
/// catálogos y registro de cuenta) para normalizar el valor que se persiste.
///
/// NO debe aplicarse a contraseñas ni a correos electrónicos: el backend
/// compara el email en minúsculas y la contraseña es sensible a mayúsculas.
class UpperCaseTextFormatter extends TextInputFormatter {
  const UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final texto = newValue.text.toUpperCase();
    if (texto == newValue.text) return newValue;
    // Algunos caracteres cambian de longitud al pasar a mayúsculas (p. ej. ß),
    // así que el caret se reubica para que siga apuntando al último carácter
    // editado en lugar de quedarse desfasado.
    final delta = texto.length - newValue.text.length;
    final fin = (newValue.selection.end + delta).clamp(0, texto.length);
    return newValue.copyWith(
      text: texto,
      selection: TextSelection.collapsed(offset: fin),
    );
  }
}