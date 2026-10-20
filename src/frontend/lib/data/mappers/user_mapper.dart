// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 25010 / ISO/IEC 27001
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

import '../../domain/entities/user.dart';

class UserMapper {
  static Map<String, dynamic> toMap(User user) => user.toJson();

  static User fromMap(Map<String, dynamic> map) => User.fromJson(map);
}
