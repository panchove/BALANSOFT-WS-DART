import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../config/app_config.dart';
import '../i18n/translations.dart';

/// Avisos nativos del sistema operativo emitidos por **la app Flutter**
/// (Linux y Windows).
///
/// No sustituye a los del WServer (`backend/app/services/notifier.py`): ese
/// emisor corre aunque la app esté cerrada y este es el de la propia app.
/// Ambos usan el **mismo AUMID**, así que Windows los muestra bajo un mismo
/// emisor, y en Linux el operador ve el mismo nombre e icono en las dos vías.
///
/// Todo es *best effort*: si no hay bus de sesión (una estación sin escritorio,
/// un contenedor, un CI), el aviso simplemente no sale y el código sigue.
class OsNotifications {
  OsNotifications._();

  /// AppUserModelID, idéntico al que registra el backend (`notifier.py`).
  ///
  /// Windows exige que el emisor de un toast esté identificado; con el mismo
  /// AUMID en los dos canales, el operador no ve dos "apps" distintas por
  /// notificar lo mismo.
  static const String aumid = 'BALANSOFT-WS';

  /// Nombre del emisor tal como debe aparecer en el Centro de notificaciones.
  static const String nombreEmisor = 'BALANSOFT-WS';

  /// GUID del callback de activación (comportamiento idéntico al que usa el
  /// plugin; se fija para que no cambie entre instalaciones y los avisos
  /// queden agrupados bajo un mismo emisor).
  static const String guidActivacion = '7e2e6c4a-9d3f-4a1b-9f2c-5a8b6d0e1f34';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _listo = false;

  // ── Puntos de inyección para tests ────────────────────────────────────────
  //
  // En un test no hay bus de sesión ni notificador de escritorio, así que el
  // soporte de la plataforma y el plugin se pueden sustituir para observar el
  // aviso sin depender del equipo en el que corre la prueba.

  /// Sustituto del plugin real (solo tests).
  @visibleForTesting
  static FlutterLocalNotificationsPlugin? pluginPrueba;

  /// Sustituto del cálculo de soporte de plataforma (solo tests).
  @visibleForTesting
  static bool? soportadoPrueba;

  /// Restablece los sustitutos y el estado de inicialización (solo tests).
  @visibleForTesting
  static void reiniciarPrueba() {
    pluginPrueba = null;
    soportadoPrueba = null;
    _listo = false;
  }

  static FlutterLocalNotificationsPlugin get _pluginActual =>
      pluginPrueba ?? _plugin;

  /// ¿Soporta la app avisos nativos en este equipo?
  static bool get _soportado =>
      soportadoPrueba ??
      ((Platform.isLinux || Platform.isWindows) &&
          !Platform.environment.containsKey('FLUTTER_TEST'));

  static Future<void> _asegurarInicializado() async {
    if (_listo) return;
    await _pluginActual.initialize(
      settings: InitializationSettings(
        linux: LinuxInitializationSettings(
          defaultActionName: 'open',
          // Sin icono propio el servidor de escritorio dibuja uno genérico:
          // el mismo que usa el backend cuando no encuentra el de la app.
          defaultIcon: ThemeLinuxIcon('dialog-information'),
        ),
        windows: const WindowsInitializationSettings(
          appName: nombreEmisor,
          appUserModelId: aumid,
          guid: guidActivacion,
        ),
      ),
    );
    _listo = true;
  }

  /// Muestra un aviso nativo (idempotente: nunca lanza).
  static Future<void> mostrar({
    required String titulo,
    required String mensaje,
  }) async {
    if (!_soportado) return;
    try {
      await _asegurarInicializado();
      await _pluginActual.show(
        // Un único aviso: cada mensaje sustituye al anterior del mismo emisor.
        id: 0,
        title: titulo,
        body: mensaje,
        notificationDetails: NotificationDetails(
          linux: LinuxNotificationDetails(
            icon: ThemeLinuxIcon('dialog-information'),
          ),
          windows: const WindowsNotificationDetails(),
        ),
      );
    } catch (e) {
      // Sin bus de sesión / sin notificador de escritorio no hay aviso, pero
      // tampoco hay motivo para tumbar la operación que lo pedía.
      debugPrint('Aviso nativo omitido ($titulo): $e');
    }
  }

  /// Aviso de bienvenida de una estación recién instalada: se emite **una sola
  /// vez**, en el primer inicio de sesión de la app.
  static Future<void> notificarBienvenida() async {
    if (AppConfig.bienvenidaNotificada) return;
    // Se marca antes de emitir: `mostrar` es *best effort*, y una estación
    // sin notificador de escritorio no debe repetir el aviso en cada arranque.
    try {
      await AppConfig.setBienvenidaNotificada();
      await mostrar(
        titulo: AppTranslations.tr('notif_welcome_title'),
        mensaje: AppTranslations.tr('notif_welcome_body'),
      );
    } catch (e) {
      // Si falla la escritura de la preferencia o el aviso nativo, no se
      // tumba el login: el aviso se intentará de nuevo la próxima vez que
      // inicie la sesión o se abra Ajustes → Sincronización.
      debugPrint('Error emitiendo aviso de bienvenida: $e');
    }
  }
}
