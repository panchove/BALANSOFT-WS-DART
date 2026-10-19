import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:balansoft_ws/core/theme/app_theme.dart';
import 'package:balansoft_ws/data/datasources/remote/api_client.dart';
import 'package:balansoft_ws/data/repositories/notification_repository.dart';
import 'package:balansoft_ws/domain/entities/notification.dart';
import 'package:balansoft_ws/domain/entities/user.dart';
import 'package:balansoft_ws/domain/repositories/i_auth_repository.dart';
import 'package:balansoft_ws/domain/usecases/auth_usecases.dart';
import 'package:balansoft_ws/presentation/providers/bloc/auth/auth_bloc.dart';
import 'package:balansoft_ws/presentation/providers/bloc/notifications/notifications_cubit.dart';
import 'package:balansoft_ws/presentation/screens/notifications/notification_center_screen.dart';
import 'package:balansoft_ws/presentation/screens/notifications/reminders_screen.dart';
import 'package:balansoft_ws/presentation/widgets/notification_bell.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _DummyApi extends ApiClient {}

/// Repositorio en memoria: ni red ni backend.
class _FakeRepo extends NotificationRepository {
  _FakeRepo({
    List<AppNotification>? notificaciones,
    List<Reminder>? recordatorios,
  })  : notificaciones = [...?notificaciones],
        recordatorios = [...?recordatorios],
        super(apiClient: _DummyApi());

  final List<AppNotification> notificaciones;
  final List<Reminder> recordatorios;

  int leidas = 0;
  int archivadas = 0;
  int todasLeidas = 0;
  int probadas = 0;
  int pruebRecordatorio = 0;
  int eliminados = 0;
  String? ultimoFiltro;

  @override
  Future<List<AppNotification>> listar({
    String? estado,
    String? tipo,
    bool soloNoLeidas = false,
    int skip = 0,
    int limit = 50,
  }) async {
    ultimoFiltro = soloNoLeidas ? 'sin_leer' : estado;
    if (soloNoLeidas) {
      return notificaciones
          .where((n) => n.estado == AppNotification.estadoNoLeida)
          .toList();
    }
    if (estado != null) {
      return notificaciones.where((n) => n.estado == estado).toList();
    }
    return notificaciones;
  }

  @override
  Future<NotificationSummary> resumen() async => NotificationSummary(
        noLeidas: notificaciones
            .where((n) => n.estado == AppNotification.estadoNoLeida)
            .length,
        total: notificaciones.length,
      );

  @override
  Future<AppNotification> marcarLeida(String id) async {
    leidas++;
    return _clonar(id, AppNotification.estadoLeida);
  }

  @override
  Future<AppNotification> archivar(String id) async {
    archivadas++;
    return _clonar(id, AppNotification.estadoArchivado);
  }

  @override
  Future<int> marcarTodasLeidas() async {
    todasLeidas++;
    return notificaciones.length;
  }

  @override
  Future<AppNotification> probar() async {
    probadas++;
    return _demo('prueba-1');
  }

  @override
  Future<List<Reminder>> listarRecordatorios({
    bool incluirInactivos = true,
  }) async =>
      recordatorios;

  @override
  Future<Reminder> crearRecordatorio({
    required String titulo,
    String? mensaje,
    required DateTime programadaPara,
    String recurrencia = 'none',
  }) async {
    final nuevo = Reminder(
      id: 'r${recordatorios.length + 1}',
      titulo: titulo,
      mensaje: mensaje,
      programadaPara: programadaPara,
      recurrencia: recurrencia,
      createdAt: DateTime(2026, 10, 13),
    );
    recordatorios.add(nuevo);
    return nuevo;
  }

  @override
  Future<Reminder> actualizar(
    String id, {
    String? titulo,
    String? mensaje,
    DateTime? programadaPara,
    String? recurrencia,
    bool? activo,
  }) async {
    final i = recordatorios.indexWhere((r) => r.id == id);
    final r = recordatorios[i];
    final actualizado = Reminder(
      id: r.id,
      titulo: titulo ?? r.titulo,
      mensaje: mensaje ?? r.mensaje,
      programadaPara: programadaPara ?? r.programadaPara,
      recurrencia: recurrencia ?? r.recurrencia,
      activo: activo ?? r.activo,
      createdAt: r.createdAt,
    );
    recordatorios[i] = actualizado;
    return actualizado;
  }

  @override
  Future<void> eliminar(String id) async {
    eliminados++;
    recordatorios.removeWhere((r) => r.id == id);
  }

  @override
  Future<AppNotification> probarRecordatorio(String id) async {
    pruebRecordatorio++;
    return _demo('recordatorio-prueba');
  }

  AppNotification _clonar(String id, String estado) {
    final n = notificaciones.firstWhere((x) => x.id == id);
    return AppNotification(
      id: n.id,
      tipo: n.tipo,
      severidad: n.severidad,
      titulo: n.titulo,
      mensaje: n.mensaje,
      estado: estado,
      leida: estado != AppNotification.estadoNoLeida,
      origen: n.origen,
      createdAt: n.createdAt,
    );
  }
}

AppNotification _demo(
  String id, {
  String estado = AppNotification.estadoNoLeida,
  String severidad = 'media',
  String tipo = 'licencia_por_vencer',
  String? mensaje,
}) =>
    AppNotification(
      id: id,
      tipo: tipo,
      severidad: severidad,
      titulo: 'Aviso $id',
      mensaje: mensaje,
      estado: estado,
      leida: estado != AppNotification.estadoNoLeida,
      createdAt: DateTime(2026, 10, 13, 10, 30),
    );

// ---------------------------------------------------------------------------
// Helpers de montaje
// ---------------------------------------------------------------------------

class _FakeAuthRepository implements IAuthRepository {
  _FakeAuthRepository(this.usuario);

  final User usuario;

  @override
  Future<User> login({
    required String email,
    required String password,
    String? hardwareId,
    String? deviceBrand,
    String? deviceModel,
    String? osVersion,
    String? macAddress,
  }) async =>
      usuario;
  @override
  Future<User> register({
    required String empresaNombre,
    required String empresaRif,
    required String usuarioNombre,
    required String email,
    required String password,
    String? licenciaKey,
  }) async =>
      usuario;
  @override
  Future<void> logout() async {}
  @override
  Future<String> refreshToken(String refreshToken) async => 'token';
  @override
  Future<String?> refreshAccessToken() async => 'token';
  @override
  Future<void> forgotPassword(String email) async {}
  @override
  Future<void> resetPassword(String token, String newPassword) async {}
  @override
  Future<User?> getCachedUser() async => usuario;

  @override
  Future<User?> refrescarEmpresaEnUsuarioCacheado() async => usuario;
  @override
  Future<SesionRestaurada> restoreSession() async => SesionRestaurada.ok;
  @override
  Future<void> cacheUser(User user) async {}
  @override
  Future<void> clearCache() async {}
}

AuthBloc _authBloc(String rol) {
  final repo = _FakeAuthRepository(User(
    idUsuario: 'u-1',
    nombre: 'Usuario',
    email: 'u@balansoft.com.ve',
    rol: rol,
    idEmpresa: 'emp-1',
  ));
  return AuthBloc(
    loginUseCase: LoginUseCase(repo),
    registerUseCase: RegisterUseCase(repo),
    logoutUseCase: LogoutUseCase(repo),
    getCachedUserUseCase: GetCachedUserUseCase(repo),
    restoreSessionUseCase: RestoreSessionUseCase(repo),
    forgotPasswordUseCase: ForgotPasswordUseCase(repo),
    resetPasswordUseCase: ResetPasswordUseCase(repo),
    refrescarEmpresaUseCase: RefrescarEmpresaUseCase(repo),
  )..add(const CheckAuthStatusEvent());
}

Widget _envolver(Widget hijo, {AuthBloc? auth, NotificationsCubit? cubit}) {
  return MultiBlocProvider(
    providers: [
      if (auth != null) BlocProvider<AuthBloc>.value(value: auth),
      if (cubit != null)
        BlocProvider<NotificationsCubit>.value(value: cubit),
    ],
    child: MaterialApp(
      theme: buildLightTheme(),
      locale: const Locale('es'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es')],
      home: hijo,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationBell', () {
    testWidgets('muestra el contador de no leídas', (tester) async {
      final cubit = NotificationsCubit(repo: _FakeRepo(
        notificaciones: [_demo('a'), _demo('b'), _demo('c')],
      ));
      await cubit.refrescarResumen();
      addTearDown(cubit.close);

      await tester.pumpWidget(_envolver(
        const Scaffold(body: NotificationBell()),
        cubit: cubit,
      ));

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('sin pendientes no dibuja contador', (tester) async {
      final cubit = NotificationsCubit(repo: _FakeRepo());
      await cubit.refrescarResumen();
      addTearDown(cubit.close);

      await tester.pumpWidget(_envolver(
        const Scaffold(body: NotificationBell()),
        cubit: cubit,
      ));

      expect(find.text('0'), findsNothing);
      expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    });

    testWidgets('al tocarla abre el centro de notificaciones', (tester) async {
      final cubit = NotificationsCubit(repo: _FakeRepo());
      addTearDown(cubit.close);

      await tester.pumpWidget(_envolver(
        const Scaffold(body: NotificationBell()),
        auth: _authBloc('ADMIN'),
        cubit: cubit,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('notificaciones_campana_btn')));
      await tester.pumpAndSettle();

      expect(find.byType(NotificationCenterScreen), findsOneWidget);
    });
  });

  group('NotificationCenterScreen', () {
    testWidgets('lista los avisos con su severidad', (tester) async {
      final cubit = NotificationsCubit(repo: _FakeRepo(
        notificaciones: [
          _demo('a', severidad: 'critica', mensaje: 'Licencia vencida'),
          _demo('b', estado: AppNotification.estadoLeida, severidad: 'info'),
        ],
      ));
      addTearDown(cubit.close);

      await tester.pumpWidget(_envolver(
        const NotificationCenterScreen(),
        auth: _authBloc('OPERADOR'),
        cubit: cubit,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Aviso a'), findsOneWidget);
      expect(find.text('Licencia vencida'), findsOneWidget);
      expect(find.text('Aviso b'), findsOneWidget);
    });

    testWidgets('sin avisos muestra el estado vacío', (tester) async {
      final cubit = NotificationsCubit(repo: _FakeRepo());
      addTearDown(cubit.close);

      await tester.pumpWidget(_envolver(
        const NotificationCenterScreen(),
        auth: _authBloc('OPERADOR'),
        cubit: cubit,
      ));
      await tester.pumpAndSettle();

      expect(find.text('No hay notificaciones.'), findsOneWidget);
    });

    testWidgets('el filtro "sin leer" recarga solo las no leídas',
        (tester) async {
      final repo = _FakeRepo(notificaciones: [
        _demo('a'),
        _demo('b', estado: 'leida'),
      ]);
      final cubit = NotificationsCubit(repo: repo);
      addTearDown(cubit.close);

      await tester.pumpWidget(_envolver(
        const NotificationCenterScreen(),
        auth: _authBloc('OPERADOR'),
        cubit: cubit,
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notificacion_a')), findsOneWidget);
      expect(find.byKey(const Key('notificacion_b')), findsOneWidget);

      await tester.tap(find.byKey(const Key('notificaciones_filtro_no_leidas')));
      await tester.pumpAndSettle();

      expect(repo.ultimoFiltro, 'sin_leer');
      expect(find.byKey(const Key('notificacion_a')), findsOneWidget);
      expect(find.byKey(const Key('notificacion_b')), findsNothing);
    });

    testWidgets('marcar como leída llama al backend', (tester) async {
      final repo = _FakeRepo(notificaciones: [_demo('a')]);
      final cubit = NotificationsCubit(repo: repo);
      addTearDown(cubit.close);

      await tester.pumpWidget(_envolver(
        const NotificationCenterScreen(),
        auth: _authBloc('OPERADOR'),
        cubit: cubit,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('notificacion_leer_a')));
      await tester.pumpAndSettle();

      expect(repo.leidas, 1);
    });

    testWidgets('archivar llama al backend', (tester) async {
      final repo = _FakeRepo(notificaciones: [_demo('a')]);
      final cubit = NotificationsCubit(repo: repo);
      addTearDown(cubit.close);

      await tester.pumpWidget(_envolver(
        const NotificationCenterScreen(),
        auth: _authBloc('OPERADOR'),
        cubit: cubit,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('notificacion_archivar_a')));
      await tester.pumpAndSettle();

      expect(repo.archivadas, 1);
    });

    testWidgets('marcar todas como leídas llama al backend', (tester) async {
      final repo = _FakeRepo(notificaciones: [_demo('a'), _demo('b')]);
      final cubit = NotificationsCubit(repo: repo);
      addTearDown(cubit.close);

      await tester.pumpWidget(_envolver(
        const NotificationCenterScreen(),
        auth: _authBloc('OPERADOR'),
        cubit: cubit,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('notif_marcar_todas_btn')));
      await tester.pumpAndSettle();

      expect(repo.todasLeidas, 1);
    });

    testWidgets('el aviso de prueba solo aparece para ADMIN', (tester) async {
      final repo = _FakeRepo(notificaciones: [_demo('a')]);
      final cubit = NotificationsCubit(repo: repo);
      addTearDown(cubit.close);

      await tester.pumpWidget(_envolver(
        const NotificationCenterScreen(),
        auth: _authBloc('OPERADOR'),
        cubit: cubit,
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notificaciones_probar_btn')), findsNothing);
      expect(
        find.byKey(const Key('notificaciones_recordatorios_btn')),
        findsNothing,
      );
      expect(repo.probadas, 0);
    });

    testWidgets('ADMIN ve y usa el aviso de prueba', (tester) async {
      final repo = _FakeRepo(notificaciones: [_demo('a')]);
      final cubit = NotificationsCubit(repo: repo);
      addTearDown(cubit.close);

      await tester.pumpWidget(_envolver(
        const NotificationCenterScreen(),
        auth: _authBloc('ADMIN'),
        cubit: cubit,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('notificaciones_probar_btn')));
      await tester.pumpAndSettle();

      expect(repo.probadas, 1);
    });
  });

  group('RemindersScreen', () {
    Reminder demo({
      String id = 'r1',
      bool activo = true,
      String recurrencia = 'none',
    }) =>
        Reminder(
          id: id,
          titulo: 'Revisar báscula',
          mensaje: 'Calibrar antes del turno',
          programadaPara: DateTime(2026, 10, 20, 8, 0),
          recurrencia: recurrencia,
          activo: activo,
          createdAt: DateTime(2026, 10, 13),
        );

    Future<void> montar(WidgetTester tester, _FakeRepo repo) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          locale: const Locale('es'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('es')],
          home: RemindersScreen(repository: repo),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lista los recordatorios', (tester) async {
      await montar(tester, _FakeRepo(recordatorios: [demo()]));

      expect(find.text('Recordatorios'), findsOneWidget);
      expect(find.text('Revisar báscula'), findsOneWidget);
      expect(find.textContaining('20/10/2026 08:00'), findsOneWidget);
    });

    testWidgets('sin recordatorios muestra el estado vacío', (tester) async {
      await montar(tester, _FakeRepo());
      expect(find.text('Todavía no hay recordatorios.'), findsOneWidget);
    });

    testWidgets('el título es obligatorio al crear', (tester) async {
      final repo = _FakeRepo();
      await montar(tester, repo);

      await tester.tap(find.byKey(const Key('recordatorio_nuevo_btn')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(find.text('El título es obligatorio'), findsOneWidget);
      expect(repo.recordatorios, isEmpty);
    });

    testWidgets('crea un recordatorio con título y mensaje', (tester) async {
      final repo = _FakeRepo();
      await montar(tester, repo);

      await tester.tap(find.byKey(const Key('recordatorio_nuevo_btn')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('recordatorio_titulo_field')),
        'Sacar el reporte',
      );
      await tester.enterText(
        find.byKey(const Key('recordatorio_mensaje_field')),
        'Cierre de mes',
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(repo.recordatorios, hasLength(1));
      expect(repo.recordatorios.first.titulo, 'Sacar el reporte');
      expect(repo.recordatorios.first.mensaje, 'Cierre de mes');
      expect(find.text('Sacar el reporte'), findsOneWidget);
    });

    testWidgets('alterna activo/inactivo', (tester) async {
      final repo = _FakeRepo(recordatorios: [demo()]);
      await montar(tester, repo);

      await tester.tap(find.byKey(const Key('recordatorio_activo_r1')));
      await tester.pumpAndSettle();

      expect(repo.recordatorios.first.activo, isFalse);
    });

    testWidgets('probar ahora dispara el recordatorio', (tester) async {
      final repo = _FakeRepo(recordatorios: [demo()]);
      await montar(tester, repo);

      await tester.tap(find.byKey(const Key('recordatorio_probar_r1')));
      await tester.pumpAndSettle();

      expect(repo.pruebRecordatorio, 1);
    });

    testWidgets('eliminar pide confirmación', (tester) async {
      final repo = _FakeRepo(recordatorios: [demo()]);
      await montar(tester, repo);

      await tester.tap(find.byKey(const Key('recordatorio_eliminar_r1')));
      await tester.pumpAndSettle();
      expect(find.text('¿Eliminar este recordatorio?'), findsOneWidget);

      await tester.tap(find.text('Eliminar').last);
      await tester.pumpAndSettle();

      expect(repo.eliminados, 1);
      expect(repo.recordatorios, isEmpty);
    });

    testWidgets('cancelar la eliminación no borra nada', (tester) async {
      final repo = _FakeRepo(recordatorios: [demo()]);
      await montar(tester, repo);

      await tester.tap(find.byKey(const Key('recordatorio_eliminar_r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(repo.eliminados, 0);
      expect(repo.recordatorios, hasLength(1));
    });
  });
}
