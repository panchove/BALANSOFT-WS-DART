/// Entidades de RB-12: aprobación de equipos de la cuenta.
///
/// Espejo del contrato del **servidor central**
/// (`backend/app/api/v1/endpoints/servidor.py`, `GET/PATCH /api/v1/auth/sesiones`).
///
/// A diferencia del resto de la UI, estos datos NO viven en la estación: salen
/// de la base del servidor central y se consultan con la credencial global
/// (`_serverToken`, obtenida en el `serverLogin` del login central-first). La
/// cuenta sale SIEMPRE del token, nunca de un parámetro del cliente.
library;

/// Un equipo registrado en la cuenta, con su estado de aprobación (RB-12).
class SesionEquipo {
  final String idDispositivo;
  final String hardwareId;
  final String? nombreEquipo;
  final String? sistemaOperativo;
  final String? versionApp;

  /// `LOCAL` o `SERVIDOR` (rol de instalación del equipo).
  final String rolDispositivo;

  /// Rol con el que operará la sesión: `ADMIN|OPERADOR|AUDITOR`.
  /// `null` mientras el equipo no ha sido aprobado.
  final String? rolSesion;

  /// `PENDIENTE|APROBADO|RECHAZADO`.
  final String estado;
  final bool activo;

  /// Equipo titular de la licencia (`licencias.hardware_id`). Es la tutora y
  /// no puede rechazarse ni cambiársele el rol.
  final bool esDueno;

  final DateTime? ultimaConexion;
  final DateTime? createdAt;

  const SesionEquipo({
    required this.idDispositivo,
    required this.hardwareId,
    this.nombreEquipo,
    this.sistemaOperativo,
    this.versionApp,
    this.rolDispositivo = 'LOCAL',
    this.rolSesion,
    this.estado = 'APROBADO',
    this.activo = true,
    this.esDueno = false,
    this.ultimaConexion,
    this.createdAt,
  });

  static const String estadoPendiente = 'PENDIENTE';
  static const String estadoAprobado = 'APROBADO';
  static const String estadoRechazado = 'RECHAZADO';

  static const List<String> estados = [
    estadoPendiente,
    estadoAprobado,
    estadoRechazado,
  ];

  /// Roles que el ADMIN puede asignar a la sesión de un equipo.
  static const List<String> rolesSesion = [
    'ADMIN',
    'OPERADOR',
    'AUDITOR',
  ];

  bool get estaPendiente => estado == estadoPendiente;
  bool get estaAprobado => estado == estadoAprobado;
  bool get estaRechazado => estado == estadoRechazado;

  /// Puede editarse desde la UI: el titular nunca.
  bool get esEditable => !esDueno;

  factory SesionEquipo.fromJson(Map<String, dynamic> json) => SesionEquipo(
        idDispositivo: '${json['id_dispositivo'] ?? ''}',
        hardwareId: '${json['hardware_id'] ?? ''}',
        nombreEquipo: json['nombre_equipo'] as String?,
        sistemaOperativo: json['sistema_operativo'] as String?,
        versionApp: json['version_app'] as String?,
        rolDispositivo: '${json['rol_dispositivo'] ?? 'LOCAL'}',
        rolSesion: json['rol_sesion'] as String?,
        estado: '${json['estado'] ?? estadoAprobado}',
        activo: json['activo'] as bool? ?? true,
        esDueno: json['es_dueno'] as bool? ?? false,
        ultimaConexion: _fecha(json['ultima_conexion']),
        createdAt: _fecha(json['created_at']),
      );

  @override
  String toString() => '$hardwareId:$estado';
}

/// Respuesta de `GET /api/v1/auth/sesiones`.
class SesionesEquipo {
  final List<SesionEquipo> items;

  /// Tope de equipos de la licencia (`null` = ilimitado).
  final int? maxEquipos;

  /// Tope de sesiones concurrentes (`null` = ilimitado).
  final int? maxSesiones;

  /// `hardware_id` del equipo titular de la licencia.
  final String? hardwareTitular;

  const SesionesEquipo({
    this.items = const [],
    this.maxEquipos,
    this.maxSesiones,
    this.hardwareTitular,
  });

  int get total => items.length;

  int get pendientes =>
      items.where((e) => e.estaPendiente).length;

  factory SesionesEquipo.fromJson(Map<String, dynamic> json) => SesionesEquipo(
        items: (json['items'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((m) => SesionEquipo.fromJson(m.cast<String, dynamic>()))
            .toList(),
        maxEquipos: (json['max_equipos'] as num?)?.toInt(),
        maxSesiones: (json['max_sesiones'] as num?)?.toInt(),
        hardwareTitular: json['hardware_titular'] as String?,
      );
}

DateTime? _fecha(Object? valor) {
  if (valor == null) return null;
  return DateTime.tryParse('$valor');
}
