// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 27001 / ISO/IEC 25010
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

import '../entities/user.dart';
import '../repositories/i_auth_repository.dart';

/// Caso de uso para la autenticación de usuarios y validación de hardware.
class LoginUseCase {
  final IAuthRepository _repo;
  LoginUseCase(this._repo);

  /// Ejecuta el proceso de inicio de sesión.
  ///
  /// Precondiciones:
  /// - [email] y [password] no vacíos.
  ///
  /// Poscondiciones:
  /// - Retorna la entidad [User] autenticada.
  Future<User> execute({
    required String email,
    required String password,
    String? hardwareId,
    String? deviceBrand,
    String? deviceModel,
    String? osVersion,
    String? macAddress,
  }) {
    return _repo.login(
      email: email,
      password: password,
      hardwareId: hardwareId,
      deviceBrand: deviceBrand,
      deviceModel: deviceModel,
      osVersion: osVersion,
      macAddress: macAddress,
    );
  }
}

/// Caso de uso para registrar una nueva cuenta de empresa y usuario administrador inicial.
class RegisterUseCase {
  final IAuthRepository _repo;
  RegisterUseCase(this._repo);

  /// Ejecuta el aprovisionamiento de la empresa y cuenta principal.
  ///
  /// Precondiciones:
  /// - Datos fiscales [empresaNombre] y [empresaRif] válidos.
  /// - Credenciales de acceso no vacías.
  Future<User> execute({
    required String empresaNombre,
    required String empresaRif,
    required String usuarioNombre,
    required String email,
    required String password,
    String? licenciaKey,
  }) {
    return _repo.register(
      empresaNombre: empresaNombre,
      empresaRif: empresaRif,
      usuarioNombre: usuarioNombre,
      email: email,
      password: password,
      licenciaKey: licenciaKey,
    );
  }
}

/// Caso de uso para cerrar la sesión local e invalidar credenciales.
class LogoutUseCase {
  final IAuthRepository _repo;
  LogoutUseCase(this._repo);

  /// Ejecuta el cierre de sesión seguro.
  Future<void> execute() => _repo.logout();
}

/// Caso de uso para recuperar el usuario autenticado desde el almacenamiento seguro local.
class GetCachedUserUseCase {
  final IAuthRepository _repo;
  GetCachedUserUseCase(this._repo);

  /// Ejecuta la recuperación del usuario en caché.
  Future<User?> execute() => _repo.getCachedUser();
}

/// Caso de uso para validar y restaurar la sesión persistida al iniciar la aplicación.
class RestoreSessionUseCase {
  final IAuthRepository _repo;
  RestoreSessionUseCase(this._repo);

  /// Ejecuta el chequeo de validez del token y restauración de la sesión.
  Future<SesionRestaurada> execute() => _repo.restoreSession();
}

/// Relee la empresa del perfil (`GET /api/v1/empresa`) y la aplica al usuario
/// cacheado. Se usa tras guardar el perfil de empresa para que la UI refresque
/// nombre, RIF, dirección y logo sin obligar a reloguearse.
class RefrescarEmpresaUseCase {
  final IAuthRepository _repo;
  RefrescarEmpresaUseCase(this._repo);

  /// Ejecuta la sincronización del perfil empresarial en la sesión local.
  Future<User?> execute() => _repo.refrescarEmpresaEnUsuarioCacheado();
}

/// Caso de uso para solicitar el envío de correo de recuperación de contraseña.
class ForgotPasswordUseCase {
  final IAuthRepository _repo;
  ForgotPasswordUseCase(this._repo);

  /// Ejecuta el envío de la solicitud de restablecimiento para [email].
  Future<void> execute(String email) => _repo.forgotPassword(email);
}

/// Caso de uso para reestablecer la contraseña utilizando un token recibido por correo.
class ResetPasswordUseCase {
  final IAuthRepository _repo;
  ResetPasswordUseCase(this._repo);

  /// Ejecuta el cambio de contraseña asignando [newPassword] mediante [token].
  Future<void> execute(String token, String newPassword) =>
      _repo.resetPassword(token, newPassword);
}
