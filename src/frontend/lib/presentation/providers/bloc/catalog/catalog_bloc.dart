import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../domain/entities/catalogs.dart';
import '../../../../domain/usecases/catalog_usecases.dart';

part 'catalog_event.dart';
part 'catalog_state.dart';

class CatalogBloc extends Bloc<CatalogEvent, CatalogState> {
  final SyncCatalogsUseCase _syncUseCase;
  final GetCachedCatalogsUseCase _cachedUseCase;

  CatalogBloc({
    required SyncCatalogsUseCase syncUseCase,
    required GetCachedCatalogsUseCase cachedUseCase,
  })  : _syncUseCase = syncUseCase,
        _cachedUseCase = cachedUseCase,
        super(CatalogInitial()) {
    on<FetchCatalogsEvent>(_onFetch);
  }

  Future<void> _onFetch(
      FetchCatalogsEvent event, Emitter<CatalogState> emit) async {
    emit(CatalogLoading());
    try {
      final data = await _syncUseCase.execute();
      emit(CatalogLoaded(data));
    } catch (_) {
      try {
        final cached = await _cachedUseCase.execute();
        if (cached != null) {
          emit(CatalogLoaded(cached));
          return;
        }
      } catch (_) {}
      emit(const CatalogError('No se pudieron cargar los catálogos'));
    }
  }
}