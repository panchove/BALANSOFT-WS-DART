import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../domain/entities/license.dart';
import '../../../../domain/usecases/license_usecases.dart';

part 'license_event.dart';
part 'license_state.dart';

class LicenseBloc extends Bloc<LicenseEvent, LicenseState> {
  final ValidateLicenseUseCase _validateUseCase;
  final GetCachedLicenseUseCase _getCachedUseCase;
  final ClearLicenseCacheUseCase _clearCacheUseCase;

  LicenseBloc({
    required ValidateLicenseUseCase validateUseCase,
    required GetCachedLicenseUseCase getCachedUseCase,
    required ClearLicenseCacheUseCase clearCacheUseCase,
  })  : _validateUseCase = validateUseCase,
        _getCachedUseCase = getCachedUseCase,
        _clearCacheUseCase = clearCacheUseCase,
        super(LicenseInitial()) {
    on<ValidateLicenseEvent>(_onValidate);
    on<CheckCachedLicenseEvent>(_onCheckCached);
    on<ClearLicenseCacheEvent>(_onClearCache);
  }

  Future<void> _onValidate(
      ValidateLicenseEvent event, Emitter<LicenseState> emit) async {
    emit(LicenseLoading());
    try {
      final license = await _validateUseCase.execute(event.licenseKey);
      emit(LicenseValid(license));
    } catch (e) {
      emit(LicenseInvalid());
    }
  }

  Future<void> _onCheckCached(
      CheckCachedLicenseEvent event, Emitter<LicenseState> emit) async {
    final license = await _getCachedUseCase.execute();
    if (license != null) {
      emit(LicenseValid(license));
    }
  }

  Future<void> _onClearCache(
      ClearLicenseCacheEvent event, Emitter<LicenseState> emit) async {
    await _clearCacheUseCase.execute();
    emit(LicenseInitial());
  }
}
