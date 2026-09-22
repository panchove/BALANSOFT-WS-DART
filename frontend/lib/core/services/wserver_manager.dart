import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../config/app_config.dart';

/// Orquesta el WServer: el backend local de la estación, compilado con
/// PyInstaller, que levanta la API FastAPI de la máquina.
///
/// En la PRIMERA instalación la app no tiene URL local configurada: este
/// gestor localiza el binario WServer (junto a la app o vía `WSERVER_PATH`),
/// lo lanza en modo detached y espera a que `/api/v1/health` responda. Así el
/// modo instalación de "Conexiones" puede probar/editar la conexión con la
/// API local ya levantada.
class WServerManager {
  WServerManager._();

  static const String _healthPath = '/api/v1/health';
  static const Duration _timeout = Duration(seconds: 60);
  static const Duration _probeTimeout = Duration(milliseconds: 1500);

  static Process? _proceso;
  static bool _intentado = false;

  /// Ruta por defecto (mismo esquema que `AppConfig.defaultApiBaseUrl`).
  static String get _baseLocal {
    final base = AppConfig.apiBaseUrl?.trim();
    return (base == null || base.isEmpty)
        ? AppConfig.defaultApiBaseUrl
        : base;
  }

  /// Ubica el binario WServer: env `WSERVER_PATH`, junto al ejecutable de la
  /// app, o rutas relativas típicas de desarrollo.
  static String? _buscarBinario() {
    final envPath = Platform.environment['WSERVER_PATH'];
    if (envPath != null && envPath.trim().isNotEmpty && File(envPath).existsSync()) {
      return File(envPath).path;
    }

    final wname = Platform.isWindows ? 'WServer.exe' : 'WServer';

    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final junto = '$exeDir/$wname';
      if (File(junto).existsSync()) return junto;
    } catch (_) {}

    for (final rel in ['bin/WServer', 'dist/WServer/WServer', 'WServer']) {
      final f = File(rel);
      final abs = f.absolute;
      if (abs.existsSync()) return abs.path;
    }
    return null;
  }

  /// Verifica que la API local responde (sin tocar configuración global).
  static Future<bool> _healthOk(String baseUrl) async {
    final url = '${baseUrl.replaceAll(RegExp(r'/$'), '')}$_healthPath';
    try {
      final resp = await Dio(
        BaseOptions(connectTimeout: _probeTimeout, receiveTimeout: _probeTimeout),
      ).get(url);
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// ¿El WServer está corriendo y con la API local accesible?
  static Future<bool> isOnline() => _healthOk(_baseLocal);

  /// Asegura que el WServer está levantado. Idempotente: si la API local ya
  /// responde o ya se lanzó el proceso, no vuelve a intentarlo.
  ///
  /// Devuelve `true` si la API local responde al terminar.
  static Future<bool> ensureRunning() async {
    if (_intentado) return isOnline();
    _intentado = true;

    if (await isOnline()) return true;

    final binario = _buscarBinario();
    if (binario == null) return false;

    try {
      _proceso = await Process.start(
        binario,
        const [],
        mode: ProcessStartMode.detached,
      );
    } catch (_) {
      _proceso = null;
      return isOnline();
    }

    final limite = DateTime.now().add(_timeout);
    while (DateTime.now().isBefore(limite)) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (await isOnline()) return true;
      if (_proceso?.exitCode != null) return false;
      if (_proceso == null) return false;
    }
    return isOnline();
  }

  /// Baja el WServer lanzado por esta app (útil en desarrollo/tests).
  static Future<void> detener() async {
    _proceso?.kill();
    await _proceso?.exitCode.timeout(const Duration(seconds: 3), onTimeout: () => -1);
    _proceso = null;
    _intentado = false;
  }

  /// Olvida el estado interno (proceso lanzado/intento hecho) sin detener el
  /// servicio, de modo que una nueva llamada a [ensureRunning] re-verifique el
  /// health. Útil al "reiniciar la instalación" desde la app.
  static void reset() {
    _intentado = false;
  }
}