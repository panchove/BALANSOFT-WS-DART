import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';

/// Datos de la cuenta que el servidor central devolvió al validar las
/// credenciales durante la instalación (paso 3 del modo servidor).
///
/// Sirven para **precargar** el formulario de empresa del paso 4: el operador
/// solo completa lo que el proveedor no registró (logo, formatos de
/// exportación, carpeta de reportes, idioma).
class CuentaActivada {
  static const _clave = 'cuenta.activada';

  final String? idCuenta;
  final String rifNit;
  final String nombreFiscal;
  final String nombreComercial;
  final String? direccion;
  final String? telefono;
  final String email;
  final String? licenciaKey;
  final String? licenciaTier;
  final String? licenciaStatus;
  final String? licenciaExpira;
  final String emailActivacion;
  final String? logoUrl;
  final bool titular;

  const CuentaActivada({
    this.idCuenta,
    required this.rifNit,
    required this.nombreFiscal,
    this.nombreComercial = '',
    this.direccion,
    this.telefono,
    this.email = '',
    this.licenciaKey,
    this.licenciaTier,
    this.licenciaStatus,
    this.licenciaExpira,
    this.emailActivacion = '',
    this.logoUrl,
    this.titular = false,
  });

  /// Lee la cuenta guardada; `null` si la estación aún no se activó.
  static Future<CuentaActivada?> leer() async {
    final prefs = await SharedPreferences.getInstance();
    final crudo = prefs.getString(_clave);
    if (crudo == null || crudo.isEmpty) return null;
    try {
      return CuentaActivada.fromJson(jsonDecode(crudo) as Map<String, dynamic>);
    } catch (_) {
      await prefs.remove(_clave);
      return null;
    }
  }

  static Future<void> guardar(CuentaActivada cuenta) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clave, json.encode(cuenta.toJson()));
  }

  static Future<void> limpiar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_clave);
  }

  /// Construye la cuenta desde la respuesta de `POST /api/v1/auth/login-central`.
  factory CuentaActivada.fromLoginResponse(
    Map<String, dynamic> data, {
    required String email,
    required bool titular,
  }) {
    final emp = (data['empresa'] as Map<String, dynamic>?) ?? const {};
    final lic = (data['license'] as Map<String, dynamic>?) ?? const {};
    String txt(String? v) => v?.trim() ?? '';
    return CuentaActivada(
      idCuenta: txt(lic['id_cuenta'] ?? emp['id_cuenta']).isEmpty
          ? null
          : txt(lic['id_cuenta'] ?? emp['id_cuenta']),
      rifNit: txt(emp['rif_nit']),
      nombreFiscal: txt(emp['nombre_fiscal']),
      nombreComercial: txt(emp['nombre_comercial']),
      direccion: txt(emp['direccion']).isEmpty ? null : txt(emp['direccion']),
      telefono: txt(emp['telefono']).isEmpty ? null : txt(emp['telefono']),
      email: txt(emp['email']),
      licenciaKey:
          txt(emp['licencia_key']).isEmpty ? null : txt(emp['licencia_key']),
      licenciaTier: txt(lic['tier'] ?? emp['licencia_tier']),
      licenciaStatus: txt(lic['status'] ?? emp['licencia_status']),
      licenciaExpira: txt(lic['expires_at'] ?? emp['licencia_expira']),
      emailActivacion: email,
      logoUrl: txt(emp['logo_url']).isEmpty ? null : txt(emp['logo_url']),
      titular: titular,
    );
  }

  Map<String, dynamic> toJson() => {
        'id_cuenta': idCuenta,
        'rif_nit': rifNit,
        'nombre_fiscal': nombreFiscal,
        'nombre_comercial': nombreComercial,
        'direccion': direccion,
        'telefono': telefono,
        'email': email,
        'licencia_key': licenciaKey,
        'licencia_tier': licenciaTier,
        'licencia_status': licenciaStatus,
        'licencia_expira': licenciaExpira,
        'email_activacion': emailActivacion,
        'logo_url': logoUrl,
        'titular': titular,
      };

  factory CuentaActivada.fromJson(Map<String, dynamic> json) => CuentaActivada(
        idCuenta: json['id_cuenta'] as String?,
        rifNit: json['rif_nit'] as String? ?? '',
        nombreFiscal: json['nombre_fiscal'] as String? ?? '',
        nombreComercial: json['nombre_comercial'] as String? ?? '',
        direccion: json['direccion'] as String?,
        telefono: json['telefono'] as String?,
        email: json['email'] as String? ?? '',
        licenciaKey: json['licencia_key'] as String?,
        licenciaTier: json['licencia_tier'] as String?,
        licenciaStatus: json['licencia_status'] as String?,
        licenciaExpira: json['licencia_expira'] as String?,
        emailActivacion: json['email_activacion'] as String? ?? '',
        logoUrl: json['logo_url'] as String?,
        titular: json['titular'] as bool? ?? false,
      );

  /// `true` si la cuenta tiene RIF y razón social (datos mínimos para precargar
  /// el formulario de empresa sin pedir nada al operador).
  bool get tieneDatos =>
      rifNit.trim().isNotEmpty && nombreFiscal.trim().isNotEmpty;

  /// Vuelve a marcar la estación como no activada (reinstalación).
  static Future<void> reiniciar() async {
    await limpiar();
    await AppConfig.setLicenciaVerificada(verificada: false, titular: false);
  }
}
