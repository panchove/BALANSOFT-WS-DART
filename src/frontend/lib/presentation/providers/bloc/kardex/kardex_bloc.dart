// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 17025 / OIML R 76-1 / ISO/IEC 25010
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../../domain/entities/kardex.dart';
import '../../../../domain/usecases/kardex_usecases.dart';

part 'kardex_event.dart';
part 'kardex_state.dart';

class KardexBloc extends Bloc<KardexEvent, KardexState> {
  final KardexDetalleUseCase _detalleUseCase;

  KardexBloc({required KardexDetalleUseCase detalleUseCase})
      : _detalleUseCase = detalleUseCase,
        super(KardexInitial()) {
    on<LoadKardexEvent>(_onLoad);
  }

  Future<void> _onLoad(
      LoadKardexEvent event, Emitter<KardexState> emit) async {
    emit(KardexLoading());
    try {
      final data = await _detalleUseCase.execute(
        desde: event.desde,
        hasta: event.hasta,
        idProducto: event.idProducto,
        idAlmacen: event.idAlmacen,
      );
      emit(KardexLoaded(data));
    } catch (e) {
      emit(KardexError(e.toString()));
    }
  }
}