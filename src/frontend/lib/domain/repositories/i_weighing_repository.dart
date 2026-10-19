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

abstract class IWeighingRepository {
  Future<Weighing> createWeighing(
    Weighing weighing, {
    bool online = true,
    Map<String, dynamic>? adicionales,
  });
  Future<Weighing> closeWeighing(
      String boleto, Map<String, dynamic> closeData);
  Future<Weighing?> getWeighingByBoleto(String boleto);
  Future<List<Weighing>> listWeighings({
    int skip = 0,
    int limit = 100,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? vehicleId,
    String? estado,
  });
  Future<Weighing> updateWeighing(String boleto, Map<String, dynamic> data);
  /// Historial de ediciones del boleto (más reciente primero).
  Future<List<BoletoEdicion>> getEdiciones(String boleto);
  Future<Weighing> anularWeighing(String boleto, String motivo);
  Future<List<Weighing>> listPendientes();
  Future<Response> getTicketPdf(
    String boleto, {
    int copias = 1,
    String tamanoPapel = 'Letter',
    String orientacion = 'portrait',
    bool mostrarEncabezado = true,
    bool mostrarDetalles = true,
  });
  Future<Response> getTicketTxt(String boleto);
  Future<int> countWeighingsToday();
  Future<List<Weighing>> getPendingWeighings();
  Future<int> markAsSynced(String boleto);
  Future<void> pushWeighing(Weighing weighing);
  Future<int> incrementSyncAttempt(String boleto);
  Future<List<Weighing>> getFailedWeighings();
}
