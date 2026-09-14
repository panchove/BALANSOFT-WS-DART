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
