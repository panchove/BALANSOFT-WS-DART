// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 27001 / ISO/IEC 25010
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

part of 'license_bloc.dart';

abstract class LicenseEvent extends Equatable {
  const LicenseEvent();
  @override
  List<Object?> get props => [];
}

class ValidateLicenseEvent extends LicenseEvent {
  final String licenseKey;
  const ValidateLicenseEvent(this.licenseKey);
  @override
  List<Object?> get props => [licenseKey];
}

class CheckCachedLicenseEvent extends LicenseEvent {}

class ClearLicenseCacheEvent extends LicenseEvent {}
