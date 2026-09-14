import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Utilidad para guardar archivos (reportes, tickets, kardex) en la carpeta
/// de descargas del equipo (desktop) o documentos (mobile), devolviendo la
/// ruta completa para mostrarlo al usuario.
class SaveFileUtils {
  static Future<Directory> _directorioBase() async {
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