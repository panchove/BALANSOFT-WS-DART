import '../entities/license.dart';

abstract class ILicenseRepository {
  Future<License> validateLicense(String licenseKey);
  Future<License> activateLicense(String licenseKey);
  Future<License?> getCachedLicense();
  Future<void> cacheLicense(License license);
  Future<void> clearCache();
  Future<License?> refreshLicense(String licenseKey);
}
