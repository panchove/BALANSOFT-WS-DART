import '../entities/user.dart';

/// Resultado del intento de restaurar la sesión guardada en el dispositivo.
enum SesionRestaurada {
  /// El refresh token es válido y el acceso quedó renovado (online).
  ok,

  /// No se pudo validar online pero hay red caída: se conserva la sesión
  /// (offline-first).
  offline,

  /// El refresh token fue rechazado (inválido/revocado): se limpia la sesión
  /// y se pide login de nuevo.
  invalida,
}

abstract class IAuthRepository {
  Future<User> login({
    required String email,
    required String password,
    String? hardwareId,
    String? deviceBrand,
    String? deviceModel,
    String? osVersion,
    String? macAddress,
  });

  Future<User> register({
    required String empresaNombre,
    required String empresaRif,
    required String usuarioNombre,
    required String email,
    required String password,
    String? licenciaKey,
  });

  Future<void> logout();
  Future<String> refreshToken(String refreshToken);
  Future<String?> refreshAccessToken();
  Future<void> forgotPassword(String email);
  Future<void> resetPassword(String token, String newPassword);
  Future<User?> getCachedUser();
  Future<SesionRestaurada> restoreSession();
  Future<void> cacheUser(User user);
  Future<void> clearCache();
}
