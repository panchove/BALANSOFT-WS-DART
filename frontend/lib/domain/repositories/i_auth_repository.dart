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

  Future<void> logout();
  Future<String> refreshToken(String refreshToken);
  Future<String?> refreshAccessToken();
  Future<void> forgotPassword(String email);
  Future<void> resetPassword(String token, String newPassword);
  Future<User?> getCachedUser();
  Future<SesionRestaurada> restoreSession();

  /// Crea la empresa y el primer usuario ADMIN en la estación (setup inicial).
  ///
  /// Llama a `POST /api/v1/setup/crear-admin`, guarda los tokens y devuelve
  /// `true` si la cuenta se creó exitosamente.
  Future<bool> setupCrearAdmin(Map<String, dynamic> data);

  /// Relee el perfil de la empresa (`GET /api/v1/empresa`) y lo aplica al
  /// [User] cacheado (nombre, RIF, dirección y logo).
  ///
  /// Devuelve el usuario actualizado, o `null` si no hay sesión o la lectura
  /// falló (no es crítico: el usuario cacheado conserva los datos anteriores).
  /// Se usa tras guardar el perfil de empresa para que la UI deje de mostrar
  /// —y de pedir— el logo anterior, sin obligar a reloguearse.
  Future<User?> refrescarEmpresaEnUsuarioCacheado();

  Future<void> cacheUser(User user);
  Future<void> clearCache();
}
