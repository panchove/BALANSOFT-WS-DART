import '../entities/user.dart';

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
  Future<void> restoreSession();
  Future<void> cacheUser(User user);
  Future<void> clearCache();
}
