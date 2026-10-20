// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 27001 / ISO/IEC 25010
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

/// Entidad representativa de la licencia de uso de la estación de pesaje.
///
/// Modela los niveles de suscripción (DEMO, MONOPUESTA, CENTRAL), límites de concurrencia
/// y vigencia temporal según ISO/IEC 27001 y las especificaciones del License Manager (LM).
class License {
  final bool valid;
  final String? status;
  final String? tier;
  final String? planType;
  final DateTime? expiresAt;
  final Map<String, dynamic> features;
  final String? message;

  /// Crea una instancia inmutable de [License].
  const License({
    required this.valid,
    this.status,
    this.tier,
    this.planType,
    this.expiresAt,
    this.features = const {},
    this.message,
  });

  /// Indica si la licencia corresponde al tier demostrativo (DEMO, máximo 3 sesiones locales).
  bool get isDemo => (tier ?? '').toUpperCase() == 'DEMO';

  /// Indica si la licencia es monopuesto para una única estación local.
  bool get isMonopuesta {
    final t = (tier ?? '').toUpperCase();
    return t == 'MONOPUESTA' || t == 'MONOPUESTO';
  }

  /// Indica si la licencia corresponde a una central de sincronización multi-estación.
  bool get isCentral => (tier ?? '').toUpperCase() == 'CENTRAL';

  /// Límite máximo de registros históricos o boletos permitidos según el plan.
  int get maxRecords => features['max_registros'] ?? 10;

  /// Límite máximo de sesiones simultáneas permitidas para esta instalación.
  int get maxSessions => features['max_sesiones'] ?? 1;

  /// Determina si la licencia ha sobrepasado su fecha de expiración.
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  /// Determina si la licencia es válida criptográficamente y no se encuentra expirada.
  bool get isValidAndActive => valid && !isExpired;

  /// Construye una [License] a partir del payload JSON retornado por el LM o el WServer.
  factory License.fromJson(Map<String, dynamic> json) => License(
        valid: json['valid'] ?? false,
        status: json['status'],
        tier: json['tier'],
        planType: json['plan_type'],
        expiresAt: json['expires_at'] != null
            ? DateTime.tryParse(json['expires_at'])
            : null,
        features: json['features'] ?? {},
        message: json['message'],
      );

  /// Serializa la entidad de licencia para almacenamiento persistente en caché local segura.
  Map<String, dynamic> toJson() => {
        'valid': valid,
        'status': status,
        'tier': tier,
        'plan_type': planType,
        'expires_at': expiresAt?.toIso8601String(),
        'features': features,
        'message': message,
      };
}
