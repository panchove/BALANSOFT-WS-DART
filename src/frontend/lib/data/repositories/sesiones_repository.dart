// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 25010 / ISO/IEC 27001
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

import '../../domain/entities/sesion_equipo.dart';
import '../datasources/remote/api_client.dart';

/// Repositorio de RB-12 (aprobación de equipos de la cuenta).
///
/// A diferencia del resto de repositorios, la autoridad es el **servidor
/// central**, no la estación: usa la credencial global (`_serverToken`,
/// obtenida en el login central-first) y no persiste nada localmente. Si no
/// hay credencial (sesión local antigua, o login offline), el `ApiClient`
/// lanza [StateError] y la pantalla pide volver a iniciar sesión.
class SesionesRepository {
  final ApiClient _apiClient;

  SesionesRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  /// Equipos de la cuenta con su estado de aprobación (ADMIN global).
  Future<SesionesEquipo> listar() async {
    return SesionesEquipo.fromJson(await _apiClient.listarSesionesEquipo());
  }

  /// Aprueba/rechaza un equipo y/o le asigna su rol de sesión.
  Future<SesionEquipo> actualizar(
    String idDispositivo, {
    String? estado,
    String? rolSesion,
  }) async {
    final json = await _apiClient.actualizarSesionEquipo(
      idDispositivo,
      estado: estado,
      rolSesion: rolSesion,
    );
    return SesionEquipo.fromJson(json);
  }
}
