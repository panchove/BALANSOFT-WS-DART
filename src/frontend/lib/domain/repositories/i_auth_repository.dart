// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 27001 / ISO/IEC 25010
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

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

/// Contrato del repositorio de autenticación y gestión de sesiones.
///
/// Implementa los controles de acceso y credenciales bajo ISO/IEC 27001 / ISO/IEC 25010.
abstract class IAuthRepository {
  /// Autentica a un usuario mediante credenciales y hardware de la estación.
  ///
  /// Precondiciones:
  /// - [email] debe ser una dirección de correo no vacía y con formato válido.
  /// - [password] no debe ser vacía.
  ///
  /// Poscondiciones:
  /// - Retorna una entidad [User] con tokens JWT y datos de la empresa vinculada.
  /// - Persiste la sesión en almacenamiento seguro local si la autenticación es exitosa.
  ///
  /// Lanza [Exception] o errores de red si las credenciales son inválidas o la estación está inalcanzable.
  Future<User> login({
    required String email,
    required String password,
    String? hardwareId,
    String? deviceBrand,
    String? deviceModel,
    String? osVersion,
    String? macAddress,
  });

  /// Registra una nueva empresa y su usuario administrador inicial.
  ///
  /// Precondiciones:
  /// - [empresaNombre] y [empresaRif] no deben ser vacíos.
  /// - [usuarioNombre], [email] y [password] requeridos para el usuario principal.
  ///
  /// Poscondiciones:
  /// - Retorna el [User] administrador creado y activo.
  Future<User> register({
    required String empresaNombre,
    required String empresaRif,
    required String usuarioNombre,
    required String email,
    required String password,
    String? licenciaKey,
  });

  /// Cierra la sesión activa actual y limpia credenciales seguras.
  ///
  /// Poscondiciones:
  /// - Invalida tokens en servidor y elimina estado en almacenamiento seguro.
  Future<void> logout();

  /// Renueva el token de acceso utilizando un refresh token específico.
  ///
  /// Precondiciones:
  /// - [refreshToken] debe ser un JWT válido y no expirado.
  ///
  /// Poscondiciones:
  /// - Retorna el nuevo access token JWT como [String].
  Future<String> refreshToken(String refreshToken);

  /// Renueva el access token a partir del refresh token almacenado localmente.
  ///
  /// Poscondiciones:
  /// - Retorna el nuevo token o `null` si no hay token o falló la renovación.
  Future<String?> refreshAccessToken();

  /// Solicita el restablecimiento de contraseña para el correo especificado.
  ///
  /// Precondiciones:
  /// - [email] debe ser una dirección de correo válida.
  Future<void> forgotPassword(String email);

  /// Restablece la contraseña de usuario utilizando un token de recuperación.
  ///
  /// Precondiciones:
  /// - [token] no debe estar expirado.
  /// - [newPassword] debe cumplir con la política de seguridad mínima de longitud.
  Future<void> resetPassword(String token, String newPassword);

  /// Obtiene el usuario autenticado actualmente almacenado en caché local.
  ///
  /// Poscondiciones:
  /// - Retorna [User] si existe sesión guardada, o `null` si no hay sesión activa.
  Future<User?> getCachedUser();

  /// Restaura la sesión guardada en el dispositivo validándola de forma online u offline.
  ///
  /// Poscondiciones:
  /// - Retorna [SesionRestaurada.ok] si se renovó exitosamente online.
  /// - Retorna [SesionRestaurada.offline] si no hay red pero el token previo permite operación offline.
  /// - Retorna [SesionRestaurada.invalida] si el token fue rechazado o revocado.
  Future<SesionRestaurada> restoreSession();

  /// Relee el perfil de la empresa (`GET /api/v1/empresa`) y lo aplica al
  /// [User] cacheado (nombre, RIF, dirección y logo).
  ///
  /// Devuelve el usuario actualizado, o `null` si no hay sesión o la lectura
  /// falló (no es crítico: el usuario cacheado conserva los datos anteriores).
  /// Se usa tras guardar el perfil de empresa para que la UI deje de mostrar
  /// —y de pedir— el logo anterior, sin obligar a reloguearse.
  Future<User?> refrescarEmpresaEnUsuarioCacheado();

  /// Persiste la entidad [User] en el almacenamiento seguro local.
  ///
  /// Precondiciones:
  /// - [user] debe contener tokens y datos de empresa consistentes.
  Future<void> cacheUser(User user);

  /// Limpia todo el almacenamiento seguro de sesión y credenciales.
  Future<void> clearCache();
}
