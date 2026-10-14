import 'package:balansoft_ws/data/datasources/remote/api_client.dart';
import 'package:balansoft_ws/data/repositories/notification_repository.dart';
import 'package:balansoft_ws/domain/entities/notification.dart';
import 'package:balansoft_ws/presentation/providers/bloc/notifications/notifications_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

/// ApiClient falso: devuelve filas de la bandeja sin tocar la red.
class _FakeApi extends ApiClient {
  final List<Map<String, dynamic>> notificaciones;
  Map<String, dynamic> resumen;
  bool falla = false;
  int resumenLlamadas = 0;
  int listarLlamadas = 0;
  final List<String> leidas = [];
  final List<String> archivadas = [];
  int marcadasTodas = 0;
  int pruebas = 0;
  String? ultimoEstado;
  bool ultimoSoloNoLeidas = false;
  bool fallaResumen = false;
  int crearRecordatorios = 0;
  int actualizarRecordatorios = 0;
  int eliminarRecordatorios = 0;

  _FakeApi({
    this.notificaciones = const [],
    this.resumen = const {'no_leidas': 0, 'total': 0, 'por_severidad': {}},
  });

  @override
  Future<List<Map<String, dynamic>>> listNotificaciones({
    String? estado,
    String? tipo,
    bool soloNoLeidas = false,
    int skip = 0,
    int limit = 50,
  }) async {
    ultimoEstado = estado;
    ultimoSoloNoLeidas = soloNoLeidas;
    if (estado != null) {
      return notificaciones.where((n) => n['estado'] == estado).toList();
    }
    if (soloNoLeidas) {
      return notificaciones
          .where((n) => n['estado'] == 'no_leida')
          .toList();
    }
    return notificaciones;
  }

  @override
  Future<Map<String, dynamic>> resumenNotificaciones() async {
    resumenLlamadas++;
    if (fallaResumen) throw StateError('sin red');
    return resumen;
  }

  @override
  Future<Map<String, dynamic>> marcarNotificacionLeida(String id) async {
    if (id.endsWith('boom')) throw StateError('sin red');
    return {'id': id, 'estado': 'leida', 'tipo': 'x', 'titulo': 't', 'severidad': 'info', 'created_at': '2026-01-01T00:00:00', 'origen': 'evento'};
  }

  @override
  Future<Map<String, dynamic>> archivarNotificacion(String id) async {
    archivadas.add(id);
    return {'id': id, 'estado': 'archivado', 'tipo': 'x', 'titulo': 't', 'severidad': 'info', 'created_at': '2026-01-01T00:00:00', 'origen': 'evento'};
  }

  @override
  Future<int> marcarTodasLeidas() async {
    marcadasTodas++;
    return marcadasTodas;
  }

  @override
  Future<Map<String, dynamic>> probarNotificacion() async {
    pruebas++;
    return {'id': 'p1', 'estado': 'no_leida', 'tipo': 'prueba', 'titulo': 'Hola', 'severidad': 'info', 'created_at': '2026-01-01T00:00:00', 'origen': 'sistema'};
  }

  @override
  Future<List<Map<String, dynamic>>> listRecordatorios({
    bool incluirInactivos = true,
  }) async =>
      const [];

  @override
  Future<Map<String, dynamic>> crearRecordatorio(Map<String, dynamic> body) async {
    crearRecordatorios++;
    return {
      'id': 'r$crearRecordatorios',
      'titulo': body['titulo'],
      'mensaje': body['mensaje'],
      'programada_para': body['programada_para'],
      'recurrencia': body['recurrencia'] ?? 'none',
      'activo': true,
      'created_at': '2026-01-01T00:00:00',
    };
  }

  @override
  Future<Map<String, dynamic>> actualizarRecordatorio(
      String id, Map<String, dynamic> body) async {
    actualizarRecordatorios++;
    return {
      'id': id,
      'titulo': body['titulo'] ?? 't',
      'mensaje': body['mensaje'],
      'programada_para': body['programada_para'] ?? '2026-01-01T00:00:00',
      'recurrencia': body['recurrencia'] ?? 'none',
      'activo': body['activo'] ?? true,
      'created_at': '2026-01-01T00:00:00',
    };
  }

  @override
  Future<void> eliminarRecordatorio(String id) async {
    eliminarRecordatorios++;
  }

  @override
  Future<Map<String, dynamic>> probarRecordatorio(String id) async => {
        'id': 'np',
        'estado': 'no_leida',
        'tipo': 'recordatorio',
        'titulo': 't',
        'severidad': 'media',
        'created_at': '2026-01-01T00:00:00',
        'origen': 'recordatorio',
      };
}

Map<String, dynamic> _notif(
  String id, {
  String estado = 'no_leida',
  String severidad = 'info',
  String tipo = 'licencia_por_vencer',
  String? mensaje,
}) =>
    {
      'id': id,
      'tipo': tipo,
      'severidad': severidad,
      'titulo': 'Aviso $id',
      'mensaje': mensaje,
      'estado': estado,
      'leida': estado != 'no_leida',
      'origen': 'evento',
      'created_at': '2026-10-13T10:00:00',
      'leida_en': estado == 'leida' ? '2026-10-13T10:05:00' : null,
    };

NotificationsCubit _cubit(_FakeApi api, {Duration? intervalo}) =>
    NotificationsCubit(
      repo: NotificationRepository(apiClient: api),
      intervalo: intervalo,
    );

void main() {
  group('NotificationRepository', () {
    test('traduce la bandeja y el resumen del backend', () async {
      final api = _FakeApi(
        notificaciones: [_notif('a', severidad: 'critica', mensaje: 'hola')],
        resumen: const {
          'no_leidas': 3,
          'total': 7,
          'por_severidad': {'critica': 2, 'media': 1},
        },
      );
      final repo = NotificationRepository(apiClient: api);

      final items = await repo.listar();
      expect(items, hasLength(1));
      expect(items.first.severidad, 'critica');
      expect(items.first.mensaje, 'hola');
      expect(items.first.leida, isFalse);

      final resumen = await repo.resumen();
      expect(resumen.noLeidas, 3);
      expect(resumen.total, 7);
      expect(resumen.porSeveridad['critica'], 2);
    });

    test('la entidad marca leída y calcula no leídas', () {
      final items = [
        AppNotification.fromJson(_notif('a')),
        AppNotification.fromJson(_notif('b', estado: 'leida')),
      ];
      expect(items.first.estado, AppNotification.estadoNoLeida);
      expect(items[1].leida, isTrue);
    });
  });

  group('NotificationsCubit', () {
    test('iniciar refresca el resumen y sondea periódicamente', () async {
      final api = _FakeApi(
        resumen: const {'no_leidas': 2, 'total': 4, 'por_severidad': {}},
      );
      final cubit = _cubit(api, intervalo: const Duration(milliseconds: 25));
      await cubit.iniciar();
      expect(cubit.state.resumen.noLeidas, 2);
      expect(api.resumenLlamadas, 1);

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(api.resumenLlamadas, greaterThan(1));
      await cubit.close();
    });

    test('close cancela el sondeo', () async {
      final api = _FakeApi();
      final cubit = _cubit(api, intervalo: const Duration(milliseconds: 20));
      await cubit.iniciar();
      await cubit.close();
      final llamadas = api.resumenLlamadas;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(api.resumenLlamadas, llamadas);
    });

    test('cargar trae la bandeja y sincroniza el contador', () async {
      final api = _FakeApi(
        notificaciones: [_notif('a', severidad: 'alta'), _notif('b')],
        resumen: const {'no_leidas': 2, 'total': 2, 'por_severidad': {}},
      );
      final cubit = _cubit(api);
      await cubit.cargar();
      expect(cubit.state.cargando, isFalse);
      expect(cubit.state.items, hasLength(2));
      expect(cubit.state.noLeidas, hasLength(2));
      expect(cubit.state.resumen.noLeidas, 2);
    });

    test('cargar con filtro "sin leer" pide solo no leídas', () async {
      final api = _FakeApi(notificaciones: [
        _notif('a'),
        _notif('b', estado: 'leida'),
        _notif('c', estado: 'archivado'),
      ]);
      final cubit = _cubit(api);
      await cubit.cargar(soloNoLeidas: true);
      expect(api.ultimoSoloNoLeidas, isTrue);
      expect(cubit.state.items, hasLength(1));
      expect(cubit.state.items.first.id, 'a');
    });

    test('marcarLeida reemplaza el aviso y refresca el contador', () async {
      final api = _FakeApi(
        notificaciones: [_notif('a')],
        resumen: const {'no_leidas': 1, 'total': 1, 'por_severidad': {}},
      );
      final cubit = _cubit(api);
      await cubit.cargar();

      await cubit.marcarLeida('a');
      expect(cubit.state.items.first.estado, AppNotification.estadoLeida);
      expect(cubit.state.items.first.leida, isTrue);
      expect(cubit.state.procesando, isFalse);
    });

    test('archivar llama al backend y marca el aviso', () async {
      final api = _FakeApi(notificaciones: [_notif('a')]);
      final cubit = _cubit(api);
      await cubit.cargar();

      await cubit.archivar('a');
      expect(api.archivadas, ['a']);
      expect(cubit.state.items.first.estado, AppNotification.estadoArchivado);
    });

    test('marcarTodasLeidas marca localmente todas las no leídas', () async {
      final api = _FakeApi(notificaciones: [
        _notif('a'),
        _notif('b'),
        _notif('c', estado: 'leida'),
      ]);
      final cubit = _cubit(api);
      await cubit.cargar();

      await cubit.marcarTodasLeidas();
      expect(api.marcadasTodas, 1);
      expect(cubit.state.items.where(
            (n) => n.estado == AppNotification.estadoNoLeida,
          ),
          isEmpty);
    });

    test('probar crea el aviso de prueba y recarga la bandeja', () async {
      final api = _FakeApi(notificaciones: [_notif('a')]);
      final cubit = _cubit(api);
      await cubit.cargar();
      final ok = await cubit.probar();
      expect(ok, isTrue);
      expect(api.pruebas, 1);
    });

    test('un fallo de red deja el error y no rompe el estado', () async {
      final api = _FakeApi(notificaciones: [_notif('boom')]);
      final cubit = _cubit(api);
      await cubit.cargar();
      await cubit.marcarLeida('boom');
      expect(cubit.state.error, isNotNull);
      expect(cubit.state.procesando, isFalse);
    });

    test('un resumen que falla conserva el último valor conocido', () async {
      final api = _FakeApi(
        resumen: const {'no_leidas': 5, 'total': 5, 'por_severidad': {}},
      );
      final cubit = _cubit(api);
      await cubit.refrescarResumen();
      expect(cubit.state.resumen.noLeidas, 5);

      // Ahora el backend "cae": no debe borrar el contador ni lanzar.
      api.fallaResumen = true;
      await cubit.refrescarResumen();
      expect(cubit.state.resumen.noLeidas, 5);
    });
  });
}
