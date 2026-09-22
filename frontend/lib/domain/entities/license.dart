class License {
  final bool valid;
  final String? status;
  final String? tier;
  final String? planType;
  final DateTime? expiresAt;
  final Map<String, dynamic> features;
  final String? message;

  const License({
    required this.valid,
    this.status,
    this.tier,
    this.planType,
    this.expiresAt,
    this.features = const {},
    this.message,
  });

  bool get isDemo => (tier ?? '').toUpperCase() == 'DEMO';
  bool get isMonopuesta {
    final t = (tier ?? '').toUpperCase();
    return t == 'MONOPUESTA' || t == 'MONOPUESTO';
  }
  bool get isCentral => (tier ?? '').toUpperCase() == 'CENTRAL';

  int get maxRecords => features['max_registros'] ?? 10;
  int get maxSessions => features['max_sesiones'] ?? 1;

  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  bool get isValidAndActive => valid && !isExpired;

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
