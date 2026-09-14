class User {
  final String idUsuario;
  final String nombre;
  final String email;
  final String rol;
  final String? idEmpresa;

  const User({
    required this.idUsuario,
    required this.nombre,
    required this.email,
    required this.rol,
    this.idEmpresa,
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
      );

  Map<String, dynamic> toJson() => {
        'id_usuario': idUsuario,
        'nombre': nombre,
        'email': email,
        'rol': rol,
        'id_empresa': idEmpresa,
      };
}
