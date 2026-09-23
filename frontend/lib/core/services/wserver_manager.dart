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
  /// Recibe parámetros opcionales para configurar la base de datos local y el puerto.
  /// Devuelve `true` si la API local responde al terminar. Lanza un error con el mensaje 
  /// de stderr si el proceso falla por credenciales o puertos.
  static Future<bool> ensureRunning({
    String? dbHost,
    String? dbPort,
    String? dbUser,
    String? dbPass,
    String? dbName,
    String? apiPort,
  }) async {
    if (_intentado && dbUser == null) return isOnline();
    _intentado = true;

    if (await isOnline()) return true;

    final binario = _buscarBinario();
    if (binario == null) throw Exception('No se encontró el binario WServer.');

    final args = <String>[];
    if (dbHost != null && dbHost.isNotEmpty) args.addAll(['--db-host', dbHost]);
    if (dbPort != null && dbPort.isNotEmpty) args.addAll(['--db-port', dbPort]);
    if (dbUser != null && dbUser.isNotEmpty) args.addAll(['--db-user', dbUser]);
    if (dbPass != null && dbPass.isNotEmpty) args.addAll(['--db-pass', dbPass]);
    if (dbName != null && dbName.isNotEmpty) args.addAll(['--db-name', dbName]);
    if (apiPort != null && apiPort.isNotEmpty) args.addAll(['--api-port', apiPort]);

    String stderrSalida = '';

    try {
      _proceso = await Process.start(binario, args);
      
      // Capturar stderr para detectar errores si falla el proceso (ej: FATAL: password auth)
      _proceso?.stderr.transform(const SystemEncoding().decoder).listen((data) {
        stderrSalida += data;
      });
      
    } catch (e) {
      _proceso = null;
      throw Exception('No se pudo ejecutar el WServer: $e');
    }

    final limite = DateTime.now().add(_timeout);
    while (DateTime.now().isBefore(limite)) {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (await isOnline()) return true;
      
      // Ver si el proceso se cerró prematuramente (error)
      final exitCode = await _proceso?.exitCode.timeout(const Duration(milliseconds: 50), onTimeout: () => -1);
      if (exitCode != null && exitCode != -1 && exitCode != 0) {
        throw Exception('El servidor local falló al iniciar. Detalle:\n$stderrSalida');
      }
      if (_proceso == null) return false;
    }
    return isOnline();
  }

  /// Baja el WServer lanzado por esta app o corriendo en el puerto 8000.
  static Future<void> detener() async {
    try {
      if (_proceso != null) {
        _proceso?.kill();
        await _proceso?.exitCode
            .timeout(const Duration(seconds: 3), onTimeout: () => -1);
        _proceso = null;
      } else {
        if (Platform.isLinux || Platform.isMacOS) {
          await Process.run('fuser', ['-k', '8000/tcp']);
        } else if (Platform.isWindows) {
          await Process.run('taskkill', ['/F', '/IM', 'WServer.exe']);
        }
      }
    } catch (_) {}
    _intentado = false;
  }

  /// Olvida el estado interno (proceso lanzado/intento hecho) sin detener el
  /// servicio, de modo que una nueva llamada a [ensureRunning] re-verifique el
  /// health. Útil al "reiniciar la instalación" desde la app.
  static void reset() {
    _intentado = false;
  }

  /// Ruta del binario WServer a usar para el autostart del sistema (o `null`).
  static String? get binarioPath => _buscarBinario();

  static const String _autostartName = 'com.balansoft.wserver';

  /// Instala/elimina el arranque automático del WServer al iniciar sesión.
  /// Linux: `~/.config/autostart/*.desktop`; Windows: clave RUN del usuario.
  static Future<bool> setAutostart(bool activar) async {
    try {
      if (Platform.isLinux) {
        final bin = _buscarBinario();
        if (bin == null) return false;
        final binDir = File(bin).parent.path;
        String? icono;
        for (final nombre in ['wserver_icon.jpeg', 'wserver_icon.png']) {
          final f = File('$binDir/$nombre');
          if (f.existsSync()) {
            icono = f.path;
            break;
          }
        }
        final dir = Directory(
            '${Platform.environment['HOME'] ?? ''}/.config/autostart');
        final file = File('${dir.path}/$_autostartName.desktop');
        if (activar) {
          await dir.create(recursive: true);
          final lineaIcono = icono != null ? 'Icon=$icono\n' : '';
          await file.writeAsString('''
[Desktop Entry]
Type=Application
Version=1.0
Name=Balansoft-WS WServer
Comment=Backend local de Balansoft-WS (API de la estación)
Exec="$bin"
${lineaIcono}Terminal=false
X-GNOME-Autostart-enabled=true
''');
        } else if (await file.exists()) {
          await file.delete();
        }
        return true;
      }
      if (Platform.isWindows) {
        const runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
        const valueName = 'BalansoftWServer';
        if (activar) {
          final bin = _buscarBinario();
          if (bin == null) return false;
          await Process.run('reg',
              ['add', runKey, '/v', valueName, '/t', 'REG_SZ', '/d', '"$bin"', '/f']);
        } else {
          await Process.run('reg', ['delete', runKey, '/v', valueName, '/f']);
        }
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// ¿El autostart del WServer está instalado actualmente?
  static Future<bool> autostartActivo() async {
    try {
      if (Platform.isLinux) {
        final home = Platform.environment['HOME'] ?? '';
        return File('$home/.config/autostart/$_autostartName.desktop').existsSync();
      }
      if (Platform.isWindows) {
        const runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
        final res = await Process.run('reg', ['query', runKey, '/v', 'BalansoftWServer']);
        return res.exitCode == 0;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}