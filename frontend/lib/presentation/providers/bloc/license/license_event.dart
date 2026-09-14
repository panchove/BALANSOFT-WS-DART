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
