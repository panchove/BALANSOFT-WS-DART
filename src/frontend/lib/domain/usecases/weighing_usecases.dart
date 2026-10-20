// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 17025 / OIML R 76-1 / ISO/IEC 25010
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

import '../entities/weighing.dart';
import '../repositories/i_weighing_repository.dart';

/// Caso de uso para registrar una pesada inicial en la estación de pesaje.
class CreateWeighingUseCase {
  final IWeighingRepository _repo;
  CreateWeighingUseCase(this._repo);

  /// Ejecuta la creación del pesaje inicial.
  ///
  /// Precondiciones:
  /// - `weighing.pesoEntradaVehiculo >= 0`.
  ///
  /// Poscondiciones:
  /// - Retorna [Weighing] persistido en estado `PENDIENTE`.
  Future<Weighing> execute(
      Weighing weighing, [Map<String, dynamic>? adicionales]) {
    return _repo.createWeighing(weighing, adicionales: adicionales);
  }
}

/// Caso de uso para cerrar un boleto de pesaje pendiente capturando la pesada de salida.
class CloseWeighingUseCase {
  final IWeighingRepository _repo;
  CloseWeighingUseCase(this._repo);

  /// Ejecuta el cierre del boleto calculando el peso neto final.
  ///
  /// Precondiciones:
  /// - [boleto] debe existir y estar en estado `PENDIENTE`.
  /// - [closeData] contiene el peso de salida válido.
  ///
  /// Poscondiciones:
  /// - Retorna [Weighing] en estado `CERRADO`.
  Future<Weighing> execute(String boleto, Map<String, dynamic> closeData) {
    return _repo.closeWeighing(boleto, closeData);
  }
}

/// Caso de uso para anular un boleto de pesaje registrando justificación mandatoria.
class AnularWeighingUseCase {
  final IWeighingRepository _repo;
  AnularWeighingUseCase(this._repo);

  /// Ejecuta la anulación del boleto.
  ///
  /// Precondiciones:
  /// - [motivo] no vacío (mínimo 5 caracteres para auditoría según ISO/IEC 17025).
  ///
  /// Poscondiciones:
  /// - Retorna [Weighing] en estado `ANULADO`.
  Future<Weighing> execute(String boleto, String motivo) {
    return _repo.anularWeighing(boleto, motivo);
  }
}

/// Caso de uso para consultar un boleto de pesaje individual por identificador.
class GetWeighingUseCase {
  final IWeighingRepository _repo;
  GetWeighingUseCase(this._repo);

  /// Ejecuta la búsqueda del boleto por identificador o número.
  Future<Weighing?> execute(String boleto) {
    return _repo.getWeighingByBoleto(boleto);
  }
}

/// Caso de uso para listar boletos con filtrado y paginación.
class ListWeighingsUseCase {
  final IWeighingRepository _repo;
  ListWeighingsUseCase(this._repo);

  /// Ejecuta la consulta paginada de boletos.
  Future<List<Weighing>> execute({
    int skip = 0,
    int limit = 100,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? vehicleId,
    String? estado,
  }) {
    return _repo.listWeighings(
      skip: skip,
      limit: limit,
      dateFrom: dateFrom,
      dateTo: dateTo,
      vehicleId: vehicleId,
      estado: estado,
    );
  }
}

/// Caso de uso para sincronizar boletos pendientes capturados en modo offline.
class SyncWeighingsUseCase {
  final IWeighingRepository _repo;
  SyncWeighingsUseCase(this._repo);

  /// Ejecuta la sincronización hacia el servidor central.
  ///
  /// Poscondiciones:
  /// - Retorna el número de boletos sincronizados con éxito.
  Future<int> execute() async {
    final pending = await _repo.getPendingWeighings();
    int synced = 0;
    for (final w in pending) {
      try {
        await _repo.pushWeighing(w);
        synced++;
      } catch (_) {
        await _repo.incrementSyncAttempt(w.boleto);
      }
    }
    return synced;
  }
}

/// Caso de uso para obtener el conteo de boletos pendientes de sincronización.
class GetPendingWeighingsCountUseCase {
  final IWeighingRepository _repo;
  GetPendingWeighingsCountUseCase(this._repo);

  /// Retorna el número de boletos pendientes de subida.
  Future<int> execute() async {
    final pending = await _repo.getPendingWeighings();
    return pending.length;
  }
}

/// Caso de uso para obtener la lista de boletos cuya sincronización ha fallado reiteradamente.
class GetFailedWeighingsUseCase {
  final IWeighingRepository _repo;
  GetFailedWeighingsUseCase(this._repo);

  /// Retorna los boletos fallidos en sincronización.
  Future<List<Weighing>> execute() => _repo.getFailedWeighings();
}

/// Caso de uso para obtener la cantidad de boletos en estado fallido de sincronización.
class GetFailedWeighingsCountUseCase {
  final IWeighingRepository _repo;
  GetFailedWeighingsCountUseCase(this._repo);

  /// Retorna el número de boletos con fallas de sincronización.
  Future<int> execute() async {
    final failed = await _repo.getFailedWeighings();
    return failed.length;
  }
}
