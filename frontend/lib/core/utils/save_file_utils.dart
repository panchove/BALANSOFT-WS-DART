import 'dart:io';

import 'package:path_provider/path_provider.dart';
import '../config/app_config.dart';

/// Utilidad para guardar archivos (reportes, tickets, kardex) en la carpeta
/// configurada por el ADMIN de la cuenta para todas las sesiones, o en la
/// carpeta de descargas del equipo como fallback predeterminado.
class SaveFileUtils {
  static const String keyRutaExportacion = 'report_export_path';

  /// Obtiene la ruta personalizada configurada en la sesión/empresa.
  static String? getRutaPersonalizada() {
    try {
      return AppConfig.prefs.getString(keyRutaExportacion);
    } catch (_) {
      return null;
    }
  }

  /// Guarda o limpia la ruta personalizada en las preferencias locales.
  static Future<void> setRutaPersonalizada(String? ruta) async {
    try {
      if (ruta == null || ruta.trim().isEmpty) {
        await AppConfig.prefs.remove(keyRutaExportacion);
      } else {
        await AppConfig.prefs.setString(keyRutaExportacion, ruta.trim());
      }
    } catch (_) {}
  }

  static Future<Directory> _directorioBase() async {
    final custom = getRutaPersonalizada();
    if (custom != null && custom.trim().isNotEmpty) {
      final customDir = Directory(custom.trim());
      try {
        if (!await customDir.exists()) {
          await customDir.create(recursive: true);
        }
        return customDir;
      } catch (_) {
        // Fallback seguro a descargas si la ruta no tiene permisos de escritura
      }
    }

    final downloads = await getDownloadsDirectory();
    if (downloads != null) return downloads;
    return getApplicationDocumentsDirectory();
  }

  /// Guarda [bytes] en un archivo con el [nombre] dado.
  /// Retorna la ruta absoluta del archivo guardado.
  static Future<String> save(
    List<int> bytes,
    String nombre, {
    String? subcarpeta,
  }) async {
    var dir = await _directorioBase();
    if (subcarpeta != null && subcarpeta.isNotEmpty) {
      dir = Directory('${dir.path}/$subcarpeta');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }
    final nombreLimpio =
        nombre.replaceAll(RegExp(r'[^A-Za-z0-9_\-.]'), '_');
    final file = File('${dir.path}/$nombreLimpio');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}