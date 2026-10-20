// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 25010 / ISO/IEC 27001
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

/// Entidad representativa de un usuario autenticado en la estación de pesaje.
///
/// Encapsula la identidad, roles de seguridad (ADMIN, SUPERVISOR, OPERADOR) y metadatos
/// de la empresa según ISO/IEC 27001 (control de acceso y principio de menor privilegio).
class User {
  final String idUsuario;
  final String nombre;
  final String email;
  final String rol;
  final String? idEmpresa;
  final String? logoUrl; // URL del logo de la empresa (desde backend)

  // ── Datos de la empresa (vienen en la respuesta del login) ──
  final String? empresaNombre;
  final String? empresaRif;
  final String? empresaDireccion;

  /// Crea una instancia inmutable de [User].
  const User({
    required this.idUsuario,
    required this.nombre,
    required this.email,
    required this.rol,
    this.idEmpresa,
    this.logoUrl,
    this.empresaNombre,
    this.empresaRif,
    this.empresaDireccion,
  });

  /// Determina si el usuario posee privilegios totales de administración.
  bool get isAdmin => rol == 'ADMIN';

  /// Determina si el usuario posee rol de supervisión de planta o estación.
  bool get isSupervisor => rol == 'SUPERVISOR';

  /// Determina si el usuario posee permisos de pesaje y despacho operativo.
  bool get isOperador => rol == 'OPERADOR';

  /// Construye un [User] deserializando el payload de respuesta de autenticación.
  ///
  /// Poscondiciones:
  /// - Mapea campos de usuario y perfil de tenant empresarial.
  factory User.fromJson(Map<String, dynamic> json) => User(
        idUsuario: json['id_usuario'],
        nombre: json['nombre'],
        email: json['email'],
        rol: json['rol'],
        idEmpresa: json['id_empresa'],
        logoUrl: json['logo_url'],
        empresaNombre: json['empresa_nombre'],
        empresaRif: json['empresa_rif'],
        empresaDireccion: json['empresa_direccion'],
      );

  /// Serializa la entidad a un mapa JSON para almacenamiento en caché segura local.
  Map<String, dynamic> toJson() => {
        'id_usuario': idUsuario,
        'nombre': nombre,
        'email': email,
        'rol': rol,
        'id_empresa': idEmpresa,
        'logo_url': logoUrl,
        'empresa_nombre': empresaNombre,
        'empresa_rif': empresaRif,
        'empresa_direccion': empresaDireccion,
      };
}