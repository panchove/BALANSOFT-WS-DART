import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:balansoft_ws/core/config/menu_config.dart';
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
  Future<User?> refrescarEmpresaEnUsuarioCacheado() async => usuario;

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
    // Menú efectivo siempre el de fábrica: ningún caso hereda el árbol inyectado
    // por otro (estado global de MenuConfig).
    MenuConfig.inyectarParaPruebas(MenuConfig.arbolPorDefecto);
    MenuConfig.errores = <String>[];
  });

  tearDown(() {
    final node = FocusSearchBus.instance.node;
    if (node != null) FocusSearchBus.instance.liberar(node);
    MenuConfig.inyectarParaPruebas(MenuConfig.arbolPorDefecto);
    MenuConfig.errores = <String>[];
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
      refrescarEmpresaUseCase: RefrescarEmpresaUseCase(repo),
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

    test('cada hoja-página tiene índice único y dentro de 0..30', () {
      final paginas =
          hojas(AppSidebar.menuTree).where((n) => n.accion == null).toList();
      final indices = paginas.map((n) => n.index).toList();

      expect(indices.every((i) => i != null), isTrue,
          reason: 'toda hoja-página debe declarar índice explícito');
      expect(indices.toSet().length, indices.length,
          reason: 'no puede haber índices repetidos');
      for (final i in indices) {
        expect(i, inInclusiveRange(0, 30));
      }
    });

    test('las hojas del menú estructurado existen con su acción o clave', () {
      final hojasMenu = hojas(AppSidebar.menuTree);
      MenuNode? buscar(String label) {
        for (final n in hojasMenu) {
          if (n.label == label) return n;
        }
        return null;
      }

      expect(buscar('Peso Automático')?.accion, 'go:pesaje_automatico');
      expect(buscar('Peso Manual')?.accion, 'go:pesaje_manual');
      expect(buscar('Inventario')?.accion, 'go:ajustes');
      expect(buscar('Auditoría del Sistema')?.accion, 'go:auditoria');
      expect(buscar('Ayuda y Soporte')?.accion, 'go:ayuda');
      expect(buscar('Reportes Generales')?.clave, 'reportes');
      expect(buscar('Camiones / Vehículos')?.shortcut, 'Alt+F');
      expect(buscar('Conductores')?.shortcut, 'F8');
      expect(buscar('Configuración')?.clave, 'configuracion');
      expect(buscar('Configuración')?.shortcut, 'Ctrl+,');
      // Nuevos módulos de la estructura pedida.
      expect(buscar('Clientes')?.clave, 'clientes');
      expect(buscar('Proveedores')?.clave, 'proveedores');
      expect(buscar('Ingresos')?.clave, 'ingresos');
      expect(buscar('Despachos')?.clave, 'despachos');
      // Dispositivos separado en vistas independientes: ahora cada una navega
      // por su clave e índice propio (ya no son hojas-acción del shell).
      expect(buscar('Semáforos')?.clave, 'dispositivos_semaforos');
      expect(buscar('Semáforos')?.index, 28);
      expect(buscar('Impresoras')?.clave, 'dispositivos_impresoras');
      expect(buscar('Impresoras')?.index, 30);
      expect(buscar('Básculas')?.clave, 'dispositivos_basculas');
      expect(buscar('Básculas')?.index, 13);
      expect(buscar('Cámaras')?.clave, 'dispositivos_camaras');
      expect(buscar('Cámaras')?.index, 29);
      expect(buscar('Indicadores')?.clave, 'dispositivos_indicadores');
      expect(buscar('Indicadores')?.index, 27);
      // El catálogo de conceptos de inventario (migración 029) es una
      // hoja-página bajo CATÁLOGOS: navega por clave, no por acción.
      expect(buscar('Conceptos de Inventario')?.clave, 'conceptos_inventario');
      expect(buscar('Conceptos de Inventario')?.index, 22);
      // Catálogo de roles (informativo, enlaza a la matriz de accesos).
      expect(buscar('Roles')?.clave, 'roles');
      expect(buscar('Roles')?.index, 23);
      // REPORTES → presets de rango sobre la misma pantalla.
      expect(buscar('Diarios')?.clave, 'reportes_diarios');
      expect(buscar('Diarios')?.index, 24);
      expect(buscar('Mensuales')?.clave, 'reportes_mensuales');
      expect(buscar('Mensuales')?.index, 25);
      expect(buscar('Personalizado')?.clave, 'reportes_personalizado');
      expect(buscar('Personalizado')?.index, 26);
      // AYUDA → opciones que ejecuta el shell (no ocupan índice).
      expect(buscar('Manuales')?.accion, 'go:ayuda_manuales');
      expect(buscar('Página Web')?.accion, 'go:ayuda_pagina');
      expect(buscar('Versión')?.accion, 'go:ayuda_version');
      expect(buscar('Tutorial')?.accion, 'go:ayuda_tutorial');
      // Fuera del menú a propósito: solo desde la paleta (Ctrl+K).
      expect(buscar('Diagnóstico del Sistema'), isNull);
      expect(buscar('Administración de Licencia'), isNull);
      expect(buscar('Conexiones'), isNull);
      expect(buscar('Peso Automático')?.shortcut, 'F1');
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
      for (final rol in ['ADMIN', 'OPERADOR', 'AUDITOR']) {
        expect(accionVisible(rol, 'go:ayuda'), isNotNull, reason: rol);
      }
    });

    test('clavesDisponibles coincide con los índices reales de AccesosDefault',
        () {
      // El mensaje de error de `menu.json` publica esta lista. Si se
      // desincroniza, el usuario escribe una clave que no navega (o repite
      // `terceros` en Clientes y Proveedores, como ocurrió) y el diagnóstico
      // le miente. Toda clave publicada debe resolver a un índice real.
      for (final clave in MenuConfig.clavesDisponibles) {
        expect(
          AccesosDefault.indiceDe(clave),
          greaterThanOrEqualTo(0),
          reason: '"$clave" está en clavesDisponibles pero no en indiceDe',
        );
      }
      // Y al revés: los índices con pantalla deben anunciarse.
      for (final clave in ['clientes', 'proveedores', 'ingresos', 'despachos']) {
        expect(MenuConfig.clavesDisponibles, contains(clave));
      }
    });
  });

  testWidgets('sidebar muestra la estructura pedida con sus secciones',
      (tester) async {
    await renderSidebar(tester, sidebarApp('ADMIN'));

    // Encabezados de sección (siempre visibles, no colapsables).
    for (final seccion in [
      'CATÁLOGOS',
      'GESTIÓN',
      'CONSULTAR',
      'REPORTES',
      'MANTENIMIENTO',
      'AYUDA Y SOPORTE',
    ]) {
      expect(find.text(seccion), findsOneWidget, reason: 'falta $seccion');
    }

    // Hojas de la estructura pedida, todas visibles.
    for (final label in [
      'Clientes',
      'Proveedores',
      'Transportes',
      'Conductores',
      'Camiones / Vehículos',
      'Categorías',
      'Productos',
      'Almacenes',
      'Peso Manual',
      'Peso Automático',
      'Inventario',
      'Entradas',
      'Salidas',
      'Ingresos',
      'Despachos',
      'Auditoría del Sistema',
      'Reportes Generales',
      'Kardex',
      'Empresa y Documentos',
      'Usuarios del Sistema',
      'Seguridad y Accesos',
      'Semáforos',
      'Impresoras',
      'Básculas',
      'Diseño de Ticket',
      'Configuración',
      'Ayuda y Soporte',
    ]) {
      expect(find.text(label), findsOneWidget, reason: 'falta $label');
    }
    expect(find.text('F1'), findsOneWidget);
  });

  testWidgets('sidebar OPERADOR oculta módulos restringidos', (tester) async {
    await renderSidebar(tester, sidebarApp('OPERADOR'));

    expect(find.text('Usuarios del Sistema'), findsNothing);
    expect(find.text('Seguridad y Accesos'), findsNothing);
    expect(find.text('Configuración'), findsNothing);
    expect(find.text('Semáforos'), findsNothing);
    expect(find.text('Básculas'), findsNothing);
    expect(find.text('Ayuda y Soporte'), findsOneWidget);
    expect(find.text('Entradas'), findsOneWidget);
  });

  testWidgets('sidebar OPERADOR oculta las hojas solo de paleta',
      (tester) async {
    await renderSidebar(tester, sidebarApp('OPERADOR'));

    expect(find.text('Diagnóstico del Sistema'), findsNothing);
    expect(find.text('Administración de Licencia'), findsNothing);
    expect(find.text('Conexiones'), findsNothing);
    expect(find.text('Usuarios del Sistema'), findsNothing);
    expect(find.text('Ayuda y Soporte'), findsOneWidget);
  });

  testWidgets('sidebar dispara onAction en hojas-acción', (tester) async {
    final acciones = <String>[];
    await renderSidebar(
      tester,
      sidebarApp('ADMIN', onAction: acciones.add),
    );

    await tester.tap(find.text('Peso Manual'));
    await tester.pumpAndSettle();
    expect(acciones, ['go:pesaje_manual']);

    await tester.tap(find.text('Inventario'));
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

    await tester.tap(find.text('Reportes Generales'));
    await tester.pumpAndSettle();
    expect(indices, [9, 12]);

    await tester.tap(find.text('Usuarios del Sistema'));
    await tester.pumpAndSettle();
    expect(indices, [9, 12, 2]);
  });

  test('la matriz por defecto sigue marcando reportes como visible', () {
    expect(AccesosDefault.acceso('OPERADOR', 'reportes'), 'editar');
    expect(AccesosDefault.modulos['reportes'], 'Reportes Generales');
    // El rol TRABAJADOR se fusionó en OPERADOR: ya no existe en la matriz
    // (un valor heredado cae al `ninguno` por defecto, sin exponer nada).
    expect(AccesosDefault.roles, ['ADMIN', 'OPERADOR', 'AUDITOR']);
    expect(AccesosDefault.acceso('TRABAJADOR', 'reportes'), 'ninguno');
  });

  group('Separadores del menú (menu.json)', () {
    test('filtrarMenu conserva los separadores y descarta los colgantes',
        () async {
      MenuConfig.inyectarParaPruebas(MenuConfig.desdeJson([
        {
          'tipo': 'seccion',
          'label': 'PRINCIPAL',
          'hijos': [
            {'tipo': 'opcion', 'label': 'Inicio', 'clave': 'inicio'},
            {'tipo': 'separador'},
            {'tipo': 'opcion', 'label': 'Kardex', 'clave': 'kardex'},
            // Solo visible para ADMIN: al filtrar por OPERADOR cae y deja un
            // separador colgante que `filtrarMenu` debe recortar.
            {'tipo': 'separador'},
            {'tipo': 'opcion', 'label': 'Seguridad', 'clave': 'seguridad'},
          ],
        },
      ]));

      final admin = AppSidebar.filtrarMenu(AppSidebar.menuTree, 'ADMIN');
      final hijosAdmin = admin.single.children!;
      expect(hijosAdmin.map((n) => n.esSeparador), [false, true, false, true, false]);

      final operador = AppSidebar.filtrarMenu(AppSidebar.menuTree, 'OPERADOR');
      final hijosOperador = operador.single.children!;
      // Inicio y Kardex sobreviven; el separador final se recorta.
      expect(hijosOperador.last.esSeparador, isFalse,
          reason: 'no puede quedar una línea separadora al final');
      expect(hijosOperador.first.esSeparador, isFalse);
      expect(hijosOperador.where((n) => n.esSeparador), hasLength(1));
      expect(hijosOperador.map((n) => n.label),
          containsAll(['Inicio', 'Kardex']));
    });

    testWidgets('el sidebar dibuja la línea separadora', (tester) async {
      MenuConfig.inyectarParaPruebas(MenuConfig.desdeJson([
        {
          'tipo': 'seccion',
          'label': 'INFORMACIÓN',
          'hijos': [
            {'tipo': 'opcion', 'label': 'Inicio', 'clave': 'inicio'},
            {'tipo': 'separador'},
            {
              'tipo': 'opcion',
              'label': 'Kardex',
              'clave': 'kardex',
              'atajo': 'Alt+K',
            },
          ],
        },
        {
          'tipo': 'seccion',
          'label': 'AYUDA Y SOPORTE',
          'hijos': [
            {'tipo': 'opcion', 'label': 'Ayuda', 'accion': 'go:ayuda'},
          ],
        },
      ]));

      await renderSidebar(tester, sidebarApp('ADMIN'));

      expect(find.byKey(const Key('menu_separador')), findsOneWidget);
      expect(find.text('Inicio'), findsOneWidget);
      expect(find.text('Kardex'), findsOneWidget);
      expect(find.text('Alt+K'), findsOneWidget);
      expect(find.text('Ayuda y Soporte'), findsOneWidget);
    });

    testWidgets('dos opciones con la MISMA clave no rompen el sidebar',
        (tester) async {
      // Un `menu.json` editado a mano puede repetir `clave` (p. ej. Clientes y
      // Proveedores apuntando a `terceros`). Antes colisionaban las keys de
      // widget y el árbol lanzaba «Duplicate keys found». La segunda opción
      // conserva la key estable `menu_terceros`; la repetida se desambigua.
      MenuConfig.inyectarParaPruebas(MenuConfig.desdeJson([
        {
          'tipo': 'seccion',
          'label': 'CATÁLOGOS',
          'hijos': [
            {'tipo': 'opcion', 'label': 'Clientes', 'clave': 'terceros'},
            {'tipo': 'opcion', 'label': 'Proveedores', 'clave': 'terceros'},
          ],
        },
      ]));

      await renderSidebar(tester, sidebarApp('ADMIN'));

      expect(find.text('Clientes'), findsOneWidget);
      expect(find.text('Proveedores'), findsOneWidget);
      expect(find.byKey(const Key('menu_terceros')), findsOneWidget);
    });

    testWidgets('la clave duplicada queda avisada en MenuConfig.errores',
        (tester) async {
      MenuConfig.errores = const [];
      MenuConfig.desdeJson([
        {
          'tipo': 'seccion',
          'label': 'CATÁLOGOS',
          'hijos': [
            {'tipo': 'opcion', 'label': 'Clientes', 'clave': 'terceros'},
            {'tipo': 'opcion', 'label': 'Proveedores', 'clave': 'terceros'},
          ],
        },
      ]);

      expect(
        MenuConfig.errores.any((e) => e.contains('"terceros" se repite')),
        isTrue,
        reason: 'el menú sigue mostrándose, pero el usuario debe enterarse',
      );
    });

    testWidgets('reordenar y quitar opciones en el JSON cambia el sidebar',
        (tester) async {
      MenuConfig.inyectarParaPruebas(MenuConfig.desdeJson([
        {
          'tipo': 'seccion',
          'label': 'INFORMACIÓN',
          'hijos': [
            {
              'tipo': 'opcion',
              'label': 'Kardex',
              'clave': 'kardex',
              'icono': 'table_rows_outlined',
            },
            {
              'tipo': 'opcion',
              'label': 'Inicio',
              'clave': 'inicio',
              'icono': 'dashboard_outlined',
            },
          ],
        },
        {
          'tipo': 'seccion',
          'label': 'AYUDA Y SOPORTE',
          'hijos': [
            {'tipo': 'opcion', 'label': 'Ayuda', 'accion': 'go:ayuda'},
          ],
        },
      ]));

      await renderSidebar(tester, sidebarApp('ADMIN'));

      // «Terceros» ya no está en el menú (se eliminó del JSON).
      expect(find.text('Terceros'), findsNothing);
      // El orden visual es el del JSON: Kardex va por encima de Inicio.
      final yKardex = tester.getTopLeft(find.text('Kardex')).dy;
      final yInicio = tester.getTopLeft(find.text('Inicio')).dy;
      expect(yKardex, lessThan(yInicio));
    });
  });

  group('Atajos y alias de docs/INPUTS_MAP.md', () {
    test('los alias de la paleta apuntan a destinos reales', () {
      const paginas = {
        'inicio',
        'terceros',
        'clientes',
        'proveedores',
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
        'ingresos',
        'despachos',
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
