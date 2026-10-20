// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 27001 / ISO/IEC 25010
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

import '../../domain/entities/license.dart';

class LicenseMapper {
  static Map<String, dynamic> toMap(License license) => license.toJson();

  static License fromMap(Map<String, dynamic> map) => License.fromJson(map);
}
