// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 25010 / ISO/IEC 27001
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

class Validators {
  static String? required(String? value, [String field = 'Campo']) {
    if (value == null || value.trim().isEmpty) {
      return '$field es obligatorio';
    }
    return null;
  }

  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) return 'Email es obligatorio';
    if (!isEmail(value)) return 'Email inválido';
    return null;
  }

  static bool isEmail(String value) {
    final regex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return regex.hasMatch(value.trim());
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Contraseña es obligatoria';
    if (value.length < 6) return 'Mínimo 6 caracteres';
    return null;
  }

  static String? positiveNumber(String? value, [String field = 'Precio']) {
    if (value == null || value.trim().isEmpty) return '$field es obligatorio';
    final num = double.tryParse(value);
    if (num == null || num < 0) return '$field debe ser positivo';
    return null;
  }

  static String? minLength(String? value, int min, [String field = 'Campo']) {
    if (value == null || value.length < min) {
      return '$field debe tener al menos $min caracteres';
    }
    return null;
  }
}
