// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 27001 / ISO/IEC 25010
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

part of 'license_bloc.dart';

abstract class LicenseState extends Equatable {
  const LicenseState();
  @override
  List<Object?> get props => [];
}

class LicenseInitial extends LicenseState {}
class LicenseLoading extends LicenseState {}

class LicenseValid extends LicenseState {
  final License license;
  const LicenseValid(this.license);
  @override
  List<Object?> get props => [license];
}

class LicenseInvalid extends LicenseState {}

class LicenseError extends LicenseState {
  final String message;
  const LicenseError(this.message);
  @override
  List<Object?> get props => [message];
}
