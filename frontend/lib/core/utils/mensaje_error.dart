import 'package:dio/dio.dart';

const _sinConexion =
    'No se pudo conectar con el servidor. Revisa la conexión e inténtalo de nuevo.';

/// Extrae un mensaje legible para el usuario desde una excepción.
///
/// El backend FastAPI responde los errores HTTP con JSON `{"detail": "..."}`;
/// con DioException se aprovecha ese detalle (p.ej. `Credenciales inválidas`)
/// en lugar de mostrar el texto técnico de la librería.
String mensajeDeError(Object e, {String? fallback}) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map && data['detail'] is String) {
      final detalle = (data['detail'] as String).trim();
      if (detalle.isNotEmpty) return detalle;
    }
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return _sinConexion;
      case DioExceptionType.unknown:
        if (e.response == null) return _sinConexion;
        break;
      default:
        break;
    }
  }
  return fallback ?? 'Ocurrió un error inesperado. Inténtalo de nuevo.';
}

/// `true` si la excepción es el 403 de RB-12: el equipo no está aprobado
/// (pendiente o rechazado) y por eso el servidor central no le abre sesión.
///
/// Se usa en el login para distinguirlo del 403 del titular de la licencia:
/// aquí la solución es que la tutora apruebe el equipo, no reasignar hardware.
bool esErrorEquipoSinAprobar(Object e) {
  if (e is! DioException || e.response?.statusCode != 403) return false;
  final data = e.response?.data;
  if (data is! Map) return false;
  final detalle = '${data['detail'] ?? ''}'.toLowerCase();
  return detalle.contains('pendiente de aprobación') ||
      detalle.contains('rechazado por el administrador');
}

/// Extrae del 403 del login-central el hardware/equipo titular de la licencia
/// para que la UI pueda mostrar un mensaje accionable (reasignar titular).
///
/// Devuelve `null` en `hardwareTitular` si el error no es un 403 de titular.
({String mensaje, String? hardwareTitular, String? nombreEquipoTitular})
    parsearErrorTitular(Object e, {String? fallback}) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map) {
      final hw = data['hardware_titular'];
      final nombre = data['nombre_equipo_titular'];
      final detalle = (data['detail'] as String?)?.trim() ?? '';
      if (hw is String && hw.isNotEmpty) {
        return (
          mensaje: detalle.isNotEmpty ? detalle : (fallback ?? ''),
          hardwareTitular: hw,
          nombreEquipoTitular:
              (nombre is String && nombre.isNotEmpty) ? nombre : null,
        );
      }
    }
  }
  return (
    mensaje: mensajeDeError(e, fallback: fallback),
    hardwareTitular: null,
    nombreEquipoTitular: null,
  );
}