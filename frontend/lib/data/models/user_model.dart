import '../../domain/entities/user.dart';

class UserModel extends User {
  const UserModel({
    required super.idUsuario,
    required super.nombre,
    required super.email,
    required super.rol,
    super.idEmpresa,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        idUsuario: json['id_usuario'],
        nombre: json['nombre'],
        email: json['email'],
        rol: json['rol'],
        idEmpresa: json['id_empresa'],
      );

  factory UserModel.fromEntity(User user) => UserModel(
        idUsuario: user.idUsuario,
        nombre: user.nombre,
        email: user.email,
        rol: user.rol,
        idEmpresa: user.idEmpresa,
      );
}
