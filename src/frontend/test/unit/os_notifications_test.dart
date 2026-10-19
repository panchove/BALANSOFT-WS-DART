import 'package:balansoft_ws/core/config/app_config.dart';
import 'package:balansoft_ws/core/i18n/translations.dart';
import 'package:balansoft_ws/core/services/os_notifications.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

/// Plugin falso: registra lo que la app le pide, sin tocar el SO.
///
/// Se **implementa** la clase real (no se hereda): su constructor sin nombre es
/// una fábrica, así que no admite subclases. Los miembros no usados caen por
/// `noSuchMethod`.
class _PluginFalso implements FlutterLocalNotificationsPlugin {
  final List<InitializationSettings> inicializaciones = [];
  final List<Map<String, Object?>> avisos = [];
  bool falla = false;

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
        onDidReceiveBackgroundNotificationResponse,
  }) async {
    inicializaciones.add(settings);
    return true;
  }

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async {
    if (falla) {
      throw Exception('sin notificador de escritorio');
    }
    avisos.add({'id': id, 'title': title, 'body': body});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} no se usa en el test');
}

void main() {
  late _PluginFalso plugin;

  setUp(() {
    plugin = _PluginFalso();
    OsNotifications.reiniciarPrueba();
    OsNotifications.pluginPrueba = plugin;
    OsNotifications.soportadoPrueba = true;
    AppConfig.bienvenidaNotificada = false;
  });

  tearDown(() {
    OsNotifications.reiniciarPrueba();
    AppConfig.bienvenidaNotificada = false;
  });

  group('notificarBienvenida', () {
    test('se emite una sola vez por estación', () async {
      await OsNotifications.notificarBienvenida();

      expect(plugin.avisos, hasLength(1));
      expect(AppConfig.bienvenidaNotificada, isTrue,
          reason: 'el aviso se debe marcar emitido al instante');

      await OsNotifications.notificarBienvenida();
      expect(plugin.avisos, hasLength(1),
          reason: 'segundo arranque de la app: no se repite');
    });

    test('lleva el título y el cuerpo traducidos del locale activo', () async {
      await OsNotifications.notificarBienvenida();

      final aviso = plugin.avisos.single;
      expect(aviso['title'], AppTranslations.tr('notif_welcome_title'));
      expect(aviso['body'], AppTranslations.tr('notif_welcome_body'));
      expect(aviso['id'], 0,
          reason: 'un id estable evita que los avisos se apilen en el SO');
    });

    test('usa el MISMO AUMID que el backend del WServer', () async {
      await OsNotifications.notificarBienvenida();

      final windows = plugin.inicializaciones.single.windows;
      expect(windows, isNotNull);
      expect(windows!.appUserModelId, 'BALANSOFT-WS');
      expect(OsNotifications.aumid, 'BALANSOFT-WS',
          reason: 'el emisor de los avisos del WServer (notifier.py) es el '
              'mismo: si cambia aquí, hay que cambiarlo en el backend');
    });

    test('inicializa el canal de Linux con acción por defecto', () async {
      await OsNotifications.notificarBienvenida();

      final linux = plugin.inicializaciones.single.linux;
      expect(linux, isNotNull);
      expect(linux!.defaultActionName, isNotEmpty);
    });

    test('sin soporte de plataforma no se toca el plugin', () async {
      OsNotifications.soportadoPrueba = false;

      await OsNotifications.notificarBienvenida();

      expect(plugin.avisos, isEmpty);
      expect(plugin.inicializaciones, isEmpty);
    });

    test('un fallo del plugin no tumba la operación que lo pidió', () async {
      plugin.falla = true;

      await expectLater(
        OsNotifications.notificarBienvenida(),
        completes,
      );
    });

    test('mostrar() es un no-op fuera de Linux y Windows', () async {
      OsNotifications.soportadoPrueba = false;

      await OsNotifications.mostrar(titulo: 'T', mensaje: 'M');

      expect(plugin.avisos, isEmpty);
    });
  });

  group('traducción del aviso', () {
    test('el texto existe en los tres idiomas', () {
      for (final lang in ['es', 'en', 'pt']) {
        expect(
          AppTranslations.tr('notif_welcome_title', langCode: lang),
          isNot('notif_welcome_title'),
          reason: 'falta notif_welcome_title en $lang',
        );
        expect(
          AppTranslations.tr('notif_welcome_body', langCode: lang),
          isNot('notif_welcome_body'),
          reason: 'falta notif_welcome_body en $lang',
        );
      }
      expect(
        AppTranslations.tr('notif_welcome_title', langCode: 'es'),
        'Bienvenido a BALANSOFT WS',
      );
      expect(
        AppTranslations.tr('notif_welcome_title', langCode: 'en'),
        'Welcome to BALANSOFT WS',
      );
      expect(
        AppTranslations.tr('notif_welcome_title', langCode: 'pt'),
        'Bem-vindo ao BALANSOFT WS',
      );
    });
  });
}
