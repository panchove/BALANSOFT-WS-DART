// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 25010 / ISO/IEC 27001
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

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

  /// Nombre del arranque automático que instala el instalador
  /// (BALANSOFT-INSTALLER): tarea programada `balansoft-ws` en Windows, unidad
  /// `balansoft-ws.service` en Linux.
  static const String nombreServicio = 'balansoft-ws';

  static Process? _proceso;
  static bool _intentado = false;

  /// El WServer se lanzó **sin handle** de proceso (Windows, oculto).
  static bool _lanzadoOculto = false;

  /// Script de PowerShell entre comillas simples (duplica las internas).
  static String _ps(String valor) => "'${valor.replaceAll("'", "''")}'";

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

  // ── Arranque automático del sistema (instalador) ─────────────────────────
  //
  // El instalador deja el WServer arrancando con el equipo: tarea programada
  // `balansoft-ws` en Windows (como SYSTEM, sin sesión) y unidad systemd
  // `balansoft-ws.service` en Linux. Cuando existe, es **la mejor vía** para
  // levantar la API desde la app: arranca en segundo plano y sin consola (lo
  // que no consigue `Process.start`, que en Windows le crea una consola nueva
  // a una aplicación de consola como el WServer).

  /// ¿Existe el arranque automático que instaló el instalador?
  static Future<bool> _servicioInstalado() async {
    try {
      if (Platform.isWindows) {
        final r = await Process.run(
            'schtasks', ['/Query', '/TN', nombreServicio]);
        return r.exitCode == 0;
      }
      if (Platform.isLinux) {
        // `list-unit-files` sale con 0 aunque no exista la unidad (devuelve la
        // lista, quizá sin ella), así que se comprueba la salida.
        final r = await Process.run(
            'systemctl', ['list-unit-files', '$nombreServicio.service']);
        return r.exitCode == 0 && '${r.stdout}'.contains(nombreServicio);
      }
    } catch (_) {
      // Sin `schtasks`/`systemctl` (contenedor, SO distinto) no hay servicio.
    }
    return false;
  }

  /// Arranca el WServer por el arranque automático del sistema. Best-effort:
  /// devuelve si el arranque se pidió sin error.
  static Future<bool> _arrancarServicio() async {
    try {
      final r = Platform.isWindows
          ? await Process.run('schtasks', ['/Run', '/TN', nombreServicio])
          : await Process.run(
              'systemctl', ['start', '$nombreServicio.service']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Pide al arranque automático del sistema que se detenga (best-effort).
  static Future<void> _detenerServicio() async {
    try {
      if (Platform.isWindows) {
        await Process.run('schtasks', ['/End', '/TN', nombreServicio]);
      } else if (Platform.isLinux) {
        await Process.run('systemctl', ['stop', '$nombreServicio.service']);
      }
    } catch (_) {}
  }

  /// Fichero donde el lanzador oculto de Windows deja el `stdout`/`stderr`.
  static File _logOculto(String sufijo) => File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'balansoft-wserver$sufijo.log');

  /// Lanza el WServer en Windows **sin que asome una consola**.
  ///
  /// `Process.start` de Dart no expone `CREATE_NO_WINDOW`, y el WServer es una
  /// aplicación de consola (PyInstaller `console=True`): al lanzarlo desde la
  /// app —que es gráfica— Windows le crea una consola nueva, la ventana negra
  /// que veía el operador en cada arranque. `Start-Process -WindowStyle Hidden`
  /// pide al sistema que no la muestre.
  ///
  /// Devuelve el PID del WServer lanzado (o `null`), que es lo único que
  /// permite notar que murió antes de responder: `Start-Process` no da un
  /// handle de proceso a Dart. Las dos salidas se redirigen a fichero —así
  /// PowerShell no le pasa al hijo su propia tubería, que dejaría a
  /// `Process.run` esperando a que el WServer terminase— y el `stderr` se lee si
  /// el arranque falla (el mismo detalle que antes salía de la tubería).
  static Future<int?> _lanzarOcultoWindows(
      String binario, List<String> args) async {
    final lista = args.isEmpty ? '@()' : '@(${args.map(_ps).join(',')})';
    // `$p` es la variable de PowerShell: con `\` se escapa para que Dart no la
    // interprete como interpolación propia.
    final script = '\$p = Start-Process -FilePath ${_ps(binario)} '
        '-ArgumentList $lista -WindowStyle Hidden '
        '-RedirectStandardOutput ${_ps(_logOculto('').path)} '
        '-RedirectStandardError ${_ps(_logOculto('.err').path)} '
        '-PassThru; \$p.Id';
    final r = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-WindowStyle',
      'Hidden',
      '-Command',
      script,
    ]);
    _lanzadoOculto = true;
    return int.tryParse('${r.stdout}'.trim());
  }

  /// ¿Sigue vivo el proceso `pid`? (Windows, vía `tasklist`)
  static Future<bool> _sigueVivo(int pid) async {
    try {
      final r = await Process.run(
          'tasklist', ['/FI', 'PID eq $pid', '/NH', '/FO', 'CSV']);
      return r.exitCode == 0 && '${r.stdout}'.contains('$pid');
    } catch (_) {
      return true; // sin `tasklist` no se puede saber: no se declara muerto
    }
  }

  /// Contenido de los ficheros de diagnóstico del lanzador oculto (Windows).
  ///
  /// Se limita a los últimos 1024 caracteres de cada fichero para evitar que
  /// datos obsoletos o rutas largas se muestren al operador.
  static Future<String> _detalleOculto() async {
    final partes = <String>[];
    for (final f in [_logOculto('.err'), _logOculto('')]) {
      try {
        if (f.existsSync()) {
          final texto = (await f.readAsString()).trim();
          if (texto.isNotEmpty) {
            // Mantener solo los últimos 1024 caracteres por seguridad
            final limite = texto.length > 1024 ? texto.length - 1024 : 0;
            partes.add(texto.substring(limite));
          }
        }
      } catch (_) {}
    }
    return partes.join('\n');
  }

  /// Espera a que la API local responda, hasta `_timeout`.
  static Future<bool> _esperarOnline() async {
    final limite = DateTime.now().add(_timeout);
    while (DateTime.now().isBefore(limite)) {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (await isOnline()) return true;
    }
    return false;
  }

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

    // 1) Arranque automático del instalador (tarea programada / systemd): es
    //    la vía natural cuando existe — segundo plano y sin consola. Con
    //    parámetros de conexión explícitos (asistente de "Conexiones") se pasa
    //    directo al binario: el servicio no los admite.
    if (dbUser == null && await _servicioInstalado()) {
      final pidioArranque = await _arrancarServicio();
      if (pidioArranque && await _esperarOnline()) return true;
      if (pidioArranque) {
        // El servicio está instalado y aceptó el arranque, pero la API no
        // respondió. No se lanza además el binario: el `IgnoreNew` del
        // Programador de tareas (y el `Restart=on-failure` de la unidad) solo
        // protege a la vía del servicio, así que un segundo proceso lanzado
        // desde la app competiría por el mismo puerto (`:8000`). Se informa
        // del fallo y se deja que el servicio reintente.
        throw Exception(
            'El WServer está instalado como servicio pero la API local no '
            'respondió. Revisa el servicio ($nombreServicio) y vuelve a '
            'intentarlo.');
      }
      // No aceptó el arranque (sin permisos, gestor ausente): se cae al
      // lanzamiento directo del binario como último recurso.
    }

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
    int? pidOculto;

    try {
      if (Platform.isWindows) {
        // Sin handle de proceso (`Start-Process`): solo el PID, y el detalle
        // del fallo se lee de los ficheros de redirección.
        pidOculto = await _lanzarOcultoWindows(binario, args);
      } else {
        _proceso = await Process.start(binario, args);

        // Capturar stderr para detectar errores si falla el proceso (ej: FATAL: password auth)
        _proceso?.stderr.transform(const SystemEncoding().decoder).listen((data) {
          stderrSalida += data;
        });
      }
    } catch (e) {
      _proceso = null;
      throw Exception('No se pudo ejecutar el WServer: $e');
    }

    final limite = DateTime.now().add(_timeout);
    while (DateTime.now().isBefore(limite)) {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (await isOnline()) return true;

      if (_lanzadoOculto) {
        // El proceso no se puede observar con un handle, así que el fallo se
        // detecta por el PID (murió) y por el rastro del fichero de diagnóstico.
        stderrSalida = await _detalleOculto();
        if (pidOculto != null && !await _sigueVivo(pidOculto)) {
          throw Exception(
              'El servidor local falló al iniciar. Detalle:\n$stderrSalida');
        }
        continue;
      }

      // Ver si el proceso se cerró prematuramente (error)
      final exitCode = await _proceso?.exitCode.timeout(const Duration(milliseconds: 50), onTimeout: () => -1);
      if (exitCode != null && exitCode != -1 && exitCode != 0) {
        throw Exception('El servidor local falló al iniciar. Detalle:\n$stderrSalida');
      }
      if (_proceso == null) return false;
    }

    // Se agotó el plazo: si el lanzador oculto dejó un rastro, es el detalle
    // del fallo (credenciales, puerto ocupado...). Sin rastro, no responde.
    if (_lanzadoOculto) {
      final detalle = await _detalleOculto();
      if (detalle.isNotEmpty) {
        throw Exception('El servidor local falló al iniciar. Detalle:\n$detalle');
      }
    }
    return isOnline();
  }

  /// Baja el WServer lanzado por esta app, el que arrancó el arranque
  /// automático del sistema, o el que ocupa el puerto 8000.
  static Future<void> detener() async {
    try {
      if (_proceso != null) {
        _proceso?.kill();
        await _proceso?.exitCode
            .timeout(const Duration(seconds: 3), onTimeout: () => -1);
        _proceso = null;
      } else {
        // Si lo levantó el arranque automático instalado, se para por su gestor
        // (systemd / Programador de tareas) y no matando el proceso: al
        // matarlo, el gestor lo reviviría al momento.
        if (await _servicioInstalado()) {
          await _detenerServicio();
        }
        if (await isOnline()) {
          if (Platform.isLinux || Platform.isMacOS) {
            await Process.run('fuser', ['-k', '8000/tcp']);
          } else if (Platform.isWindows) {
            await Process.run('taskkill', ['/F', '/IM', 'WServer.exe']);
          }
        }
      }
    } catch (_) {}
    _intentado = false;
    _lanzadoOculto = false;
  }

  /// Detiene **solo** el WServer lanzado directamente por esta app en este
  /// arranque. No toca el servicio del sistema (systemd / tarea programada)
  /// ni un proceso ajeno: la estación SERVIDOR debe seguir sirviendo a las
  /// estaciones OPERADOR de la LAN aunque esta app se cierre.
  ///
  /// Es lo que usa [MainWindowListener.onWindowClose]: cerrar la ventana de
  /// la app no debe apagar el backend de la estación.
  static Future<void> detenerSoloProcesoLocal() async {
    try {
      if (_proceso != null) {
        _proceso?.kill();
        await _proceso?.exitCode
            .timeout(const Duration(seconds: 3), onTimeout: () => -1);
        _proceso = null;
      }
    } catch (_) {}
    _intentado = false;
    _lanzadoOculto = false;
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

  /// Script de PowerShell en base64 UTF-16LE (`-EncodedCommand`).
  ///
  /// Evita el problema de las comillas al guardar el guion en el registro
  /// (`reg add /d` recibe el valor como argumento y el analizador de línea de
  /// comandos se come las comillas internas) y de paso soporta rutas con
  /// espacios sin escaparlas: el alfabeto base64 no lleva comillas.
  static String _psEncoded(String script) {
    final bytes = <int>[];
    for (final code in script.codeUnits) {
      bytes.add(code & 0xFF);
      bytes.add((code >> 8) & 0xFF);
    }
    return base64Encode(bytes);
  }

  /// Lanzador oculto para el arranque automático de **usuario** en Windows.
  ///
  /// El WServer es una aplicación de consola: arrancarlo pelado al iniciar
  /// sesión abría la ventana negra que veía el operador en el escritorio.
  static String _lanzadorOculto(String binario) {
    final script =
        'Start-Process -FilePath ${_ps(binario)} -WindowStyle Hidden';
    return 'powershell.exe -NoProfile -WindowStyle Hidden '
        '-EncodedCommand ${_psEncoded(script)}';
  }

  /// Variante pública de [_lanzadorOculto], solo para tests: es el texto que se
  /// guarda en la clave RUN del usuario, y que el arranque de Windows ejecuta
  /// sin que se vea ninguna consola.
  @visibleForTesting
  static String lanzadorOculto(String binario) => _lanzadorOculto(binario);

  /// ¿La tarea programada del instalador existe y está habilitada? (Windows)
  ///
  /// Se mira el XML de la tarea y no la salida de texto (`/FO LIST`), que llega
  /// traducida al idioma del Windows instalado y no se puede analizar.
  static Future<bool> _tareaWindowsActiva() async {
    try {
      final r = await Process.run(
          'schtasks', ['/Query', '/TN', nombreServicio, '/XML']);
      if (r.exitCode != 0) return false;
      return !'${r.stdout}'.contains('<Enabled>false</Enabled>');
    } catch (_) {
      return false;
    }
  }

  /// ¿La unidad systemd del instalador está habilitada? (Linux)
  static Future<bool> _unidadLinuxActiva() async {
    try {
      final r = await Process.run(
          'systemctl', ['is-enabled', '$nombreServicio.service']);
      return r.exitCode == 0 && '${r.stdout}'.trim().startsWith('enabled');
    } catch (_) {
      return false;
    }
  }

  /// Contenido del `.desktop` de arranque automático de **usuario** (Linux).
  ///
  /// `Terminal=false` es lo que mantiene el arranque en silencio: sin esa línea
  /// los escritorios que no la heredan pueden abrirle una consola a un servicio
  /// que no la necesita, que es el equivalente a la ventana negra de Windows.
  /// La ruta del binario va entrecomillada, que una instalación en
  /// `/opt/BALANSOFT WS/` no debe partirse en dos argumentos.
  @visibleForTesting
  static String contenidoDesktop(String binario, String? icono) {
    final lineaIcono = icono != null ? 'Icon=$icono\n' : '';
    return '''
[Desktop Entry]
Type=Application
Version=1.0
Name=Balansoft-WS WServer
Comment=Backend local de Balansoft-WS (API de la estación)
Exec="$binario"
${lineaIcono}Terminal=false
X-GNOME-Autostart-enabled=true
''';
  }

  /// Instala/elimina el arranque automático del WServer al iniciar el sistema.
  ///
  /// Cuando el instalador dejó su servicio (tarea programada `balansoft-ws` en
  /// Windows, unidad `balansoft-ws.service` en Linux) el conmutador actúa
  /// **sobre él**, que es la vía silenciosa; sin servicio se cae al arranque de
  /// usuario (`.desktop` en Linux, clave RUN en Windows).
  static Future<bool> setAutostart(bool activar) async {
    try {
      if (Platform.isWindows) {
        const runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
        const valueName = 'BalansoftWServer';
        if (await _servicioInstalado()) {
          await Process.run('schtasks', [
            '/Change',
            '/TN',
            nombreServicio,
            activar ? '/ENABLE' : '/DISABLE',
          ]);
          // El valor de RUN se retira: con él y la tarea a la vez arrancarían
          // dos WServers compitiendo por el puerto y por la base de datos.
          await Process.run('reg', ['delete', runKey, '/v', valueName, '/f']);
          if (activar) await _arrancarServicio();
          return true;
        }
        if (activar) {
          final bin = _buscarBinario();
          if (bin == null) return false;
          await Process.run('reg', [
            'add', runKey, '/v', valueName, '/t', 'REG_SZ',
            '/d', _lanzadorOculto(bin), '/f',
          ]);
        } else {
          await Process.run('reg', ['delete', runKey, '/v', valueName, '/f']);
        }
        return true;
      }
      if (Platform.isLinux) {
        final dir = Directory(
            '${Platform.environment['HOME'] ?? ''}/.config/autostart');
        final file = File('${dir.path}/$_autostartName.desktop');
        if (await _servicioInstalado()) {
          final r = await Process.run('systemctl', [
            activar ? 'enable' : 'disable',
            if (activar) '--now',
            '$nombreServicio.service',
          ]);
          if (r.exitCode == 0) {
            // La unidad del instalador manda: no se añade además un autostart
            // de usuario (arrancarían dos WServers a la vez).
            if (await file.exists()) await file.delete();
            return true;
          }
        }
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
        if (activar) {
          await dir.create(recursive: true);
          await file.writeAsString(contenidoDesktop(bin, icono));
        } else if (await file.exists()) {
          await file.delete();
        }
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// ¿El autostart del WServer está instalado y activo actualmente?
  ///
  /// Mira las dos vías: el arranque de usuario de esta app y el servicio del
  /// instalador (tarea programada / unidad systemd).
  static Future<bool> autostartActivo() async {
    try {
      if (Platform.isLinux) {
        final home = Platform.environment['HOME'] ?? '';
        if (File('$home/.config/autostart/$_autostartName.desktop')
            .existsSync()) {
          return true;
        }
        return await _unidadLinuxActiva();
      }
      if (Platform.isWindows) {
        const runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
        final res =
            await Process.run('reg', ['query', runKey, '/v', 'BalansoftWServer']);
        if (res.exitCode == 0) return true;
        return await _tareaWindowsActiva();
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Materializa el arranque automático que pide [AppConfig.wserverAutostart].
  ///
  /// El conmutador de Ajustes y el flag de configuración guardan la
  /// **intención**; si en el equipo no está instalado nada (estación recién
  /// instalada, desinstalación parcial), este método la convierte en realidad.
  /// Si ya hay algo activo no se toca: el servicio del instalador manda.
  static Future<void> asegurarAutostart() async {
    try {
      if (await autostartActivo()) return;
      await setAutostart(true);
    } catch (_) {}
  }
}
