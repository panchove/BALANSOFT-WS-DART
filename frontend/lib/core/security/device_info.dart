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
          macAddress: await _realMacAddress(),
          brand: androidInfo.brand,
          model: androidInfo.model,
          osVersion: 'Android ${androidInfo.version.release}',
        );
      } else if (Platform.isLinux) {
        final linuxInfo = await _plugin.linuxInfo;
        _cachedInfo = HardwareInfo(
          hardwareId: linuxInfo.machineId ?? linuxInfo.id,
          macAddress: await _realMacAddress(),
          brand: linuxInfo.prettyName,
          model: linuxInfo.name,
          osVersion: linuxInfo.version ?? '',
        );
      } else if (Platform.isWindows) {
        final windowsInfo = await _plugin.windowsInfo;
        _cachedInfo = HardwareInfo(
          hardwareId: windowsInfo.deviceId,
          macAddress: await _realMacAddress(),
          brand: windowsInfo.productName,
          model: windowsInfo.productName,
          osVersion:
              '${windowsInfo.productName} ${windowsInfo.displayVersion}',
        );
      } else {
        _cachedInfo = const HardwareInfo(
          hardwareId: 'unknown',
          macAddress: '',
          brand: 'unknown',
          model: 'unknown',
          osVersion: 'unknown',
        );
      }
    } catch (_) {
      _cachedInfo = const HardwareInfo(
        hardwareId: 'fallback',
        macAddress: '',
        brand: 'unknown',
        model: 'unknown',
        osVersion: 'unknown',
      );
    }

    return _cachedInfo!;
  }

  static Future<String> _realMacAddress() async {
    if (!Platform.isLinux) return '';
    try {
      final dir = Directory('/sys/class/net');
      if (!dir.existsSync()) return '';
      for (final entry in dir.listSync()) {
        final macFile = File('${entry.path}/address');
        if (!macFile.existsSync()) continue;
        final mac = macFile.readAsStringSync().trim().toUpperCase();
        if (RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$').hasMatch(mac) &&
            mac != '00:00:00:00:00:00') {
          return mac;
        }
      }
    } catch (_) {
      return '';
    }
    return '';
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
