import 'package:bloc/bloc.dart';

import '../../../../core/constants/catalog_resources.dart';
import '../../../../data/datasources/remote/api_client.dart';

class CatalogCrudState {
  final List<Map<String, dynamic>> items;
  final bool cargando;
  final bool eliminando;
  final String? error;

  const CatalogCrudState({
    this.items = const [],
    this.cargando = true,
    this.eliminando = false,
    this.error,
  });

  CatalogCrudState copyWith({
    List<Map<String, dynamic>>? items,
    bool? cargando,
    bool? eliminando,
    String? error,
  }) {
    return CatalogCrudState(
      items: items ?? this.items,
      cargando: cargando ?? this.cargando,
      eliminando: eliminando ?? this.eliminando,
      error: error,
    );
  }
}

class CatalogCrudCubit extends Cubit<CatalogCrudState> {
  final ApiClient _api;

  CatalogCrudCubit(this._api) : super(const CatalogCrudState());

  Future<void> cargar(CatalogResource recurso) async {
    emit(state.copyWith(cargando: true, error: null));
    try {
      final resp = await _api.getList(recurso.listaPath);
      final items = _extraerLista(resp.data);
      emit(CatalogCrudState(items: items, cargando: false));
    } catch (e) {
      emit(state.copyWith(cargando: false, error: 'No se pudo cargar: $e'));
    }
  }

  Future<void> eliminar(CatalogResource recurso, String id) async {
    emit(state.copyWith(eliminando: true, error: null));
    try {
      await _api.deleteItem(recurso.itemPath(id));
      await cargar(recurso);
    } catch (e) {
      emit(state.copyWith(eliminando: false, error: 'No se pudo eliminar: $e'));
    }
  }

  List<Map<String, dynamic>> _extraerLista(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (data is Map && data['data'] is List) {
      return (data['data'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }
}