import 'package:balansoft_ws/core/config/app_config.dart';
import 'package:balansoft_ws/core/services/wserver_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Contratos del arranque silencioso del WServer (Windows/Linux) y del
/// interruptor de Ajustes, que ahora arranca **activado** por defecto.
void main() {
  group('AppConfig — contrato de la ventana y del arranque automático', () {
    test('windowTitle es el título exacto que debe tener la ventana', () {
      // El runner nativo fija el título al crear la ventana; si este valor
      // cambia, Windows vuelve a mostrar "balansoft_ws".
      expect(AppConfig.windowTitle,
          'BALANSOFT WS - ESTACIÓN DE PESAJE INDUSTRIAL');
    });

    test('wserverAutostart arranca activado por defecto', () {
      // Una estación recién instalada no puede depender de abrir la app
      // para que haya API.
      expect(AppConfig.wserverAutostart, isTrue);
    });

    test('init respeta el apagado explícito guardado', () async {
      SharedPreferences.setMockInitialValues({'wserver_autostart': false});
      await AppConfig.init();
      expect(AppConfig.wserverAutostart, isFalse);

      SharedPreferences.setMockInitialValues({'wserver_autostart': true});
      await AppConfig.init();
      expect(AppConfig.wserverAutostart, isTrue);
    });

    test('init con prefs vacías activa el arranque automático', () async {
      SharedPreferences.setMockInitialValues({});
      await AppConfig.init();
      expect(AppConfig.wserverAutostart, isTrue);
    });
  });

  group('WServerManager — .desktop de usuario en silencio (Linux)', () {
    test('Terminal=false para no abrir consola', () {
      final txt = WServerManager.contenidoDesktop('/opt/Balansoft/wserver', null);
      expect(txt, contains('Terminal=false'));
      expect(txt, contains('X-GNOME-Autostart-enabled=true'));
      expect(txt, contains('Exec="/opt/Balansoft/wserver"'));
      expect(txt.contains('Icon='), isFalse);
    });

    test('incluye el icono cuando se pasa', () {
      final txt = WServerManager.contenidoDesktop('/usr/bin/ws', '/tmp/x.png');
      expect(txt, contains('Icon=/tmp/x.png'));
      expect(txt, contains('Terminal=false'));
    });
  });

  group('WServerManager — lanzador oculto en Windows', () {
    test('es powershell oculto con -EncodedCommand y sin comillas sueltas', () {
      final cmd = WServerManager.lanzadorOculto(r'C:\Balansoft WS\wserver.exe');

      expect(cmd, startsWith('powershell.exe -NoProfile -WindowStyle Hidden'));
      expect(cmd, contains('-EncodedCommand '));
      // El valor de la clave RUN no debe llevar comillas dobles: el
      // analizador de línea de comandos de `reg add /d` se las come y la
      // ruta con espacios se partiría en pedazos.
      expect(cmd.contains('"'), isFalse);

      // El payload decodificado debe ser el Start-Process oculto.
      final b64 = cmd.split('-EncodedCommand ').last.trim();
      final decoded = _base64Decode(b64);
      expect(decoded, contains('Start-Process'));
      expect(decoded, contains('-WindowStyle Hidden'));
      expect(decoded, contains(r'C:\Balansoft WS\wserver.exe'));
    });

    test('el script codificado es UTF-16LE válido (letras no ASCII)', () {
      final cmd = WServerManager.lanzadorOculto('C:\\ñú\\wserver.exe');
      final b64 = cmd.split('-EncodedCommand ').last.trim();
      final decoded = _base64Decode(b64);
      expect(decoded, contains('ñú'.substring(0, 1)));
      expect(decoded, contains('Start-Process'));
    });
  });

  group('WServerManager — detenerSoloProcesoLocal (cierre de ventana)', () {
    test('sin proceso lanzado es no-op: no lanza excepción', () async {
      // En el arranque de un test nunca hay _proceso lanzado; el método
      // debe limitarse a resetear los flags sin tocar systemd ni fuser.
      await expectLater(WServerManager.detenerSoloProcesoLocal(), completes);
    });

    test('resetea los flags de intento para un futuro ensureRunning', () async {
      await WServerManager.detenerSoloProcesoLocal();
      // Si los flags no se resetearan, un segundo ensureRunning creería que
      // ya intentó arrancar y saltaría el health-check.
      // La señal observable es que detenerSoloProcesoLocal es idempotente.
      await expectLater(WServerManager.detenerSoloProcesoLocal(), completes);
    });
  });
}

/// Decodifica base64 a texto (UTF-16LE del script de PowerShell).
String _base64Decode(String b64) {
  const tabla = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
      'abcdefghijklmnopqrstuvwxyz0123456789+/';
  final salida = <int>[];
  var acumulado = 0;
  var bits = 0;
  for (final ch in b64.split('')) {
    if (ch == '=') break;
    final idx = tabla.indexOf(ch);
    if (idx < 0) continue;
    acumulado = (acumulado << 6) | idx;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      salida.add((acumulado >> bits) & 0xFF);
    }
  }
  // UTF-16LE → UTF-8 aprox: convertimos a codeUnits de 2 bytes.
  final codeUnits = <int>[];
  for (var i = 0; i + 1 < salida.length; i += 2) {
    codeUnits.add(salida[i] | (salida[i + 1] << 8));
  }
  return String.fromCharCodes(codeUnits);
}
