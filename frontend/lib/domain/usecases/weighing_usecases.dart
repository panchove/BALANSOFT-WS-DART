import '../entities/weighing.dart';
import '../repositories/i_weighing_repository.dart';

class CreateWeighingUseCase {
  final IWeighingRepository _repo;
  CreateWeighingUseCase(this._repo);

  Future<Weighing> execute(
      Weighing weighing, [Map<String, dynamic>? adicionales]) {
    return _repo.createWeighing(weighing, adicionales: adicionales);
  }
}

class CloseWeighingUseCase {
  final IWeighingRepository _repo;
  CloseWeighingUseCase(this._repo);

  Future<Weighing> execute(String boleto, Map<String, dynamic> closeData) {
    return _repo.closeWeighing(boleto, closeData);
  }
}

class AnularWeighingUseCase {
  final IWeighingRepository _repo;
  AnularWeighingUseCase(this._repo);

  Future<Weighing> execute(String boleto, String motivo) {
    return _repo.anularWeighing(boleto, motivo);
  }
}

class GetWeighingUseCase {
  final IWeighingRepository _repo;
  GetWeighingUseCase(this._repo);

  Future<Weighing?> execute(String boleto) {
    return _repo.getWeighingByBoleto(boleto);
  }
}

class ListWeighingsUseCase {
  final IWeighingRepository _repo;
  ListWeighingsUseCase(this._repo);

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

class SyncWeighingsUseCase {
  final IWeighingRepository _repo;
  SyncWeighingsUseCase(this._repo);

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

class GetPendingWeighingsCountUseCase {
  final IWeighingRepository _repo;
  GetPendingWeighingsCountUseCase(this._repo);

  Future<int> execute() async {
    final pending = await _repo.getPendingWeighings();
    return pending.length;
  }
}

class GetFailedWeighingsUseCase {
  final IWeighingRepository _repo;
  GetFailedWeighingsUseCase(this._repo);

  Future<List<Weighing>> execute() => _repo.getFailedWeighings();
}

class GetFailedWeighingsCountUseCase {
  final IWeighingRepository _repo;
  GetFailedWeighingsCountUseCase(this._repo);

  Future<int> execute() async {
    final failed = await _repo.getFailedWeighings();
    return failed.length;
  }
}
