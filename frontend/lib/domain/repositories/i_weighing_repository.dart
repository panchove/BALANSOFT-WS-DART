import 'package:dio/dio.dart';
import '../entities/weighing.dart';

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
  Future<Weighing> anularWeighing(String boleto, String motivo);
  Future<List<Weighing>> listPendientes();
  Future<Response> getTicketPdf(String boleto);
  Future<int> countWeighingsToday();
  Future<List<Weighing>> getPendingWeighings();
  Future<int> markAsSynced(String boleto);
  Future<void> pushWeighing(Weighing weighing);
  Future<int> incrementSyncAttempt(String boleto);
  Future<List<Weighing>> getFailedWeighings();
}
