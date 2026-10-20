// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 17025 / OIML R 76-1 / ISO/IEC 25010
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

import 'package:dio/dio.dart';
import '../entities/boleto_edicion.dart';
import '../entities/weighing.dart';

/// Se lanza al intentar editar un boleto **sin conexión**.
///
/// La edición exige justificación, respeta el tope por boleto y deja historial
/// inmutable con el usuario, la fecha y la IP: eso solo lo puede garantizar el
/// backend. La rama offline del repositorio persiste un subconjunto de campos
/// sin ninguna de esas garantías, así que se rechaza en vez de saltarse la
/// regla de negocio (y la auditoría) en silencio.
class EdicionRequiereConexionException implements Exception {
  const EdicionRequiereConexionException();

  @override
  String toString() => 'edit_ticket_needs_connection';
}

/// Contrato del repositorio de pesajes de la estación BALANSOFT-WS.
///
/// Gestiona la persistencia de boletos, pesadas de entrada y salida, sincronización
/// offline y emisión de tickets según las normas ISO/IEC 17025 y OIML R 76-1.
abstract class IWeighingRepository {
  /// Registra una pesada inicial en la estación.
  ///
  /// Precondiciones:
  /// - `weighing.pesoEntradaVehiculo` >= 0.
  /// - La balanza debe reportar peso estable antes de llamar a este método.
  ///
  /// Poscondiciones:
  /// - Retorna el [Weighing] persistido en estado `PENDIENTE`.
  Future<Weighing> createWeighing(
    Weighing weighing, {
    bool online = true,
    Map<String, dynamic>? adicionales,
  });

  /// Cierra un boleto de pesaje pendiente capturando el peso de salida.
  ///
  /// Precondiciones:
  /// - El boleto debe existir y encontrarse en estado `PENDIENTE`.
  /// - `closeData` debe incluir `peso_salida_vehiculo` válido.
  ///
  /// Poscondiciones:
  /// - El boleto pasa a estado `CERRADO` y se calcula el peso neto inmutable.
  Future<Weighing> closeWeighing(
      String boleto, Map<String, dynamic> closeData);

  /// Obtiene un boleto específico por su UUID o número de boleto.
  Future<Weighing?> getWeighingByBoleto(String boleto);

  /// Lista boletos con soporte de paginación y filtros de auditoría.
  Future<List<Weighing>> listWeighings({
    int skip = 0,
    int limit = 100,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? vehicleId,
    String? estado,
  });

  /// Modifica campos permitidos de un boleto cerrado.
  ///
  /// Precondiciones:
  /// - Exige conexión activa con el backend para garantizar auditoría inmutable.
  ///
  /// Lanza:
  /// - [EdicionRequiereConexionException] si se intenta ejecutar offline.
  Future<Weighing> updateWeighing(String boleto, Map<String, dynamic> data);

  /// Historial de ediciones inmutables del boleto (más reciente primero).
  Future<List<BoletoEdicion>> getEdiciones(String boleto);

  /// Anula un boleto de pesaje registrando el motivo justificado.
  ///
  /// Poscondiciones:
  /// - Si el boleto tenía movimiento Kardex 10 o 60, se emite contrasiento automático.
  Future<Weighing> anularWeighing(String boleto, String motivo);

  /// Devuelve la lista de boletos pendientes de segunda pesada.
  Future<List<Weighing>> listPendientes();

  /// Solicita el documento PDF del boleto según el formato canónico de 5 columnas.
  Future<Response> getTicketPdf(
    String boleto, {
    int copias = 1,
    String tamanoPapel = 'Letter',
    String orientacion = 'portrait',
    bool mostrarEncabezado = true,
    bool mostrarDetalles = true,
  });

  /// Solicita el ticket de texto plano para impresoras térmicas ESC/POS o matriciales.
  Future<Response> getTicketTxt(String boleto);

  /// Devuelve el contador de boletos registrados en el día calendario actual.
  Future<int> countWeighingsToday();

  /// Obtiene la cola de boletos pendientes de sincronizar con el servidor central.
  Future<List<Weighing>> getPendingWeighings();

  /// Marca un boleto como sincronizado exitosamente en la base de datos local SQLite.
  Future<int> markAsSynced(String boleto);

  /// Envía un pesaje local hacia la nube o servidor central.
  Future<void> pushWeighing(Weighing weighing);

  /// Incrementa el contador de reintentos fallidos de sincronización.
  Future<int> incrementSyncAttempt(String boleto);

  /// Devuelve los boletos que han superado el umbral de reintentos de sincronización.
  Future<List<Weighing>> getFailedWeighings();
}
