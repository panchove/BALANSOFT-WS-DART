import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

class DeviceInfo {
  static final DeviceInfoPlugin _plugin = DeviceInfoPlugin();
  static HardwareInfo? _cachedInfo;

  static Future<HardwareInfo> getHardwareInfo() async {
    if (_cachedInfo != null) return _cachedInfo!;

    try {
      if (Platform.isAndroid) {
        final androidInfo = await _plugin.androidInfo;
        _cachedInfo = HardwareInfo(
          hardwareId: androidInfo.id,
          macAddress: androidInfo.id,
          brand: androidInfo.brand,
          model: androidInfo.model,
          osVersion: 'Android ${androidInfo.version.release}',
        );
      } else if (Platform.isLinux) {
        final linuxInfo = await _plugin.linuxInfo;
        _cachedInfo = HardwareInfo(
          hardwareId: linuxInfo.machineId ?? linuxInfo.id,
          macAddress: linuxInfo.machineId ?? '',
          brand: linuxInfo.prettyName,
          model: linuxInfo.name,
          osVersion: linuxInfo.version ?? '',
        );
      } else if (Platform.isWindows) {
        final windowsInfo = await _plugin.windowsInfo;
        _cachedInfo = HardwareInfo(
          hardwareId: windowsInfo.deviceId,
          macAddress: windowsInfo.deviceId,
          brand: windowsInfo.productName,
          model: windowsInfo.productName,
          osVersion:
              '${windowsInfo.productName} ${windowsInfo.displayVersion}',
        );
      } else {
        _cachedInfo = HardwareInfo(
          hardwareId: 'unknown',
          macAddress: 'unknown',
          brand: 'unknown',
          model: 'unknown',
          osVersion: 'unknown',
        );
      }
    } catch (_) {
      _cachedInfo = HardwareInfo(
        hardwareId: 'fallback',
        macAddress: 'fallback',
        brand: 'unknown',
        model: 'unknown',
        osVersion: 'unknown',
      );
    }

    return _cachedInfo!;
  }
}

class HardwareInfo {
  final String hardwareId;
  final String macAddress;
  final String brand;
  final String model;
  final String osVersion;

  const HardwareInfo({
    required this.hardwareId,
    required this.macAddress,
    required this.brand,
    required this.model,
    required this.osVersion,
  });

  Map<String, String> toMap() => {
        'hardware_id': hardwareId,
        'mac_address': macAddress,
        'device_brand': brand,
        'device_model': model,
        'os_version': osVersion,
      };
}
