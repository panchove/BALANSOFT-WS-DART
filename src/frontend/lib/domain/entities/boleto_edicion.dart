// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 25010 / ISO/IEC 27001
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

/// Una edición registrada de un boleto de pesaje (historial inmutable).
///
/// Espeja `BoletoEdicionOut` del backend (migración 024): cada edición guarda
/// su justificación, quién la hizo, cuándo y qué campos cambiaron. El backend
/// las devuelve más reciente primero (`GET /weighing/{boleto}/ediciones`).
class BoletoEdicion {
  final String idEdicion;
  final String boleto;
  final String? numeroBoleto;
  final String? idUsuario;
  final String? usuarioNombre;
  final String? rolUsuario;
  final DateTime fechaEdicion;
  final String? ip;
  final String justificacion;
  final String estadoAnterior;
  final String estadoNuevo;
  final Map<String, dynamic>? camposModificados;
  final int edicionNumero;

  const BoletoEdicion({
    required this.idEdicion,
    required this.boleto,
    this.numeroBoleto,
    this.idUsuario,
    this.usuarioNombre,
    this.rolUsuario,
    required this.fechaEdicion,
    this.ip,
    required this.justificacion,
    required this.estadoAnterior,
    required this.estadoNuevo,
    this.camposModificados,
    required this.edicionNumero,
  });

  factory BoletoEdicion.fromJson(Map<String, dynamic> json) => BoletoEdicion(
        idEdicion: json['id_edicion']?.toString() ?? '',
        boleto: json['boleto']?.toString() ?? '',
        numeroBoleto: json['numero_boleto']?.toString(),
        idUsuario: json['id_usuario']?.toString(),
        usuarioNombre: json['usuario_nombre']?.toString(),
        rolUsuario: json['rol_usuario']?.toString(),
        fechaEdicion: json['fecha_edicion'] != null
            ? DateTime.parse(json['fecha_edicion'])
            : DateTime.now(),
        ip: json['ip']?.toString(),
        justificacion: json['justificacion']?.toString() ?? '',
        estadoAnterior: json['estado_anterior']?.toString() ?? '',
        estadoNuevo: json['estado_nuevo']?.toString() ?? '',
        camposModificados: json['campos_modificados'] is Map
            ? Map<String, dynamic>.from(json['campos_modificados'] as Map)
            : null,
        edicionNumero: (json['edicion_numero'] as num?)?.toInt() ?? 0,
      );

  /// Nombres legibles de los campos que cambiaron (para el historial).
  List<String> get camposCambiados =>
      (camposModificados ?? const {}).keys.map((k) => k.toString()).toList();
}
