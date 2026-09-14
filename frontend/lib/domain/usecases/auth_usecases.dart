import '../entities/user.dart';
import '../repositories/i_auth_repository.dart';

class LoginUseCase {
  final IAuthRepository _repo;
  LoginUseCase(this._repo);

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

class RegisterUseCase {
  final IAuthRepository _repo;
  RegisterUseCase(this._repo);

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

class LogoutUseCase {
  final IAuthRepository _repo;
  LogoutUseCase(this._repo);

  Future<void> execute() => _repo.logout();
}

class GetCachedUserUseCase {
  final IAuthRepository _repo;
  GetCachedUserUseCase(this._repo);

  Future<User?> execute() => _repo.getCachedUser();
}

class RestoreSessionUseCase {
  final IAuthRepository _repo;
  RestoreSessionUseCase(this._repo);

  Future<void> execute() => _repo.restoreSession();
}

class ForgotPasswordUseCase {
  final IAuthRepository _repo;
  ForgotPasswordUseCase(this._repo);

  Future<void> execute(String email) => _repo.forgotPassword(email);
}

class ResetPasswordUseCase {
  final IAuthRepository _repo;
  ResetPasswordUseCase(this._repo);

  Future<void> execute(String token, String newPassword) =>
      _repo.resetPassword(token, newPassword);
}
