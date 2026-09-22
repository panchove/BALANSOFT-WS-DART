/// Entidades del módulo de Dispositivos/Balanzas (REQ-NF-ARQ-004).
///
/// Complementa las entidades [Scale] y [PruebaConexion] de catalogs.dart
/// con el resultado del descubrimiento automático de básculas.
library;

/// Báscula descubierta automáticamente por el endpoint GET /balanzas/descubrir.
///
/// A diferencia de [Scale] (que representa una báscula ya registrada),
/// [ScaleDescubierta] describe una báscula detectada en la red o en
/// puertos serie que aún no está registrada en la empresa.
class ScaleDescubierta {
  final String descripcion;
  final String protocolo;
  final String? ipAddress;
  final int? puertoTcp;
  final String? puertoCom;
  final double? pesoKg;
  final bool isSimulada;

  const ScaleDescubierta({
    required this.descripcion,
    required this.protocolo,
    this.ipAddress,
    this.puertoTcp,
    this.puertoCom,
    this.pesoKg,
    this.isSimulada = false,
  });

  factory ScaleDescubierta.fromJson(Map<String, dynamic> json) =>
      ScaleDescubierta(
        descripcion: json['descripcion'] as String? ?? '',
        protocolo: json['protocolo'] as String? ?? 'tcp',
        ipAddress: json['ip_address'] as String?,
        puertoTcp: (json['puerto_tcp'] as num?)?.toInt(),
        puertoCom: json['puerto_com'] as String?,
        pesoKg: (json['peso_kg'] as num?)?.toDouble(),
        isSimulada: json['is_simulada'] as bool? ?? false,
      );

  /// Configuración de hardware resumida para mostrar en la UI.
  String get configuracionHardware {
    if (protocolo == 'serial') {
      return puertoCom != null ? 'SERIAL $puertoCom' : 'SERIAL sin puerto';
    }
    if (ipAddress != null) {
      return 'TCP $ipAddress:${puertoTcp ?? 5555}';
    }
    return 'Sin configuración';
  }

  bool get tieneHardware =>
      (puertoCom != null && puertoCom!.isNotEmpty) ||
      (ipAddress != null && ipAddress!.isNotEmpty);

  @override
  String toString() => descripcion;
}

/// Estado de una sesión de báscula activa (peso en tiempo real).
class EstadoSesionBalanza {
  final String idBalanza;
  final bool conectado;
  final double? pesoKg;
  final bool estable;
  final String? hardware;

  const EstadoSesionBalanza({
    required this.idBalanza,
    required this.conectado,
    this.pesoKg,
    this.estable = false,
    this.hardware,
  });

  factory EstadoSesionBalanza.fromJson(Map<String, dynamic> json) =>
      EstadoSesionBalanza(
        idBalanza: '${json['id_balanza'] ?? ''}',
        conectado: json['conectado'] as bool? ?? false,
        pesoKg: (json['peso_kg'] as num?)?.toDouble(),
        estable: json['estable'] as bool? ?? false,
        hardware: json['hardware'] as String?,
      );
}
