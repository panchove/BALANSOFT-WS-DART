part of 'auth_bloc.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();
  @override
  List<Object?> get props => [];
}

class LoginEvent extends AuthEvent {
  final String email;
  final String password;
  final String? hardwareId;
  final String? deviceBrand;
  final String? deviceModel;
  final String? osVersion;
  final String? macAddress;

  const LoginEvent({
    required this.email,
    required this.password,
    this.hardwareId,
    this.deviceBrand,
    this.deviceModel,
    this.osVersion,
    this.macAddress,
  });

  @override
  List<Object?> get props =>
      [email, password, hardwareId, deviceBrand, deviceModel, osVersion, macAddress];
}

class RegisterEvent extends AuthEvent {
  final String empresaNombre;
  final String empresaRif;
  final String usuarioNombre;
  final String email;
  final String password;
  final String? licenciaKey;

  const RegisterEvent({
    required this.empresaNombre,
    required this.empresaRif,
    required this.usuarioNombre,
    required this.email,
    required this.password,
    this.licenciaKey,
  });

  @override
  List<Object?> get props =>
      [empresaNombre, empresaRif, usuarioNombre, email, password, licenciaKey];
}

class LogoutEvent extends AuthEvent {
  const LogoutEvent();
}

class CheckAuthStatusEvent extends AuthEvent {
  const CheckAuthStatusEvent();
}

/// Relee el perfil de la empresa y refresca el usuario en sesión (nombre, RIF,
/// dirección y logo) sin emitir `AuthLoading`.
///
/// Se dispara al guardar el perfil de empresa (o subir el logo) para que la UI
/// muestre los datos nuevos al instante, en lugar de seguir pidiendo el logo
/// anterior —que ya no existe en `media/`— hasta el siguiente login.
class RefreshCompanyEvent extends AuthEvent {
  const RefreshCompanyEvent();
}

class ForgotPasswordEvent extends AuthEvent {
  final String email;
  const ForgotPasswordEvent({required this.email});
  @override
  List<Object?> get props => [email];
}

class ResetPasswordEvent extends AuthEvent {
  final String token;
  final String newPassword;
  const ResetPasswordEvent({required this.token, required this.newPassword});
  @override
  List<Object?> get props => [token, newPassword];
}
