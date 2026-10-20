// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 25010 / ISO/IEC 27001
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

import '../../domain/entities/user.dart';

class UserModel extends User {
  const UserModel({
    required super.idUsuario,
    required super.nombre,
    required super.email,
    required super.rol,
    super.idEmpresa,
    super.logoUrl,
    super.empresaNombre,
    super.empresaRif,
    super.empresaDireccion,
  });

  /// Construye el UserModel desde el `user` que devuelve el backend.
  /// Recibe el mapa `empresa` que viene aparte en el login para extraer
  /// nombre fiscal, RIF, dirección y logo.
  factory UserModel.fromJson(
    Map<String, dynamic> json, {
    Map<String, dynamic>? empresa,
  }) =>
      UserModel(
        idUsuario: json['id_usuario'],
        nombre: json['nombre'],
        email: json['email'],
        rol: json['rol'],
        idEmpresa: json['id_empresa'] ?? empresa?['id_empresa'],
        // Prioridad: empresa.logo_url → user.logo_url. Se ignora "" como si
        // fuera null (evita que un string vacío bloquee el fallback).
        logoUrl: _firstNonEmpty([empresa?['logo_url'], json['logo_url']]),
        empresaNombre: _firstNonEmpty([
          empresa?['nombre_fiscal'],
          empresa?['nombre_comercial'],
          json['empresa_nombre'],
        ]),
        empresaRif: _firstNonEmpty([empresa?['rif_nit'], json['empresa_rif']]),
        empresaDireccion: _firstNonEmpty([
          empresa?['direccion'],
          json['empresa_direccion'],
        ]),
      );

  factory UserModel.fromEntity(User user) => UserModel(
        idUsuario: user.idUsuario,
        nombre: user.nombre,
        email: user.email,
        rol: user.rol,
        idEmpresa: user.idEmpresa,
        logoUrl: user.logoUrl,
        empresaNombre: user.empresaNombre,
        empresaRif: user.empresaRif,
        empresaDireccion: user.empresaDireccion,
      );

  /// Devuelve el primer valor no vacío de la lista, ya recortado de espacios.
  /// Ignora `null`, valores no-string y strings vacíos/solo-espacios.
  static String? _firstNonEmpty(List<dynamic> candidates) {
    for (final c in candidates) {
      if (c is String) {
        final t = c.trim();
        if (t.isNotEmpty) return t;
      }
    }
    return null;
  }
}