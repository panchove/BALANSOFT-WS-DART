// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 25010 / ISO/IEC 27001
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

/// Entidades del módulo de Auditoría (REQ-NF-SEG-001).
library;

/// Evento registrado en el log de auditoría del sistema.
///
/// Cada operación de escritura sobre tablas sensibles (boletos, catálogos,
/// usuarios, etc.) genera un registro de auditoría con el detalle del cambio.
class AuditoriaEvento {
  final String idAuditoria;
  final String tabla;
  final String operacion;
  final String? idRegistro;
  final Map<String, dynamic>? cambios;
  final String? ip;
  final String? idUsuario;
  final String? nombreUsuario;
  final String creadoEn;

  /// Crea una instancia inmutable de un evento de auditoría.
  const AuditoriaEvento({
    required this.idAuditoria,
    required this.tabla,
    required this.operacion,
    this.idRegistro,
    this.cambios,
    this.ip,
    this.idUsuario,
    this.nombreUsuario,
    required this.creadoEn,
  });

  /// Construye un [AuditoriaEvento] a partir de un mapa JSON retornado por la API de auditoría.
  ///
  /// Poscondiciones:
  /// - Mapea de forma segura identificadores y valores numéricos a cadenas.
  /// - Extrae el diccionario de cambios si está presente.
  factory AuditoriaEvento.fromJson(Map<String, dynamic> json) =>
      AuditoriaEvento(
        idAuditoria: '${json['id_audit'] ?? json['id_auditoria'] ?? ''}',
        tabla: json['tabla'] as String? ?? '',
        operacion: json['operacion'] as String? ?? '',
        idRegistro: json['id_registro'] != null ? '${json['id_registro']}' : null,
        cambios: json['cambios'] is Map
            ? Map<String, dynamic>.from(json['cambios'] as Map)
            : null,
        ip: json['ip'] as String?,
        idUsuario:
            json['id_usuario'] != null ? '${json['id_usuario']}' : null,
        nombreUsuario: json['nombre_usuario'] as String?,
        creadoEn: json['creado_en'] as String? ?? json['created_at'] as String? ?? '',
      );

  /// Icono representativo de la operación (CREATE, UPDATE, DELETE).
  String get iconoOperacion {
    switch (operacion.toUpperCase()) {
      case 'CREATE':
        return '➕';
      case 'UPDATE':
        return '✏️';
      case 'DELETE':
        return '🗑️';
      default:
        return '📋';
    }
  }

  @override
  String toString() => '$operacion en $tabla ($creadoEn)';
}

/// Resumen de la paginación de eventos de auditoría.
class AuditoriaPage {
  final List<AuditoriaEvento> items;
  final int total;
  final int skip;
  final int limit;

  /// Crea una página inmutable de eventos de auditoría.
  const AuditoriaPage({
    required this.items,
    required this.total,
    required this.skip,
    required this.limit,
  });

  /// Construye una [AuditoriaPage] a partir de la respuesta paginada de la API.
  factory AuditoriaPage.fromJson(Map<String, dynamic> json) => AuditoriaPage(
        items: (json['items'] as List? ?? [])
            .map((e) =>
                AuditoriaEvento.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: (json['total'] as num?)?.toInt() ?? 0,
        skip: (json['skip'] as num?)?.toInt() ?? 0,
        limit: (json['limit'] as num?)?.toInt() ?? 50,
      );

  /// Indica si existen más registros en páginas posteriores (`skip + limit < total`).
  bool get tieneMore => skip + limit < total;
}
