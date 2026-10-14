/// Entidades del centro de notificaciones de la estación.
///
/// Espejo del contrato de `backend/app/api/v1/endpoints/notificaciones.py`:
/// la bandeja (`/api/v1/notificaciones`) la llena el **programador del backend**
/// (WServer, residente aunque la app Flutter esté cerrada); el aviso nativo del
/// SO lo dibuja el propio WServer. La app solo lee, marca leída/archivada y
/// administra recordatorios.
library;

/// Aviso de la bandeja (campana del *navbar*).
class AppNotification {
  final String id;
  final String tipo;
  final String severidad;
  final String titulo;
  final String? mensaje;
  final String estado;
  final bool leida;
  final String origen;
  final Map<String, dynamic>? acciones;
  final String? idReferencia;
  final String? idRecordatorio;
  final DateTime? programadaPara;
  final DateTime createdAt;
  final DateTime? leidaEn;

  const AppNotification({
    required this.id,
    required this.tipo,
    required this.severidad,
    required this.titulo,
    this.mensaje,
    this.estado = 'no_leida',
    this.leida = false,
    this.origen = 'evento',
    this.acciones,
    this.idReferencia,
    this.idRecordatorio,
    this.programadaPara,
    required this.createdAt,
    this.leidaEn,
  });

  static const String estadoNoLeida = 'no_leida';
  static const String estadoLeida = 'leida';
  static const String estadoArchivado = 'archivado';

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final estado = '${json['estado'] ?? estadoNoLeida}';
    return AppNotification(
      id: '${json['id'] ?? ''}',
      tipo: '${json['tipo'] ?? 'sistema'}',
      severidad: '${json['severidad'] ?? 'info'}',
      titulo: '${json['titulo'] ?? ''}',
      mensaje: json['mensaje'] as String?,
      estado: estado,
      // El backend manda `leida`; si faltara, se deriva del estado.
      leida: json['leida'] as bool? ?? (estado != estadoNoLeida),
      origen: '${json['origen'] ?? 'evento'}',
      acciones: (json['acciones'] as Map?)?.cast<String, dynamic>(),
      idReferencia: json['id_referencia'] as String?,
      idRecordatorio: json['id_recordatorio'] as String?,
      programadaPara: _fecha(json['programada_para']),
      createdAt:
          DateTime.tryParse('${json['created_at']}') ?? DateTime.now().toUtc(),
      leidaEn: _fecha(json['leida_en']),
    );
  }

  /// Producto de un recordatorio (no de un evento automático).
  bool get esRecordatorio => tipo == 'recordatorio' || origen == 'recordatorio';

  @override
  String toString() => '$tipo:$titulo';
}

/// Contadores para el badge de la campana.
class NotificationSummary {
  final int noLeidas;
  final int total;
  final Map<String, int> porSeveridad;

  const NotificationSummary({
    this.noLeidas = 0,
    this.total = 0,
    this.porSeveridad = const {},
  });

  factory NotificationSummary.fromJson(Map<String, dynamic> json) {
    final crudo = json['por_severidad'];
    final mapa = <String, int>{};
    if (crudo is Map) {
      crudo.forEach((clave, valor) {
        mapa['$clave'] = (valor as num?)?.toInt() ?? 0;
      });
    }
    return NotificationSummary(
      noLeidas: (json['no_leidas'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
      porSeveridad: mapa,
    );
  }
}

/// Recordatorio programado de la estación (`/api/v1/recordatorios`).
class Reminder {
  final String id;
  final String titulo;
  final String? mensaje;
  final DateTime programadaPara;
  final String recurrencia;
  final bool activo;
  final DateTime? ultimaEjecucion;
  final DateTime createdAt;

  const Reminder({
    required this.id,
    required this.titulo,
    this.mensaje,
    required this.programadaPara,
    this.recurrencia = 'none',
    this.activo = true,
    this.ultimaEjecucion,
    required this.createdAt,
  });

  /// Recurrencias aceptadas por el backend (`Recordatorio.RECURRENCIAS`).
  static const List<String> recurrencias = ['none', 'daily', 'weekly', 'monthly'];

  factory Reminder.fromJson(Map<String, dynamic> json) => Reminder(
        id: '${json['id'] ?? ''}',
        titulo: '${json['titulo'] ?? ''}',
        mensaje: json['mensaje'] as String?,
        programadaPara: DateTime.parse('${json['programada_para']}'),
        recurrencia: '${json['recurrencia'] ?? 'none'}',
        activo: json['activo'] as bool? ?? true,
        ultimaEjecucion: json['ultima_ejecucion'] == null
            ? null
            : DateTime.tryParse('${json['ultima_ejecucion']}'),
        createdAt: DateTime.parse('${json['created_at']}'),
      );
}

DateTime? _fecha(dynamic valor) {
  if (valor == null) return null;
  return DateTime.tryParse('$valor');
}
