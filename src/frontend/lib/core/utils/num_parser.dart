// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 25010 / ISO/IEC 27001
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

/// Parser robusto de valores numéricos que llegan del backend.
///
/// Los campos `Decimal` de FastAPI/Pydantic se serializan como string
/// (ej. `"53000.00"`), por lo que nunca se debe asumir que vienen como
/// `num`. Esta utilidad acepta `num`, `String` o `null`.
class NumParser {
  NumParser._();

  static double toDouble(dynamic value, [double fallback = 0]) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    final s = value.toString().replaceAll(',', '.').trim();
    if (s.isEmpty) return fallback;
    return double.tryParse(s) ?? fallback;
  }

  static double? toDoubleOrNull(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final s = value.toString().replaceAll(',', '.').trim();
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }
}
