import 'dart:io';

/// Abre un archivo con la aplicación predeterminada del sistema operativo.
/// En Linux usa `xdg-open`; en macOS `open`; en Windows `start`.
/// En caso de error retorna el mensaje de la excepción.
class OpenFileUtils {
  OpenFileUtils._();

  /// Abre el [path] con el visor del SO.
  /// Retorna `null` si tuvo éxito o el mensaje de error en caso contrario.
  static Future<String?> open(String path) async {
    try {
      String exe;
      if (Platform.isLinux) {
        exe = 'xdg-open';
      } else if (Platform.isMacOS) {
        exe = 'open';
      } else if (Platform.isWindows) {
        exe = 'explorer';
      } else {
        return 'Plataforma no soportada para abrir archivos';
      }
      final result = await Process.run(exe, [path]);
      if (result.exitCode != 0) {
        final err = result.stderr.toString().trim();
        return err.isNotEmpty ? err : 'No se pudo abrir el archivo';
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// Abre la carpeta que contiene el archivo [path].
  static Future<String?> openFolder(String path) async {
    final folder = File(path).parent.path;
    return open(folder);
  }
}
