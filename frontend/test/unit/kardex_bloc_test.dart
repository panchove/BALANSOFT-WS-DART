/// T3.4 — BLoC de Kardex.
library;

import 'package:balansoft_ws/domain/entities/kardex.dart';
import 'package:balansoft_ws/domain/repositories/i_kardex_repository.dart';
import 'package:balansoft_ws/domain/usecases/kardex_usecases.dart';
import 'package:balansoft_ws/presentation/providers/bloc/kardex/kardex_bloc.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo implements IKardexRepository {
  Object? error;

  @override
  Future<KardexDetalle> detalle({
    required DateTime desde,
    required DateTime hasta,
    String? idProducto,
    String? idAlmacen,
  }) async {
    if (error != null) throw error!;
    return const KardexDetalle(
      fechaDesde: '2026-09-01',
      fechaHasta: '2026-09-08',
      saldoInicial: 0,
      saldoActual: 0,
      movimientos: [],
    );
  }

  @override
  Future<Response> exportExcel({
    required DateTime desde,
    required DateTime hasta,
    String? idProducto,
    String? idAlmacen,
  }) async =>
      Response(requestOptions: RequestOptions(path: ''));

  @override
  Future<Response> exportPdf({
    required DateTime desde,
    required DateTime hasta,
    String? idProducto,
    String? idAlmacen,
  }) async =>
      Response(requestOptions: RequestOptions(path: ''));
}

KardexBloc _bloc(Object? error) {
  final repo = _FakeRepo()..error = error;
  return KardexBloc(detalleUseCase: KardexDetalleUseCase(repo));
}

void main() {
  blocTest<KardexBloc, KardexState>(
    'emite Loaded al cargar',
    build: () => _bloc(null),
    act: (b) => b.add(LoadKardexEvent(
      desde: DateTime(2026, 9, 1),
      hasta: DateTime(2026, 9, 8),
    )),
    expect: () => [
      isA<KardexLoading>(),
      isA<KardexLoaded>(),
    ],
  );

  blocTest<KardexBloc, KardexState>(
    'emite Error si falla',
    build: () => _bloc(Exception('boom')),
    act: (b) => b.add(LoadKardexEvent(
      desde: DateTime(2026, 9, 1),
      hasta: DateTime(2026, 9, 8),
    )),
    expect: () => [
      isA<KardexLoading>(),
      isA<KardexError>(),
    ],
  );
}