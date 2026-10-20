// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 27001 / ISO/IEC 25010
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../domain/entities/license.dart';
import '../../../../domain/usecases/license_usecases.dart';

part 'license_event.dart';
part 'license_state.dart';

/// BLoC para la gestión del ciclo de vida y validación de licencias de uso.
///
/// Implementa los controles de acceso y activación bajo ISO/IEC 27001.
class LicenseBloc extends Bloc<LicenseEvent, LicenseState> {
  final ValidateLicenseUseCase _validateUseCase;
  final GetCachedLicenseUseCase _getCachedUseCase;
  final ClearLicenseCacheUseCase _clearCacheUseCase;

  /// Crea el BLoC inyectando casos de uso de validación, consulta y limpieza de caché.
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

  /// Maneja el evento [ValidateLicenseEvent] validando remotamente la clave ingresada.
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

  /// Maneja el evento [CheckCachedLicenseEvent] leyendo la licencia persistida en el almacenamiento seguro.
  Future<void> _onCheckCached(
      CheckCachedLicenseEvent event, Emitter<LicenseState> emit) async {
    final license = await _getCachedUseCase.execute();
    if (license != null) {
      emit(LicenseValid(license));
    }
  }

  /// Maneja el evento [ClearLicenseCacheEvent] eliminando la licencia de la estación.
  Future<void> _onClearCache(
      ClearLicenseCacheEvent event, Emitter<LicenseState> emit) async {
    await _clearCacheUseCase.execute();
    emit(LicenseInitial());
  }
}
