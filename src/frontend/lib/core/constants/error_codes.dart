class ErrorCodes {
  static const String networkError = 'NETWORK_ERROR';
  static const String unauthorized = 'UNAUTHORIZED';
  static const String forbidden = 'FORBIDDEN';
  static const String notFound = 'NOT_FOUND';
  static const String conflict = 'CONFLICT';
  static const String serverError = 'SERVER_ERROR';
  static const String licenseInvalid = 'LICENSE_INVALID';
  static const String licenseExpired = 'LICENSE_EXPIRED';
  static const String licenseLimitExceeded = 'LICENSE_LIMIT_EXCEEDED';
  static const String offlineMode = 'OFFLINE_MODE';
  static const String syncFailed = 'SYNC_FAILED';
  static const String validationError = 'VALIDATION_ERROR';

  static String messageFor(String code) {
    switch (code) {
      case networkError:
        return 'Error de conexión. Verifique su red.';
      case unauthorized:
        return 'Credenciales inválidas.';
      case forbidden:
        return 'No tiene permisos para esta acción.';
      case notFound:
        return 'Recurso no encontrado.';
      case conflict:
        return 'Conflicto con datos existentes.';
      case serverError:
        return 'Error del servidor. Intente más tarde.';
      case licenseInvalid:
        return 'Licencia inválida.';
      case licenseExpired:
        return 'Licencia expirada.';
      case licenseLimitExceeded:
        return 'Límite de licencia excedido.';
      case offlineMode:
        return 'Modo offline. Datos guardados localmente.';
      case syncFailed:
        return 'Error en sincronización.';
      case validationError:
        return 'Datos inválidos. Revise el formulario.';
      default:
        return 'Error desconocido.';
    }
  }
}
