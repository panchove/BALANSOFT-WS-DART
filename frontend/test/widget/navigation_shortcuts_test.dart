import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:balansoft_ws/core/constants/accesos_default.dart';
import 'package:balansoft_ws/core/theme/app_theme.dart';
import 'package:balansoft_ws/core/utils/focus_search_bus.dart';
import 'package:balansoft_ws/data/datasources/local/local_storage.dart';
import 'package:balansoft_ws/data/datasources/remote/api_client.dart';
import 'package:balansoft_ws/data/repositories/accesos_repository.dart';
import 'package:balansoft_ws/domain/entities/user.dart';
import 'package:balansoft_ws/domain/repositories/i_auth_repository.dart';
import 'package:balansoft_ws/domain/usecases/auth_usecases.dart';
import 'package:balansoft_ws/injection.dart' as di;
import 'package:balansoft_ws/presentation/providers/bloc/auth/auth_bloc.dart';
import 'package:balansoft_ws/presentation/screens/dashboard/home_shell.dart';
import 'package:balansoft_ws/presentation/widgets/app_sidebar.dart';
import 'package:balansoft_ws/presentation/widgets/command_palette.dart';

/// Fake de autenticación: devuelve siempre el usuario indicado.
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
  Future<SesionRestaurada> restoreSession() async => SesionRestaurada.ok;

  @override
  Future<void> cacheUser(User user) async {}

  @override
  Future<void> clearCache() async {}
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super();
}

class _FakeLocalStorage extends LocalStorage {
  @override
  Future<({String host, int port})> getScaleConfig() async =>
      (host: '127.0.0.1', port: 5555);

  @override
  Future<String> getDescargasDir() async => '/tmp/descargas';
}

User _usuario(String rol) => User(
      idUsuario: 'u-$rol',
      nombre: 'Usuario $rol',
      email: '$rol@balansoft.com.ve',
      rol: rol,
      idEmpresa: 'emp-1',
    );

/// Sidebar sobre la matriz por defecto ([AccesosDefault]): el repo nunca carga
/// (sin backend en test), por lo que `puedeVer` resuelve al default.
class _FakeAccesosRepository extends AccesosRepository {
  _FakeAccesosRepository()
      : super(
          apiClient: _FakeApiClient(),
          localStorage: _FakeLocalStorage(),
        );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  setUp(() async {
    await di.sl.reset();
    di.sl.registerLazySingleton<ApiClient>(_FakeApiClient.new);
    di.sl.registerLazySingleton<LocalStorage>(_FakeLocalStorage.new);
    di.sl.registerLazySingleton<AccesosRepository>(
      _FakeAccesosRepository.new,
    );
  });

  tearDown(() {
    final node = FocusSearchBus.instance.node;
    if (node != null) FocusSearchBus.instance.liberar(node);
  });

  Widget sidebarApp(
    String rol, {
    void Function(int)? onItemSelected,
    void Function(String)? onAction,
  }) {
    final repo = _FakeAuthRepository(_usuario(rol));
    final authBloc = AuthBloc(
      loginUseCase: LoginUseCase(repo),
      registerUseCase: RegisterUseCase(repo),
      logoutUseCase: LogoutUseCase(repo),
      getCachedUserUseCase: GetCachedUserUseCase(repo),
      restoreSessionUseCase: RestoreSessionUseCase(repo),
      forgotPasswordUseCase: ForgotPasswordUseCase(repo),
      resetPasswordUseCase: ResetPasswordUseCase(repo),
    )..add(const CheckAuthStatusEvent());

    return BlocProvider<AuthBloc>.value(
      value: authBloc,
      child: MaterialApp(
        theme: buildLightTheme(),
        locale: const Locale('es'),
        supportedLocales: const [Locale('es'), Locale('en'), Locale('pt')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: Row(
            children: [
              AppSidebar(
                selectedIndex: 0,
                onItemSelected: onItemSelected ?? (_) {},
                onAction: onAction ?? (_) {},
                onCollapse: () {},
                onLogout: () {},
                onOpenConfig: () {},
              ),
              const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
  }

  /// Los grupos del sidebar arrancan colapsados (ver `_inicializarGruposColapsados`),
  /// así que hay que abrirlos antes de poder tocar un módulo que vive dentro.
  Future<void> expandirGrupos(WidgetTester tester) async {
    for (final grupo in [
      'Flota y Transporte',
      'Inventario Base',
      'REPORTES',
      'MANTENIMIENTO',
    ]) {
      final finder = find.text(grupo);
      if (finder.evaluate().isNotEmpty) {
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }
    }
  }

  Future<void> renderSidebar(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(child);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  group('Árbol de menú', () {
    List<MenuNode> hojas(List<MenuNode> nodos) {
      final out = <MenuNode>[];
      void recorrer(List<MenuNode> lista) {
        for (final n in lista) {
          if (n.isLeaf) {
            out.add(n);
          } else if (n.children != null) {
            recorrer(n.children!);
          }
        }
      }

      recorrer(nodos);
      return out;
    }

    test('cada hoja-página tiene índice único y dentro de 0..17', () {
      final paginas =
          hojas(AppSidebar.menuTree).where((n) => n.accion == null).toList();
      final indices = paginas.map((n) => n.index).toList();

      expect(indices.every((i) => i != null), isTrue,
          reason: 'toda hoja-página debe declarar índice explícito');
      expect(indices.toSet().length, indices.length,
          reason: 'no puede haber índices repetidos');
      for (final i in indices) {
        expect(i, inInclusiveRange(0, 17));
      }
    });

    test('las hojas de docs/NAV.md existen con su acción o clave', () {
      final hojasMenu = hojas(AppSidebar.menuTree);
      MenuNode? buscar(String label) {
        for (final n in hojasMenu) {
          if (n.label == label) return n;
        }
        return null;
      }

      expect(buscar('Pesaje Automático')?.accion, 'go:pesaje_automatico');
      expect(buscar('Pesaje Manual')?.accion, 'go:pesaje_manual');
      expect(buscar('Ajustes de Inventario')?.accion, 'go:ajustes');
      expect(buscar('Auditoría del Sistema')?.accion, 'go:auditoria');
      expect(buscar('Ayuda')?.accion, 'go:ayuda');
      expect(buscar('Reportes Generales')?.clave, 'reportes');
      expect(buscar('Camiones / Vehículos')?.shortcut, 'Alt+F');
      expect(buscar('Conductores')?.shortcut, 'F8');
      expect(buscar('Configuración')?.clave, 'configuracion');
      expect(buscar('Configuración')?.shortcut, 'Ctrl+,');
      // Fuera del menú a propósito: solo desde la paleta (Ctrl+K).
      expect(buscar('Diagnóstico del Sistema'), isNull);
      expect(buscar('Administración de Licencia'), isNull);
      expect(buscar('Conexiones'), isNull);
      expect(buscar('Pesaje Automático')?.shortcut, 'F1');
    });

    test('las hojas-acción no ocupan índice ni clave de matriz', () {
      for (final n in hojas(AppSidebar.menuTree)) {
        if (n.accion != null) {
          expect(n.index, isNull, reason: '${n.label} no debe tener índice');
          expect(n.clave, isNull,
              reason: '${n.label} no debe usar clave de la matriz');
          expect(n.rolesPermitidos, isNotNull,
              reason:
                  '${n.label} debe declarar roles (no hay clave que filtrar)');
        }
      }
    });

    MenuNode? accionVisibleEn(List<MenuNode> nodos, String accion) {
      for (final n in nodos) {
        if (n.accion == accion) return n;
        if (n.children != null) {
          final encontrado = accionVisibleEn(n.children!, accion);
          if (encontrado != null) return encontrado;
        }
      }
      return null;
    }

    test('filtrarMenu oculta las hojas-acción según el rol', () {
      MenuNode? accionVisible(String rol, String accion) {
        for (final n in AppSidebar.filtrarMenu(AppSidebar.menuTree, rol)) {
          if (n.accion == accion) return n;
          if (n.children != null) {
            final encontrado = accionVisibleEn(n.children!, accion);
            if (encontrado != null) return encontrado;
          }
        }
        return null;
      }

      // Auditoría: ADMIN y AUDITOR.
      expect(accionVisible('AUDITOR', 'go:auditoria'), isNotNull);
      expect(accionVisible('OPERADOR', 'go:auditoria'), isNull);
      // Ayuda: todos los roles.
      for (final rol in ['ADMIN', 'OPERADOR', 'AUDITOR', 'TRABAJADOR']) {
        expect(accionVisible(rol, 'go:ayuda'), isNotNull, reason: rol);
      }
    });
  });

  testWidgets('sidebar arranca con los grupos colapsados', (tester) async {
    await renderSidebar(tester, sidebarApp('ADMIN'));

    // Solo se ven las hojas sueltas y los encabezados de grupo.
    expect(find.text('Inicio'), findsOneWidget);
    expect(find.text('Pesaje Manual'), findsOneWidget);
    expect(find.text('Kardex'), findsOneWidget);
    for (final grupo in [
      'Flota y Transporte',
      'Inventario Base',
      'REPORTES',
      'MANTENIMIENTO',
    ]) {
      expect(find.text(grupo), findsOneWidget, reason: 'falta $grupo');
    }
    // Hijos de grupo aún ocultos.
    expect(find.text('Ingresos (Entradas)'), findsNothing);
    expect(find.text('Productos'), findsNothing);
    expect(find.text('Usuarios del Sistema'), findsNothing);

    await expandirGrupos(tester);

    for (final label in [
      'Ajustes de Inventario',
      'Ingresos (Entradas)',
      'Despachos (Salidas)',
      'Reportes Generales',
      'Auditoría del Sistema',
      'Usuarios del Sistema',
      'Seguridad y Accesos',
      'Dispositivos de Campo',
      'Empresa y Documentos',
      'Diseño de Ticket',
      'Configuración',
    ]) {
      expect(find.text(label), findsOneWidget, reason: 'falta $label');
    }
    expect(find.text('Ayuda'), findsOneWidget);
    expect(find.text('F1'), findsOneWidget);
  });

  testWidgets('sidebar OPERADOR oculta módulos restringidos', (tester) async {
    await renderSidebar(tester, sidebarApp('OPERADOR'));
    await expandirGrupos(tester);

    expect(find.text('Usuarios del Sistema'), findsNothing);
    expect(find.text('Seguridad y Accesos'), findsNothing);
    expect(find.text('Configuración'), findsNothing);
    expect(find.text('Ayuda'), findsOneWidget);
    expect(find.text('Ingresos (Entradas)'), findsOneWidget);
  });

  testWidgets('sidebar OPERADOR oculta módulos restringidos', (tester) async {
    await renderSidebar(tester, sidebarApp('OPERADOR'));

    expect(find.text('Diagnóstico del Sistema'), findsNothing);
    expect(find.text('Administración de Licencia'), findsNothing);
    expect(find.text('Conexiones'), findsNothing);
    expect(find.text('Usuarios del Sistema'), findsNothing);
    expect(find.text('Ayuda'), findsOneWidget);
  });

  testWidgets('sidebar dispara onAction en hojas-acción', (tester) async {
    final acciones = <String>[];
    await renderSidebar(
      tester,
      sidebarApp('ADMIN', onAction: acciones.add),
    );

    await tester.tap(find.text('Pesaje Manual'));
    await tester.pumpAndSettle();
    expect(acciones, ['go:pesaje_manual']);

    await expandirGrupos(tester);
    await tester.tap(find.text('Ajustes de Inventario'));
    await tester.pumpAndSettle();
    expect(acciones, ['go:pesaje_manual', 'go:ajustes']);
  });

  testWidgets('sidebar dispara onItemSelected en páginas con su índice',
      (tester) async {
    final indices = <int>[];
    await renderSidebar(
      tester,
      sidebarApp('ADMIN', onItemSelected: indices.add),
    );

    await tester.tap(find.text('Kardex'));
    await tester.pumpAndSettle();
    expect(indices, [9]);

    await expandirGrupos(tester);
    await tester.tap(find.text('Reportes Generales'));
    await tester.pumpAndSettle();
    expect(indices, [9, 12]);

    await tester.tap(find.text('Usuarios del Sistema'));
    await tester.pumpAndSettle();
    expect(indices, [9, 12, 2]);
  });

  test('la matriz por defecto sigue marcando reportes como visible', () {
    expect(AccesosDefault.acceso('OPERADOR', 'reportes'), 'editar');
    expect(AccesosDefault.acceso('TRABAJADOR', 'reportes'), 'ninguno');
    expect(AccesosDefault.modulos['reportes'], 'Reportes Generales');
  });

  group('Atajos y alias de docs/INPUTS_MAP.md', () {
    test('los alias de la paleta apuntan a destinos reales', () {
      const paginas = {
        'inicio',
        'terceros',
        'usuarios',
        'camiones',
        'conductores',
        'transportes',
        'categorias',
        'productos',
        'almacenes',
        'kardex',
        'entradas',
        'salidas',
        'reportes',
        'dispositivos',
        'seguridad',
        'documentos_empresa',
        'configuracion',
        'diseno_ticket',
      };
      final destinos = {
        ...paginas,
        'pesaje_manual',
        'pesaje_automatico',
        'ajustes',
        'auditoria',
        'diagnostico',
        'licencia',
        'conexiones',
        'ayuda',
      };

      expect(HomeShell.aliasAcciones, isNotEmpty);
      for (final entrada in HomeShell.aliasAcciones.entries) {
        expect(
          destinos,
          contains(entrada.value),
          reason: 'el alias go:${entrada.key} apunta a «${entrada.value}», '
              'que no es un destino válido',
        );
      }
      expect(HomeShell.aliasAcciones['wm'], 'pesaje_manual');
      expect(HomeShell.aliasAcciones['wa'], 'pesaje_automatico');
      expect(HomeShell.aliasAcciones['in'], 'entradas');
      expect(HomeShell.aliasAcciones['out'], 'salidas');
      expect(HomeShell.aliasAcciones['fleet'], 'camiones');
    });

    test('cada atajo de creación del doc tiene su equivalente en el menú', () {
      void recorrer(List<MenuNode> nodos, void Function(MenuNode) visita) {
        for (final n in nodos) {
          visita(n);
          if (n.children != null) recorrer(n.children!, visita);
        }
      }

      final atajos = <String>{};
      recorrer(AppSidebar.menuTree, (n) {
        final s = n.shortcut;
        if (s != null) atajos.addAll(s.split('/').map((e) => e.trim()));
      });

      for (final atajo in [
        'F1',
        'F2',
        'F8',
        'Alt+F',
        'Alt+C',
        'Alt+P',
        'Alt+A',
        'Alt+K',
        'Alt+U',
        'Alt+D',
        'Alt+S',
        'Ctrl+1',
        'Ctrl+2',
        'Ctrl+3',
        'Ctrl+4',
        'Ctrl+A',
        'Ctrl+,',
        'Ctrl+⇧+T',
      ]) {
        expect(atajos, contains(atajo), reason: 'falta el atajo $atajo');
      }
    });
  });

  group('FocusSearchBus', () {
    testWidgets('enfocar y liberar el campo registrado', (tester) async {
      final bus = FocusSearchBus.instance;
      final nodo = FocusNode();
      addTearDown(nodo.dispose);

      expect(bus.enfocar(), isFalse, reason: 'sin registro no hace nada');

      bus.registrar(nodo);
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: TextField(focusNode: nodo))));

      expect(bus.enfocar(), isTrue);
      await tester.pump();
      expect(nodo.hasFocus, isTrue);

      bus.liberar(nodo);
      expect(bus.enfocar(), isFalse);
    });

    test('el texto pendiente se consume una sola vez', () {
      final bus = FocusSearchBus.instance;
      bus.registrarTexto('#123');
      expect(bus.tomarTexto(), '#123');
      expect(bus.tomarTexto(), isNull);
    });
  });

  group('Paleta de comandos', () {
    Future<List<String>> ejecutar(WidgetTester tester, String texto) async {
      final ejecutados = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          home: Scaffold(
            body: CommandPalette(
              onClose: () {},
              onExecute: ejecutados.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), texto);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      return ejecutados;
    }

    testWidgets('t:#123 ejecuta la búsqueda de boleto', (tester) async {
      expect(await ejecutar(tester, 't:#123'), ['buscar:t:#123']);
    });

    testWidgets('p:A12BC3 ejecuta la búsqueda de placa', (tester) async {
      expect(await ejecutar(tester, 'p:A12BC3'), ['buscar:p:A12BC3']);
    });

    testWidgets('c:V12345678 ejecuta la búsqueda de conductor', (tester) async {
      expect(await ejecutar(tester, 'c:V12345678'), ['buscar:c:V12345678']);
    });

    testWidgets('un prefijo sin parámetro no ejecuta nada', (tester) async {
      expect(await ejecutar(tester, 't:'), isEmpty);
    });

    testWidgets('las acciones nuevas del menú están en la paleta',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          home: Scaffold(
            body: CommandPalette(onClose: () {}, onExecute: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Se localizan por etiqueta visible (la paleta muestra el label, no el id)
      // escribiéndola en el buscador.
      for (final consulta in [
        'Diagnóstico',
        'Licencia',
        'Conexiones',
        'Ayuda',
        'Camiones',
        'Conductores',
        'Documentos',
      ]) {
        await tester.enterText(find.byType(TextField), consulta);
        await tester.pumpAndSettle();
        expect(
          find.textContaining(consulta, findRichText: true),
          findsWidgets,
          reason: 'la paleta debe ofrecer resultados para «$consulta»',
        );
      }
    });
  });
}
