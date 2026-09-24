import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:window_manager/window_manager.dart';
import '../../../core/constants/catalog_resources.dart';
import '../../../core/theme/theme_controller.dart';
import '../../providers/bloc/auth/auth_bloc.dart';
import '../../providers/bloc/weighing/weighing_bloc.dart';
import '../../widgets/app_sidebar.dart';
import '../../widgets/command_palette.dart';
import '../../widgets/quick_actions_bar.dart';
import '../../widgets/top_nav_bar.dart';
import '../ajustes_inventario/ajustes_inventario_screen.dart';
import '../auditoria/auditoria_screen.dart';
import '../ayuda/ayuda_screen.dart';
import '../catalog/catalog_crud_screen.dart';
import '../catalog/catalog_edit_screen.dart';
import '../dispositivos/dispositivos_screen.dart';
import '../empresa/documentos_empresa_screen.dart';
import '../kardex/kardex_screen.dart';
import '../reports/reports_screen.dart';
import '../seguridad/seguridad_screen.dart';
import '../settings/settings_screen.dart';
import '../settings/ticket_design_screen.dart';
import '../settings/usuarios_screen.dart';
import '../weighing/weighing_form_screen.dart';
import '../weighing/weighing_list_screen.dart';
import 'dashboard_screen.dart';

class HomeShell extends StatefulWidget {
  final ThemeController themeController;
  const HomeShell({super.key, required this.themeController});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  bool _argsProcesados = false;
  bool _sidebarVisible = true;
  bool _commandPaletteOpen = false;
  final List<int> _historial = [];

  late final List<Widget Function(BuildContext)> _pages = [
    (_) => const DashboardScreen(),
    (_) => CatalogCrudScreen(recurso: AppCatalogos.tercerosResource),
    (_) => const UsuariosScreen(),
    (_) => CatalogCrudScreen(recurso: AppCatalogos.camionResource),
    (_) => CatalogCrudScreen(recurso: AppCatalogos.conductorResource),
    (_) => CatalogCrudScreen(recurso: AppCatalogos.transporteResource),
    (_) => CatalogCrudScreen(recurso: AppCatalogos.categoriaResource),
    (_) => CatalogCrudScreen(recurso: AppCatalogos.productoResource),
    (_) => CatalogCrudScreen(recurso: AppCatalogos.almacenResource),
    (_) => const KardexScreen(),
    (_) => const WeighingListScreen(titulo: 'Entradas'),
    (_) => const WeighingListScreen(
          estadoInicial: 'CERRADO',
          titulo: 'Salidas',
        ),
    (_) => const ReportsScreen(),
    (_) => const DispositivosScreen(),
    (_) => const SeguridadScreen(),
    (_) => const DocumentosEmpresaScreen(),
    (_) => SettingsScreen(themeController: widget.themeController),
    (_) => const TicketDesignScreen(),
  ];

  @override
  void initState() {
    super.initState();
    context.read<WeighingBloc>().add(const ListWeighingsEvent());
    ServicesBinding.instance.keyboard.addHandler(_onKey);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_argsProcesados) return;
    _argsProcesados = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is int && args >= 0 && args < _pages.length) {
      _index = args;
    } else if (args is String) {
      final idx = _claveAIndice(args);
      if (idx != -1) _index = idx;
    }
  }

  @override
  void dispose() {
    ServicesBinding.instance.keyboard.removeHandler(_onKey);
    super.dispose();
  }

  int _claveAIndice(String clave) {
    const map = {
      'inicio': 0,
      'terceros': 1,
      'clientes': 1,
      'proveedores': 1,
      'usuarios': 2,
      'camiones': 3,
      'conductores': 4,
      'transportes': 5,
      'categorias': 6,
      'productos': 7,
      'almacenes': 8,
      'kardex': 9,
      'entradas': 10,
      'salidas': 11,
      'reportes': 12,
      'dispositivos': 13,
      'seguridad': 14,
      'documentos_empresa': 15,
      'configuracion': 16,
      'diseno_ticket': 17,
    };
    return map[clave] ?? -1;
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final key = event.logicalKey;
    final kb = HardwareKeyboard.instance;
    final ctrl = kb.isControlPressed || kb.isMetaPressed;
    final shift = kb.isShiftPressed;
    final alt = kb.isAltPressed;

    // ── Teclas de función (sin modificadores) ───────────────────────────────
    if (event is KeyDownEvent && !ctrl && !alt) {
      if (event.physicalKey == LogicalKeyboardKey.f2) {
        _abrirNuevoPesaje();
        return true;
      }
      if (event.physicalKey == LogicalKeyboardKey.f9) {
        _alternarMaximizado();
        return true;
      }
      if (event.physicalKey == LogicalKeyboardKey.f10) {
        _toggleSidebar();
        return true;
      }
      if (event.physicalKey == LogicalKeyboardKey.f11) {
        _alternarPantallaCompleta();
        return true;
      }
      if (key == LogicalKeyboardKey.escape) {
        // Esc: si hay un modal abierto, lo cierra el propio modal. Aquí solo
        // evitamos interferir con el foco de inputs.
        return false;
      }
      // Backspace/Delete para volver atrás si no hay input en foco
      if ((key == LogicalKeyboardKey.backspace ||
              key == LogicalKeyboardKey.delete) &&
          !_hayTextoEnFoco()) {
        _volverAtras();
        return true;
      }
    }

    // Alternativas a F9/F11 para teclados donde la fila F actúa como teclas de
    // medios (FnLock activo) y el SO nunca entrega F9/F11 a la app:
    //   Ctrl+Alt+Enter → maximizar/restaurar   (equivalente a F9)
    //   Ctrl+Enter      → pantalla completa    (equivalente a F11)
    if (event is KeyDownEvent && ctrl && key == LogicalKeyboardKey.enter) {
      if (alt) {
        _alternarMaximizado();
      } else {
        _alternarPantallaCompleta();
      }
      return true;
    }

    // ── Ctrl + tecla ────────────────────────────────────────────────────────
    if (ctrl && !alt) {
      // Ctrl+Q → salir
      if (event is KeyDownEvent && !shift && key == LogicalKeyboardKey.keyQ) {
        _salirDelSistema();
        return true;
      }
      // Ctrl+N → nuevo pesaje
      if (event is KeyDownEvent && !shift && key == LogicalKeyboardKey.keyN) {
        _abrirNuevoPesaje();
        return true;
      }
      // Ctrl+Shift+N → nuevo pesaje manual (mismo form por ahora)
      if (event is KeyDownEvent && shift && key == LogicalKeyboardKey.keyN) {
        _abrirNuevoPesaje();
        return true;
      }
      // Ctrl+Shift+V → nuevo vehículo
      if (event is KeyDownEvent && shift && key == LogicalKeyboardKey.keyV) {
        _abrirNuevoVehiculo();
        return true;
      }
      // Ctrl+Shift+D → nuevo conductor
      if (event is KeyDownEvent && shift && key == LogicalKeyboardKey.keyD) {
        _abrirNuevoConductor();
        return true;
      }
      // Ctrl+Shift+T → módulo de transportes
      if (event is KeyDownEvent && shift && key == LogicalKeyboardKey.keyT) {
        _irA('transportes');
        return true;
      }
      // Ctrl+Shift+L → cambiar tema
      if (event is KeyDownEvent && shift && key == LogicalKeyboardKey.keyL) {
        _alternarTema();
        return true;
      }
      // Ctrl+B → toggle sidebar
      if (event is KeyDownEvent && !shift && key == LogicalKeyboardKey.keyB) {
        _toggleSidebar();
        return true;
      }
      // Ctrl+K → paleta de comandos
      if (event is KeyDownEvent && !shift && key == LogicalKeyboardKey.keyK) {
        _toggleCommandPalette();
        return true;
      }
      // Ctrl+H → inicio
      if (event is KeyDownEvent && !shift && key == LogicalKeyboardKey.keyH) {
        _irA('inicio');
        return true;
      }
      // Ctrl+L → cerrar sesión / bloquear
      if (event is KeyDownEvent && !shift && key == LogicalKeyboardKey.keyL) {
        _cerrarSesion();
        return true;
      }
      // Ctrl+A → ajustes de inventario
      if (event is KeyDownEvent && !shift && key == LogicalKeyboardKey.keyA) {
        _abrirAjustesInventario();
        return true;
      }
      // Ctrl+, → configuración
      if (event is KeyDownEvent && key == LogicalKeyboardKey.comma) {
        _abrirConfiguracion();
        return true;
      }
      // Ctrl+R → sincronizar ahora
      if (event is KeyDownEvent && !shift && key == LogicalKeyboardKey.keyR) {
        context.read<WeighingBloc>().add(SyncWeighingsEvent());
        return true;
      }
      // Ctrl+1..5 → navegación rápida
      if (event is KeyDownEvent) {
        final idx = _numeroCtrl(key);
        if (idx != null) {
          _cambiarIndice(idx);
          return true;
        }
      }
    }

    // ── Alt + tecla (navegación mnemónica) ──────────────────────────────────
    if (alt && !ctrl && event is KeyDownEvent) {
      final destino = _destinoPorAlt(key);
      if (destino != null) {
        _irA(destino);
        return true;
      }
    }

    return false;
  }

  /// Mapea Ctrl+1..5 a índices de página.
  ///   1 → Inicio (0)
  ///   2 → Entradas (10)
  ///   3 → Salidas (11)
  ///   4 → Reportes (12)
  ///   5 → Kardex (9)
  int? _numeroCtrl(LogicalKeyboardKey key) {
    final d = key.keyLabel;
    if (d.isEmpty || d.length != 1) return null;
    switch (d) {
      case '1':
        return _claveAIndice('inicio');
      case '2':
        return _claveAIndice('entradas');
      case '3':
        return _claveAIndice('salidas');
      case '4':
        return _claveAIndice('reportes');
      case '5':
        return _claveAIndice('kardex');
      default:
        return null;
    }
  }

  /// Alt + letra → módulo destino (mnemónico).
  String? _destinoPorAlt(LogicalKeyboardKey key) {
    switch (key) {
      case LogicalKeyboardKey.keyC:
        return 'terceros'; // Clientes / Proveedores
      case LogicalKeyboardKey.keyF:
        return 'camiones'; // Flota
      case LogicalKeyboardKey.keyP:
        return 'productos'; // Productos
      case LogicalKeyboardKey.keyA:
        return 'almacenes'; // Almacenes
      case LogicalKeyboardKey.keyK:
        return 'kardex'; // Kardex
      case LogicalKeyboardKey.keyU:
        return 'usuarios'; // Usuarios
      case LogicalKeyboardKey.keyD:
        return 'dispositivos'; // Dispositivos
      case LogicalKeyboardKey.keyS:
        return 'seguridad'; // Seguridad
      case LogicalKeyboardKey.keyR:
        return 'reportes'; // Reportes
      default:
        return null;
    }
  }

  void _toggleSidebar() =>
      setState(() => _sidebarVisible = !_sidebarVisible);

  /// Menú de navegación para móvil: muestra el mismo sidebar del desktop
  /// (mismas opciones y filtrado por rol) sobre un bottom sheet.
  void _mostrarMenuNavegacion() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.92,
        child: AppSidebar(
          selectedIndex: _index,
          onItemSelected: (i) {
            Navigator.of(ctx).pop();
            _cambiarIndice(i);
          },
          onCollapse: _toggleSidebar,
          onLogout: () {
            Navigator.of(ctx).pop();
            _cerrarSesion();
          },
          onOpenConfig: () {
            Navigator.of(ctx).pop();
            _abrirConfiguracion();
          },
        ),
      ),
    );
  }

  void _toggleCommandPalette() =>
      setState(() => _commandPaletteOpen = !_commandPaletteOpen);

  void _cambiarIndice(int nuevo) {
    if (nuevo == _index) return;
    setState(() {
      if (_historial.length >= 60) _historial.removeAt(0);
      _historial.add(_index);
      _index = nuevo;
    });
  }

  void _irA(String clave) {
    final idx = _claveAIndice(clave);
    if (idx != -1) _cambiarIndice(idx);
  }

  bool _hayTextoEnFoco() {
    final contexto = FocusManager.instance.primaryFocus?.context;
    if (contexto == null) return false;
    return contexto.findAncestorStateOfType<EditableTextState>() != null;
  }

  void _volverAtras() {
    final ruta = ModalRoute.of(context);
    if (ruta != null && !ruta.isCurrent) {
      Navigator.of(context).pop();
      return;
    }
    if (_historial.isEmpty) return;
    setState(() => _index = _historial.removeLast());
  }

  Future<void> _alternarTema() async {
    final actual = widget.themeController.tema;
    await widget.themeController.setTema(
      actual == TemaApp.oscuro ? TemaApp.claro : TemaApp.oscuro,
    );
  }

  Future<void> _alternarPantallaCompleta() async {
    if (!(Platform.isLinux || Platform.isWindows || Platform.isMacOS)) return;
    try {
      await windowManager.ensureInitialized();
      final completa = await windowManager.isFullScreen();
      await windowManager.setFullScreen(!completa);
    } catch (_) {}
  }

  /// Maximiza la ventana o la restaura a su tamaño anterior (F9).
  Future<void> _alternarMaximizado() async {
    if (!(Platform.isLinux || Platform.isWindows || Platform.isMacOS)) return;
    try {
      await windowManager.ensureInitialized();
      final maximizada = await windowManager.isMaximized();
      if (maximizada) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    } catch (_) {}
  }

  /// Cierra la aplicación tras confirmación (Ctrl+Q).
  Future<void> _salirDelSistema() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Salir del sistema'),
        content: const Text('¿Deseas cerrar Balansoft-WS?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      try {
        await windowManager.ensureInitialized();
        await windowManager.close();
        return;
      } catch (_) {
        exit(0);
      }
    }
    SystemNavigator.pop();
  }

  void _abrirNuevoPesaje() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WeighingFormScreen()),
    );
  }

  void _abrirNuevoVehiculo() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            CatalogEditScreen(recurso: AppCatalogos.camionResource),
      ),
    );
  }

  void _abrirNuevoConductor() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            CatalogEditScreen(recurso: AppCatalogos.conductorResource),
      ),
    );
  }

  void _abrirConfiguracion() => _irA('configuracion');

  void _abrirAuditoria() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AuditoriaScreen()),
    );
  }

  void _abrirAjustesInventario() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AjustesInventarioScreen()),
    );
  }

  void _abrirMovimientos() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const WeighingListScreen(titulo: 'Movimientos'),
      ),
    );
  }

  void _abrirAyuda() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AyudaScreen()),
    );
  }

  Future<void> _cerrarSesion() async {
    final authBloc = context.read<AuthBloc>();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Deseas cerrar la sesión actual?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    authBloc.add(const LogoutEvent());
  }

  void _onCommandPaletteCommand(String command) {
    switch (command) {
      case 'new:ticket':
      case 'w:in':
        _abrirNuevoPesaje();
        return;
      case 'new:truck':
      case 'add:camion':
        _abrirNuevoVehiculo();
        return;
      case 'new:driver':
      case 'add:chofer':
      case 'add:conductor':
        _abrirNuevoConductor();
        return;
      case 'go:pesaje_manual':
      case 'go:wm':
      case 'go:pesaje_automatico':
      case 'go:wa':
        _abrirNuevoPesaje();
        return;
      case 'go:ajustes':
        _abrirAjustesInventario();
        return;
      case 'go:auditoria':
        _abrirAuditoria();
        return;
      case 'go:flota':
      case 'go:fleet':
        _irA('camiones');
        return;
      case 'go:clientes':
      case 'go:proveedores':
        _irA('terceros');
        return;
      case 'go:inventario_base':
        _irA('categorias');
        return;
      case 'go:in':
        _irA('entradas');
        return;
      case 'go:out':
        _irA('salidas');
        return;
      case 'go:empresa':
        _irA('documentos_empresa');
        return;
      case 'cfg:theme':
        _alternarTema();
        return;
      case 'cfg:fullscreen':
        _alternarPantallaCompleta();
        return;
      case 'cfg:maximize':
        _alternarMaximizado();
        return;
      case 'cfg:exit':
        _salirDelSistema();
        return;
      case 'cfg:dev':
        _irA('dispositivos');
        return;
      default:
        if (command.startsWith('go:')) _irA(command.substring(3));
    }
  }

  @override
  Widget build(BuildContext context) {
    final usarSidebar = MediaQuery.sizeOf(context).shortestSide >= 600;
    final authState = context.watch<AuthBloc>().state;
    final esOperador =
        authState is AuthAuthenticated && authState.user.isOperador;

    final idx = _index.clamp(0, _pages.length - 1);
    final contenido = Navigator(
      key: ValueKey('nav-$idx'),
      pages: [MaterialPage(child: _pages[idx](context))],
      onDidRemovePage: (_) {},
    );

    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (prev, next) =>
          next is AuthInitial || next is AuthUnauthenticated,
      listener: (context, state) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
      },
      child: Scaffold(
        body: Stack(
          children: [
            if (!usarSidebar)
              _buildMobileBody(esOperador, idx, contenido)
            else
              _buildDesktopBody(idx, contenido),
            if (_commandPaletteOpen)
              CommandPalette(
                onClose: () => setState(() => _commandPaletteOpen = false),
                onExecute: _onCommandPaletteCommand,
              ),
          ],
        ),
      ),
    );
  }

  /// Cuerpo móvil: TopNavBar + QuickActionsBar + contenido + BottomNavBar.
  Widget _buildMobileBody(bool esOperador, int idx, Widget contenido) {
    return Column(
      children: [
        TopNavBar(
          onToggleSidebar: _mostrarMenuNavegacion,
          onLogout: _cerrarSesion,
          onOpenConfig: _abrirConfiguracion,
        ),
        QuickActionsBar(
          onPesajeManual: _abrirNuevoPesaje,
          onPesajeAuto: _abrirNuevoPesaje,
          onAjustesInventario: _abrirAjustesInventario,
          onMovimientos: _abrirMovimientos,
          onAuditoria: _abrirAuditoria,
          onAyuda: _abrirAyuda,
        ),
        Expanded(child: contenido),
        _BottomNavBar(
          indiceActual: idx,
          esOperador: esOperador,
          alSeleccionar: _cambiarIndice,
          abrirMas: _abrirMenuMas,
        ),
      ],
    );
  }

  /// Cuerpo desktop/tablet: TopNavBar + (sidebar | quick actions + contenido).
  Widget _buildDesktopBody(int idx, Widget contenido) {
    return Column(
      children: [
        TopNavBar(
          onToggleSidebar: _toggleSidebar,
          onLogout: _cerrarSesion,
          onOpenConfig: _abrirConfiguracion,
        ),
        Expanded(
          child: Row(
            children: [
              if (_sidebarVisible)
                AppSidebar(
                  selectedIndex: idx,
                  onItemSelected: _cambiarIndice,
                  onCollapse: _toggleSidebar,
                  onLogout: _cerrarSesion,
                  onOpenConfig: _abrirConfiguracion,
                ),
              if (_sidebarVisible)
                const VerticalDivider(width: 1, thickness: 1),
              Expanded(
                child: Column(
                  children: [
                    QuickActionsBar(
                      onPesajeManual: _abrirNuevoPesaje,
                      onPesajeAuto: _abrirNuevoPesaje,
                      onAjustesInventario: _abrirAjustesInventario,
                      onMovimientos: _abrirMovimientos,
                      onAuditoria: _abrirAuditoria,
                      onAyuda: _abrirAyuda,
                    ),
                    Expanded(child: contenido),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _abrirMenuMas(BuildContext context) {
    _mostrarMenuNavegacion();
  }
}

// ── BottomNavBar (móvil) ──────────────────────────────────────────────

class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({
    required this.indiceActual,
    required this.esOperador,
    required this.alSeleccionar,
    required this.abrirMas,
  });

  final int indiceActual;
  final bool esOperador;
  final ValueChanged<int> alSeleccionar;
  final void Function(BuildContext) abrirMas;

  static const _claves = ['inicio', 'entradas', 'salidas', 'reportes'];

  int _idx(String clave) {
    const map = {
      'inicio': 0,
      'entradas': 10,
      'salidas': 11,
      'reportes': 12,
    };
    return map[clave] ?? 0;
  }

  int _navLocal() {
    final actual = indiceActual;
    if (actual == _idx('inicio')) return 0;
    if (actual == _idx('entradas')) return 1;
    if (actual == _idx('salidas')) return 2;
    if (actual == _idx('reportes')) return 3;
    return 4;
  }

  void _alNavegar(BuildContext context, int local) {
    if (local == 4) {
      abrirMas(context);
      return;
    }
    alSeleccionar(_idx(_claves[local]));
  }

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: _navLocal(),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Inicio',
        ),
        NavigationDestination(
          icon: Icon(Icons.arrow_downward_outlined),
          selectedIcon: Icon(Icons.arrow_downward),
          label: 'Entradas',
        ),
        NavigationDestination(
          icon: Icon(Icons.arrow_upward_outlined),
          selectedIcon: Icon(Icons.arrow_upward),
          label: 'Salidas',
        ),
        NavigationDestination(
          icon: Icon(Icons.description_outlined),
          selectedIcon: Icon(Icons.description),
          label: 'Reportes',
        ),
        NavigationDestination(
          icon: Icon(Icons.more_horiz),
          label: 'Más',
        ),
      ],
      onDestinationSelected: (i) => _alNavegar(context, i),
    );
  }
}