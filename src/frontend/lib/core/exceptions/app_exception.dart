class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  AppException(this.message, {this.code, this.originalError});

  @override
  String toString() => 'AppException($code): $message';
}

class NetworkException extends AppException {
  NetworkException([super.message = 'Error de conexión'])
      : super(code: 'NETWORK_ERROR');
}

class AuthException extends AppException {
  AuthException([super.message = 'No autenticado'])
      : super(code: 'UNAUTHORIZED');
}

class LicenseException extends AppException {
  LicenseException([super.message = 'Licencia inválida'])
      : super(code: 'LICENSE_INVALID');
}

class LicenseLimitException extends AppException {
  final int limit;
  LicenseLimitException(this.limit)
      : super('Límite de $limit registros excedido', code: 'LICENSE_LIMIT_EXCEEDED');
}

class ValidationException extends AppException {
  ValidationException(super.message) : super(code: 'VALIDATION_ERROR');
}

class OfflineException extends AppException {
  OfflineException([super.message = 'Sin conexión. Datos guardados localmente.'])
      : super(code: 'OFFLINE_MODE');
}

class SyncException extends AppException {
  SyncException([super.message = 'Error en sincronización'])
      : super(code: 'SYNC_FAILED');
}

class CacheException extends AppException {
  CacheException([super.message = 'Error de caché'])
      : super(code: 'CACHE_ERROR');
}
