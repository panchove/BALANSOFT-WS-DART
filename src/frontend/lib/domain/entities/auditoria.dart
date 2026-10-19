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

  /// Icono representativo de la operación.
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

  const AuditoriaPage({
    required this.items,
    required this.total,
    required this.skip,
    required this.limit,
  });

  factory AuditoriaPage.fromJson(Map<String, dynamic> json) => AuditoriaPage(
        items: (json['items'] as List? ?? [])
            .map((e) =>
                AuditoriaEvento.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: (json['total'] as num?)?.toInt() ?? 0,
        skip: (json['skip'] as num?)?.toInt() ?? 0,
        limit: (json['limit'] as num?)?.toInt() ?? 50,
      );

  bool get tieneMore => skip + limit < total;
}
