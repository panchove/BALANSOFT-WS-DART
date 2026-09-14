class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  AppException(this.message, {this.code, this.originalError});

  @override
  String toString() => 'AppException($code): $message';
}

class NetworkException extends AppException {
  NetworkException([String message = 'Error de conexión'])
      : super(message, code: 'NETWORK_ERROR');
}

class AuthException extends AppException {
  AuthException([String message = 'No autenticado'])
      : super(message, code: 'UNAUTHORIZED');
}

class LicenseException extends AppException {
  LicenseException([String message = 'Licencia inválida'])
      : super(message, code: 'LICENSE_INVALID');
}

class LicenseLimitException extends AppException {
  final int limit;
  LicenseLimitException(this.limit)
      : super('Límite de $limit registros excedido', code: 'LICENSE_LIMIT_EXCEEDED');
}

class ValidationException extends AppException {
  ValidationException(String message) : super(message, code: 'VALIDATION_ERROR');
}

class OfflineException extends AppException {
  OfflineException([String message = 'Sin conexión. Datos guardados localmente.'])
      : super(message, code: 'OFFLINE_MODE');
}

class SyncException extends AppException {
  SyncException([String message = 'Error en sincronización'])
      : super(message, code: 'SYNC_FAILED');
}

class CacheException extends AppException {
  CacheException([String message = 'Error de caché'])
      : super(message, code: 'CACHE_ERROR');
}
