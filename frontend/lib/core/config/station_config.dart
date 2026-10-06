import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Rol funcional de la estación, decidido por el INSTALADOR (no por el
/// operador). El rol determina qué hace la app en el arranque, pero NO
/// autoriza nada: tenant, licencia y permisos los decide siempre el backend
/// (docs/MANEJO_DB.md §13 · REQ-FN-079/080).
enum StationRole {
  servidor,
  trabajador;

  String get etiqueta {
    switch (this) {
      case StationRole.servidor:
        return 'SERVIDOR';
      case StationRole.trabajador:
        return 'TRABAJADOR';
    }
  }

  static StationRole parse(String? value) {
    if (value == null) {
      throw ArgumentError('rol no puede ser nulo');
    }
    final v = value.trim();
    if (v == 'SERVIDOR') return StationRole.servidor;
    if (v == 'TRABAJADOR') return StationRole.trabajador;
    throw FormatException('rol inválido: $v');
  }
}

/// Configuración inmutable leída de `config.json` (escrito por el instalador).
///
/// Contrato (BALANSOFT-INSTALLER `core/station_config.py`): exactamente dos
/// claves, `api_base_url` (http/https, sin credenciales ni path) y `rol`
/// (`SERVIDOR` | `TRABAJADOR`). Un archivo presente pero inválido es un error
/// DURO: no se degrada a otro archivo ni a un default localhost.
class StationConfig {
  final String apiBaseUrl;
  final StationRole rol;

  const StationConfig({
    required this.apiBaseUrl,
    required this.rol,
  });

  StationConfig copyWith({
    String? apiBaseUrl,
    StationRole? rol,
  }) {
    return StationConfig(
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      rol: rol ?? this.rol,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StationConfig &&
        other.apiBaseUrl == apiBaseUrl &&
        other.rol == rol;
  }

  @override
  int get hashCode => Object.hash(apiBaseUrl, rol);

  Map<String, dynamic> toJson() => {
        'api_base_url': apiBaseUrl,
        'rol': rol.etiqueta,
      };
}

enum StationConfigErrorType {
  /// No existe config.json en ninguna ubicación y no hay legado que migrar.
  ausente,

  /// El archivo existe pero no es JSON válido o no es un objeto.
  jsonInvalido,

  /// El JSON no contiene las dos claves del contrato.
  camposInvalidos,

  /// Las claves existen pero no cumplen el contrato (rol desconocido,
  /// URL rechazada, tipos incorrectos o claves extra).
  esquemaInvalido,

  /// El archivo existe pero no pudo leerse (permisos, IO).
  noLegible,
}

class StationConfigError implements Exception {
  final String? ruta;
  final StationConfigErrorType motivo;
  final String? detalle;

  StationConfigError({
    this.ruta,
    required this.motivo,
    this.detalle,
  });

  @override
  String toString() {
    final r = ruta == null ? '' : ' ($ruta)';
    final d = detalle == null ? '' : ': $detalle';
    return 'StationConfigError(${motivo.name})$r$d';
  }
}

/// Ubicaciones del contrato (BALANSOFT-INSTALLER `core/station_config.py`).
///
/// - Sistema: `/etc/balansoftws/config.json` (Linux) y
///   `%ProgramData%\BalansoftWS\config.json` (Windows).
/// - Override de usuario (prioritario): `~/.config/balansoftws/config.json`
///   en AMBAS plataformas — el instalador de TRABAJADOR, que corre con
///   privilegios distintos al usuario operativo, escribe ahí.
class StationConfigPaths {
  static String get _home {
    final h = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'];
    if (h != null && h.isNotEmpty) return h;
    return Directory.current.path;
  }

  /// Inyectables para tests: redirigen las rutas reales a un directorio
  /// temporal sin tocar la máquina del desarrollador.
  @visibleForTesting
  static String? pruebasOverrideDir;

  @visibleForTesting
  static String? pruebasSistemaDir;

  static String get overrideDir =>
      pruebasOverrideDir ?? '$_home/.config/balansoftws';

  static String get overridePath => '$overrideDir/config.json';

  static String get systemDir =>
      pruebasSistemaDir ?? _systemDirReal;

  static String get _systemDirReal {
    if (Platform.isWindows) {
      final programData = Platform.environment['ProgramData'] ??
          Platform.environment['ALLUSERSPROFILE'] ??
          'C:/ProgramData';
      return '$programData/BalansoftWS';
    }
    return '/etc/balansoftws';
  }

  static String get systemPath => '$systemDir/config.json';
}

/// Valida `api_base_url` según el contrato:
/// - esquema http/https;
/// - host no vacío;
/// - sin credenciales embebidas (`userInfo`);
/// - sin query ni fragmento;
/// - sin path distinto de vacío o `/`;
/// - puerto en 1..65535 (rechaza 0 y >65535, que `Uri.parse` tolera o lanza).
bool validarApiBaseUrl(String url) {
  try {
    final uri = Uri.parse(url);
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    if (uri.host.trim().isEmpty) return false;
    if (uri.userInfo.isNotEmpty) return false;
    if (uri.hasQuery) return false;
    if (uri.hasFragment) return false;
    if (uri.path.isNotEmpty && uri.path != '/') return false;
    final port = uri.port;
    if (port < 1 || port > 65535) return false;
    return true;
  } catch (_) {
    // Puertos fuera de rango, puertos malformados, etc.
    return false;
  }
}

Future<File?> _fileSiExiste(String path) async {
  try {
    final f = File(path);
    if (await f.exists()) return f;
  } catch (_) {
    // IO error al comprobar: se trata como ausente; el error real saldrá
    // al leer si el archivo existe.
  }
  return null;
}

Future<Map<String, dynamic>?> _leerJson(File f) async {
  try {
    final s = await f.readAsString();
    final obj = jsonDecode(s);
    if (obj is Map<String, dynamic>) return obj;
    return null;
  } catch (_) {
    return null;
  }
}

/// Decide si el JSON cumple el contrato y construye la [StationConfig].
/// Lanza [StationConfigError] con el tipo exacto.
StationConfig _configDesdeJson(Map<String, dynamic> obj, String ruta) {
  // Contrato ESTRICTO: exactamente las dos claves conocidas. Claves extra
  // rompen el contrato (el instalador solo escribe estas dos).
  final claves = obj.keys.toSet();
  const esperadas = {'api_base_url', 'rol'};
  if (!claves.containsAll(esperadas) || claves.length != esperadas.length) {
    throw StationConfigError(
      ruta: ruta,
      motivo: StationConfigErrorType.camposInvalidos,
      detalle: 'se esperaban exactamente $esperadas, se encontró $claves',
    );
  }
  final api = obj['api_base_url'];
  final rolVal = obj['rol'];
  if (api is! String || rolVal is! String) {
    throw StationConfigError(
      ruta: ruta,
      motivo: StationConfigErrorType.esquemaInvalido,
      detalle: 'api_base_url y rol deben ser strings',
    );
  }
  if (!validarApiBaseUrl(api)) {
    throw StationConfigError(
      ruta: ruta,
      motivo: StationConfigErrorType.esquemaInvalido,
      detalle: 'api_base_url no cumple el contrato: $api',
    );
  }
  try {
    final rol = StationRole.parse(rolVal);
    return StationConfig(apiBaseUrl: api, rol: rol);
  } on FormatException catch (e) {
    throw StationConfigError(
      ruta: ruta,
      motivo: StationConfigErrorType.esquemaInvalido,
      detalle: e.message,
    );
  }
}

/// Carga la config del instalador con prioridad override → sistema.
///
/// - `migrarLegado: true` intenta, cuando NO existe ningún archivo, la
///   migración única desde las preferencias de la app legada (wizard viejo).
class StationConfigLoader {
  /// Devuelve la config si el archivo existe y es válido; `null` si el
  /// archivo NO existe; lanza [StationConfigError] si existe pero es inválido.
  static Future<StationConfig?> _cargarDeRuta(String ruta) async {
    final f = await _fileSiExiste(ruta);
    if (f == null) return null;
    final obj = await _leerJson(f);
    if (obj == null) {
      throw StationConfigError(
        ruta: ruta,
        motivo: StationConfigErrorType.jsonInvalido,
      );
    }
    return _configDesdeJson(obj, ruta);
  }

  static Future<StationConfig> cargar({bool migrarLegado = false}) async {
    final override = await _cargarDeRuta(StationConfigPaths.overridePath);
    if (override != null) return override;

    final sistema = await _cargarDeRuta(StationConfigPaths.systemPath);
    if (sistema != null) return sistema;

    if (migrarLegado) {
      final migrado = await _migrarDesdePrefs();
      if (migrado != null) return migrado;
    }

    throw StationConfigError(
      motivo: StationConfigErrorType.ausente,
    );
  }

  /// Migración única desde las preferencias del wizard viejo. Solo se
  /// invoca cuando NO existe ningún `config.json` (override ni sistema).
  ///
  /// Escribe el override (0600) y limpia las claves legadas: a partir de ahí
  /// la fuente de verdad es el archivo, como el resto de estaciones.
  static Future<StationConfig?> _migrarDesdePrefs() async {
    final StationConfig? cfg;
    try {
      final prefs = await SharedPreferences.getInstance();
      final api = prefs.getString('api_base_url') ??
          prefs.getString('apiBaseUrl');
      final rolStr = prefs.getString('modo_estacion') ??
          prefs.getString('modoEstacion');
      if (api == null || !validarApiBaseUrl(api)) return null;
      final rol = StationRole.parse(rolStr);
      cfg = StationConfig(apiBaseUrl: api, rol: rol);
      await StationConfigWriter.escribirOverride(cfg);
      await _limpiarPrefsLegadas(prefs);
      return cfg;
    } catch (_) {
      // Sin preferencias legadas válidas o error de escritura: se reporta
      // como ausente; el instalador es la vía de provisión oficial.
      return null;
    }
  }

  static Future<void> _limpiarPrefsLegadas(SharedPreferences prefs) async {
    for (final clave in const [
      'api_base_url',
      'apiBaseUrl',
      'modo_estacion',
      'modoEstacion',
      'licencia_verificada',
      'es_titular_licencia',
      'empresa_setup_capturado',
      'setup_preferencias_completado',
    ]) {
      await prefs.remove(clave);
    }
  }
}

class StationConfigWriter {
  /// Establece modo 0600 en Unix mediante `chmod` del sistema.
  ///
  /// En Windows no existe el modo POSIX: se omite a propósito (la ruta de
  /// usuario ya está protegida por la política de cuentas del SO). En Unix
  /// NO se traga el error: si `chmod` falla, se propaga para no dejar el
  /// override con permisos incorrectos (el archivo puede contener la URL del
  /// servidor titular).
  static Future<void> _setFileMode0600(File f) async {
    if (Platform.isWindows) return;
    try {
      final res = await Process.run('chmod', ['0600', f.path]);
      if (res.exitCode != 0) {
        throw StationConfigError(
          ruta: f.path,
          motivo: StationConfigErrorType.noLegible,
          detalle:
              'chmod 0600 falló (exit=${res.exitCode}): ${res.stderr}',
        );
      }
    } on StationConfigError {
      rethrow;
    } catch (e) {
      throw StationConfigError(
        ruta: f.path,
        motivo: StationConfigErrorType.noLegible,
        detalle: 'no se pudo establecer modo 0600: $e',
      );
    }
  }

  /// Escribe el override de usuario de forma atómica (tmp + rename) con
  /// permisos 0600. Preserva el rol si se actualiza solo la URL.
  static Future<void> escribirOverride(StationConfig cfg) async {
    final dir = Directory(StationConfigPaths.overrideDir);
    try {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final path = StationConfigPaths.overridePath;
      final tmp = File('$path.tmp');
      final jsonStr = const JsonEncoder.withIndent('  ').convert(cfg.toJson());
      await tmp.writeAsString('$jsonStr\n');
      await tmp.rename(path);
      await _setFileMode0600(File(path));
    } on StationConfigError {
      rethrow;
    } catch (e) {
      throw StationConfigError(
        ruta: StationConfigPaths.overridePath,
        motivo: StationConfigErrorType.noLegible,
        detalle: 'no se pudo escribir el override: $e',
      );
    }
  }

  /// Actualiza solo `api_base_url` del override, conservando el rol actual.
  /// Requiere que ya exista una config válida (override, sistema o legado);
  /// si no, no inventa un rol.
  static Future<void> actualizarApiBaseUrl(String apiBaseUrl) async {
    if (!validarApiBaseUrl(apiBaseUrl)) {
      throw FormatException('api_base_url no cumple el contrato: $apiBaseUrl');
    }
    final actual = await StationConfigLoader.cargar(migrarLegado: false);
    final nuevo = actual.copyWith(apiBaseUrl: apiBaseUrl);
    await escribirOverride(nuevo);
  }
}