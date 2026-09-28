import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/company_setup_form.dart';

/// Borrador de datos de empresa capturado **antes** del login.
///
/// La instalación (modo Servidor o Cliente) pide los datos de la empresa, logo,
/// formatos de exportación y carpeta de reportes antes de autenticarse; se
/// guardan localmente y el `AuthRepository` los aplica a `PUT /api/v1/empresa`
/// justo después del login para que el sistema ya quede operativo
/// (docs/I18N_Y_ONBOARDING.md · REQ-NF-ONB-006).
class CompanyDraft {
  static const _prefijo = 'empresa.draft.';

  final CompanySetupData data;

  const CompanyDraft(this.data);

  bool get vacio => data.nombreFiscal.trim().isEmpty;

  Map<String, String> toPrefs() => {
        '${_prefijo}nombre_fiscal': data.nombreFiscal.trim(),
        '${_prefijo}nombre_comercial': data.nombreComercial.trim(),
        '${_prefijo}rif_nit': data.rifNit.trim(),
        '${_prefijo}direccion': data.direccion.trim(),
        '${_prefijo}telefono': data.telefono.trim(),
        '${_prefijo}email': data.email.trim(),
        '${_prefijo}idioma': data.idioma,
        '${_prefijo}formato_ticket': data.formatoTicket,
        '${_prefijo}formato_reporte': data.formatoReporte,
        '${_prefijo}ruta_exportacion_reportes': data.rutaReportes.trim(),
      };

  static CompanySetupData dataDesdePrefs(SharedPreferences prefs) {
    String leer(String clave, [String def = '']) =>
        prefs.getString('$_prefijo$clave') ?? def;
    return CompanySetupData(
      nombreFiscal: leer('nombre_fiscal'),
      nombreComercial: leer('nombre_comercial'),
      rifNit: leer('rif_nit'),
      direccion: leer('direccion'),
      telefono: leer('telefono'),
      email: leer('email'),
      idioma: leer('idioma', 'es'),
      formatoTicket: leer('formato_ticket', 'PDF'),
      formatoReporte: leer('formato_reporte', 'EXCEL'),
      rutaReportes: leer('ruta_exportacion_reportes'),
    );
  }

  /// Guarda el borrador. El logo se conserva como base64 porque no se puede
  /// subir al backend sin token; se envía tras el login.
  static Future<CompanyDraft> guardar(
    CompanySetupData data, {
    List<int>? logoBytes,
    String? logoNombre,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final draft = CompanyDraft(data);
    for (final e in draft.toPrefs().entries) {
      await prefs.setString(e.key, e.value);
    }
    if (logoBytes != null) {
      await prefs.setString('${_prefijo}logo_nombre', logoNombre ?? 'logo.png');
      await prefs.setString('${_prefijo}logo_base64', base64Encode(logoBytes));
    }
    return draft;
  }

  /// `null` si el usuario nunca completó este paso en la instalación.
  static Future<CompanyDraft?> leer() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey('${_prefijo}nombre_fiscal')) return null;
    return CompanyDraft(dataDesdePrefs(prefs));
  }

  static Future<List<int>?> leerLogoBytes() async {
    final prefs = await SharedPreferences.getInstance();
    final b64 = prefs.getString('${_prefijo}logo_base64');
    if (b64 == null || b64.isEmpty) return null;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> leerLogoNombre() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('${_prefijo}logo_nombre');
  }

  static Future<void> limpiar() async {
    final prefs = await SharedPreferences.getInstance();
    for (final clave
        in prefs.getKeys().where((k) => k.startsWith(_prefijo)).toList()) {
      await prefs.remove(clave);
    }
  }
}
