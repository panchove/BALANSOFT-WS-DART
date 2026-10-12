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

  bool get isAdmin => rol == 'ADMIN';
  bool get isSupervisor => rol == 'SUPERVISOR';
  bool get isOperador => rol == 'OPERADOR';

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