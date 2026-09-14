import '../entities/license.dart';

abstract class ILicenseRepository {
  Future<License> validateLicense(String licenseKey, String hardwareId);
  Future<License> activateLicense(String licenseKey, String hardwareId);
  Future<License?> getCachedLicense();
  Future<void> cacheLicense(License license);
  Future<void> clearCache();
  Future<License?> refreshLicense(String licenseKey);
}
