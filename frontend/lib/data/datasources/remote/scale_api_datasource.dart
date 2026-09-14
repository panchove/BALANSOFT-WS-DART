import 'package:dio/dio.dart';

import '../../services/scale_tcp_client.dart';
import 'api_client.dart';

/// Errores tipados del HAL de balanza vía API.
class ScaleNotConfiguredException implements Exception {
  const ScaleNotConfiguredException();
}

class ScaleNotFoundException implements Exception {
  const ScaleNotFoundException();
}

class ScaleConnectionException implements Exception {
  const ScaleConnectionException(this.cause);

  final Object cause;

  @override
  String toString() => 'ScaleConnectionException: $cause';
}

/// Lee el peso en vivo desde el backend (HAL) en vez de TCP directo.
class ScaleApiDatasource {
  final ApiClient _api;

  const ScaleApiDatasource(this._api);

  Future<PesoEnVivo> readLive(String balanzaId) async {
    try {
      final data = await _api.readLiveWeight(balanzaId);
      return PesoEnVivo(
        pesoKg: (data['peso_kg'] as num?)?.toDouble(),
        estado: data['estable'] == true ? 'stable' : 'inestable',
        timestamp:
            DateTime.tryParse('${data['timestamp']}') ?? DateTime.now(),
        origin: 'API-${data['hardware'] ?? 'tcp'}',
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 400) throw const ScaleNotConfiguredException();
      if (status == 404) throw const ScaleNotFoundException();
      throw ScaleConnectionException(e);
    }
  }
}