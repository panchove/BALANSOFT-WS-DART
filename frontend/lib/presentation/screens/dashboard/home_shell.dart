import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:window_manager/window_manager.dart';
import '../../../application/backup/auto_backup_service.dart';
import '../../../core/config/app_config.dart';
import '../../../core/config/menu_config.dart';
import '../../../core/constants/catalog_resources.dart';
import '../../../core/i18n/locale_controller.dart';
import '../../../core/i18n/translations.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/services/dialog_keyboard.dart';
import '../../../core/services/modal_manager.dart';
import '../../../core/utils/focus_search_bus.dart';
import '../../../core/utils/report_presets.dart';
import '../../../core/widgets/keyboard_dialog_wrapper.dart';
import '../../../core/widgets/welcome_guide_dialog.dart';
import '../../../data/datasources/local/local_storage.dart';
import '../../../domain/entities/user.dart';
import '../../../injection.dart' as di;
import '../../providers/bloc/auth/auth_bloc.dart';
import '../../providers/bloc/catalog_crud/catalog_crud_cubit.dart';
import '../../providers/bloc/weighing/weighing_bloc.dart';
import '../../widgets/app_sidebar.dart';
import '../../widgets/command_palette.dart';
import '../../widgets/mobile_nav_sheet.dart';
import '../../widgets/quick_actions_bar.dart';
import '../../widgets/top_nav_bar.dart';
import '../ajustes_inventario/ajustes_inventario_screen.dart';
import '../inventario/conceptos_kardex_screen.dart';
import '../auditoria/auditoria_screen.dart';
import '../ayuda/ayuda_screen.dart';
import '../catalog/catalog_crud_screen.dart';
import '../catalog/catalog_edit_screen.dart';
import '../dispositivos/dispositivos_screen.dart';
import '../empresa/documentos_empresa_screen.dart';
import '../kardex/kardex_screen.dart';
import '../reports/reports_screen.dart';
import '../roles/roles_screen.dart';
import '../seguridad/seguridad_screen.dart';
import '../sesiones/sesiones_screen.dart';
import '../settings/initial_setup_screen.dart';
import '../settings/license_admin_screen.dart';
import '../settings/settings_screen.dart';
import '../settings/system_diagnostics_screen.dart';
import '../settings/ticket_design_screen.dart';
import '../settings/usuarios_screen.dart';
import '../settings/connections_screen.dart';
import '../weighing/weighing_form_screen.dart';
import '../weighing/weighing_list_screen.dart';
import '../../../domain/entities/weighing.dart';
import 'dashboard_screen.dart';

class HomeShell extends StatefulWidget {
  final ThemeController themeController;
  const HomeShell({super.key, required this.themeController});

  static const Map<String, String> aliasAcciones = {
    'wm': 'pesaje_manual',
    'wa': 'pesaje_automatico',
    'in': 'entradas',
    'out': 'salidas',
    'fleet': 'camiones',
    'cfg': 'configuracion',
  };

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
    (_) => const DashboardScreen(),                                      // 0  Inicio
    (_) => CatalogCrudScreen(recurso: AppCatalogos.tercerosResource),    // 1  Terceros
    (_) => const UsuariosScreen(),                                       // 2  Usuarios
    (_) => CatalogCrudScreen(recurso: AppCatalogos.camionResource),      // 3  Camiones
    (_) => CatalogCrudScreen(recurso: AppCatalogos.conductorResource),   // 4  Conductores
    (_) => CatalogCrudScreen(recurso: AppCatalogos.transporteResource),  // 5  Transportes
    (_) => CatalogCrudScreen(recurso: AppCatalogos.categoriaResource),   // 6  Categorías
    (_) => CatalogCrudScreen(recurso: AppCatalogos.productoResource),    // 7  Productos
    (_) => CatalogCrudScreen(recurso: AppCatalogos.almacenResource),     // 8  Almacenes
    (_) => const KardexScreen(),                                         // 9  Kardex
    (_) => const WeighingListScreen(titulo: 'Entradas'),                 // 10 Entradas
    (_) => const WeighingListScreen(estadoInicial: 'CERRADO', titulo: 'Salidas'), // 11 Salidas
    (_) => const ReportsScreen(),                                        // 12 Reportes Generales
    (_) => const DispositivosScreen(),                                   // 13 Dispositivos
    (_) => const SeguridadScreen(),                                      // 14 Seguridad
    (_) => const DocumentosEmpresaScreen(),                              // 15 Empresa
    (_) => SettingsScreen(                                               // 16 Configuración
          themeController: widget.themeController,
          localeController: di.sl<LocaleController>(),
        ),
    (_) => const TicketDesignScreen(),                                   // 17 Diseño Ticket
    (_) => CatalogCrudScreen(recurso: AppCatalogos.clienteResource),     // 18 Clientes
    (_) => CatalogCrudScreen(recurso: AppCatalogos.proveedorResource),   // 19 Proveedores
    (_) => const RolesScreen(),                                          // 20 Roles
    (_) => const WeighingListScreen(tipoMovimiento: TipoMovimientoListado.ingreso), // 21 Ingresos
    (_) => const WeighingListScreen(tipoMovimiento: TipoMovimientoListado.despacho), // 22 Despachos
    (_) => const DispositivosScreen(initialTab: 0),                      // 23 Básculas
    (_) => const DispositivosScreen(initialTab: 1),                      // 24 Indicadores
    (_) => const DispositivosScreen(initialTab: 2),                      // 25 Semáforos
    (_) => const DispositivosScreen(initialTab: 3),                      // 26 Cámaras
    (_) => const DispositivosScreen(initialTab: 5),                      // 27 Barreras
    (_) => const DispositivosScreen(initialTab: 4),                      // 28 Impresoras
    (_) => const ConceptosKardexScreen(),                                // 29 Conceptos Kardex
    (_) => const ReportsScreen(preset: ReportPreset.diarios),            // 30 Diarios
    (_) => const ReportsScreen(preset: ReportPreset.mensuales),          // 31 Mensuales
    (_) => const ReportsScreen(preset: ReportPreset.personalizado),      // 32 Personalizado
  ];

  @override
  void initState() {
    super.initState();
    context.read<WeighingBloc>().add(const ListWeighingsEvent());
    ServicesBinding.instance.keyboard.addHandler(_onKey);
    WidgetsBinding.instance.addPostFrameCallback((_) => _abrirOnboardingSiFalta());
    AutoBackupService.instance.iniciar();
  }

  Future<void> _abrirOnboardingSiFalta() async {
    if (AppConfig.onboardingCompletado || !mounted) return;
    final usuario = await di.sl<LocalStorage>().getCachedUser();
    if (!mounted || usuario == null || !_esAdmin(usuario)) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => KeyboardDialogWrapper(
        onEscape: () => Navigator.of(ctx).pop(),
        child: Dialog(
          child: InitialSetupScreen(
            localeController: di.sl<LocaleController>(),
            onFinish: () {
              Navigator.of(ctx).pop();
              if (mounted) setState(() {});
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _abrirTutorialSiEsPrimeraVez());
            },
          ),
        ),
      ),
    );
  }

  Future<void> _abrirTutorialSiEsPrimeraVez() async {
    if (AppConfig.tutorialVisto ||
        !AppConfig.onboardingCompletado ||
        !mounted) {
      return;
    }
    final usuario = await di.sl<LocalStorage>().getCachedUser();
    if (!mounted || usuario == null || !_esAdmin(usuario)) return;
    await mostrarGuiaRapida(context, marcarVisto: true);
  }

  bool _esAdmin(User usuario) {
    final rol = usuario.rol.toString().toUpperCase();
    return rol == 'ADMIN' || rol == 'PROPIETARIO' || rol == 'SUPERADMIN';
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
    AutoBackupService.instance.detener();
    super.dispose();
  }

  int _claveAIndice(String clave) {
    const map = {
      'inicio': 0,
      'terceros': 1,
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
      'reportes_generales': 12,
      'reportes_diarios': 30,
      'reportes_mensuales': 31,
      'reportes_personalizado': 32,
      'dispositivos': 13,
      'seguridad': 14,
      'documentos_empresa': 15,
      'configuracion': 16,
      'diseno_ticket': 17,
      'clientes': 18,
      'proveedores': 19,
      'roles': 20,
      'ingresos': 21,
      'despachos': 22,
      'conceptos_inventario': 29,
      'conceptos_kardex': 29,
      'dispositivos_basculas': 23,
      'dispositivos_indicadores': 24,
      'dispositivos_semaforos': 25,
      'dispositivos_camaras': 26,
      'dispositivos_barreras': 27,
      'dispositivos_impresoras': 28,
    };
    return map[clave] ?? -1;
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    AutoBackupService.instance.registrarActividad();

    if (di.sl<ModalManager>().hasOpenModals ||
        DialogKeyboard.hayModalAbierto()) {
      return DialogKeyboard.manejarTeclaEnModal(event);
    }

    final key = event.logicalKey;
    final kb = HardwareKeyboard.instance;
    final ctrl = kb.isControlPressed || kb.isMetaPressed;
    final shift = kb.isShiftPressed;
    final alt = kb.isAltPressed;

    // ── Teclas de función (sin modificadores) ───────────────────────────────
    // ── Teclas de función (sin modificadores) ───────────────────────────────
    // F1-F7 solo actúan fuera del formulario de pesaje (ese tiene sus propias
    // teclas F1-F7). F8-F12 actúan siempre.
    if (event is KeyDownEvent && !ctrl && !alt) {
      final enFormularioPesaje = _rutaSuperior() == 'nuevo_pesaje';

      if (!enFormularioPesaje) {
        // F1 → Nuevo pesaje (igual que Ctrl+N).
        if (event.physicalKey == LogicalKeyboardKey.f1) {
          _abrirNuevoPesaje();
          return true;
        }
        // F2 → Nuevo registro estándar según la pantalla actual.
        if (event.physicalKey == LogicalKeyboardKey.f2) {
          _nuevoRegistroEstandar();
          return true;
        }
        // F4 → Guardar (delegado a la pantalla actual, si aplica).
        if (event.physicalKey == LogicalKeyboardKey.f4) {
          _guardarActual();
          return true;
        }
        // F5 → Imprimir/Exportar según la pantalla.
        if (event.physicalKey == LogicalKeyboardKey.f5) {
          _imprimirActual();
          return true;
        }
        // F6 → Buscar (enfoca buscador o abre paleta).
        if (event.physicalKey == LogicalKeyboardKey.f6) {
          _buscarActual();
          return true;
        }
        // F7 → Búsqueda rápida / paleta.
        if (event.physicalKey == LogicalKeyboardKey.f7) {
          _toggleCommandPalette();
          return true;
        }
      }

      // F8 → Nuevo conductor (global, incluso en el formulario de pesaje).
      if (event.physicalKey == LogicalKeyboardKey.f8) {
        _abrirNuevoConductor();
        return true;
      }
      // F9 → Maximizar/restaurar.
      if (event.physicalKey == LogicalKeyboardKey.f9) {
        _alternarMaximizado();
        return true;
      }
      // F10 → Toggle sidebar.
      if (event.physicalKey == LogicalKeyboardKey.f10) {
        _toggleSidebar();
        return true;
      }
      // F11 → Pantalla completa.
      if (event.physicalKey == LogicalKeyboardKey.f11) {
        _alternarPantallaCompleta();
        return true;
      }
      // F12 → Cancelar operación.
      if (event.physicalKey == LogicalKeyboardKey.f12) {
        _cancelarOperacion();
        return true;
      }
      // Esc → no interceptar (lo maneja el modal/diálogo si aplica).
      if (key == LogicalKeyboardKey.escape) {
        return false;
      }
      // Backspace/Delete → volver atrás si no hay input en foco.
      if ((key == LogicalKeyboardKey.backspace ||
              key == LogicalKeyboardKey.delete) &&
          !_hayTextoEnFoco()) {
        _volverAtras();
        return true;
      }
      // `~` (backquote) → paleta de comandos (alternativa a Ctrl+K).
      if (key == LogicalKeyboardKey.backquote) {
        _toggleCommandPalette();
        return true;
      }
    }

    if (event is KeyDownEvent && ctrl && key == LogicalKeyboardKey.enter) {
      if (alt) {
        _alternarMaximizado();
      } else {
        _alternarPantallaCompleta();
      }
      return true;
    }

    if (ctrl && !alt) {
      if (event is KeyDownEvent && !shift && key == LogicalKeyboardKey.keyQ) {
        _salirDelSistema();
        return true;
      }
      if (event is KeyDownEvent && !shift && key == LogicalKeyboardKey.keyN) {
        _abrirNuevoPesaje();
        return true;
      }
      if (event is KeyDownEvent && shift && key == LogicalKeyboardKey.keyN) {
        _abrirNuevoPesaje();
        return true;
      }
      if (event is KeyDownEvent && shift && key == LogicalKeyboardKey.keyV) {
        _abrirNuevoVehiculo();
        return true;
      }
      if (event is KeyDownEvent && shift && key == LogicalKeyboardKey.keyD) {
        _abrirNuevoConductor();
        return true;
      }
      if (event is KeyDownEvent && shift && key == LogicalKeyboardKey.keyT) {
        _irA('transportes');
        return true;
      }
      if (event is KeyDownEvent && shift && key == LogicalKeyboardKey.keyL) {
        _alternarTema();
        return true;
      }
      if (event is KeyDownEvent && !shift && key == LogicalKeyboardKey.keyB) {
        _toggleSidebar();
        return true;
      }
      if (event is KeyDownEvent && !shift && key == LogicalKeyboardKey.keyK) {
        _toggleCommandPalette();
        return true;
      }
      if (event is KeyDownEvent && !shift && key == LogicalKeyboardKey.keyH) {
        _irA('inicio');
        return true;
      }
      if (event is KeyDownEvent && !shift && key == LogicalKeyboardKey.keyL) {
        _cerrarSesion();
        return true;
      }
      if (event is KeyDownEvent && !shift && key == LogicalKeyboardKey.keyA) {
        _abrirAjustesInventario();
        return true;
      }
      if (event is KeyDownEvent && key == LogicalKeyboardKey.comma) {
        _abrirConfiguracion();
        return true;
      }
      if (event is KeyDownEvent && !shift && key == LogicalKeyboardKey.keyR) {
        context.read<WeighingBloc>().add(SyncWeighingsEvent());
        return true;
      }
      if (event is KeyDownEvent) {
        final idx = _numeroCtrl(key);
        if (idx != null) {
          _cambiarIndice(idx);
          return true;
        }
      }
      // 🆕 Ctrl+= → nuevo registro estándar (alias de F2)
      if (event is KeyDownEvent &&
          (key == LogicalKeyboardKey.equal ||
           key == LogicalKeyboardKey.numpadAdd)) {
        _nuevoRegistroEstandar();
        return true;
      }
    }

    if (alt && !ctrl && event is KeyDownEvent) {
      final destino = _destinoPorAlt(key);
      if (destino != null) {
        _irA(destino);
        return true;
      }
    }

    return false;
  }

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

  String? _destinoPorAlt(LogicalKeyboardKey key) {
    switch (key) {
      case LogicalKeyboardKey.keyC:
        return 'terceros';
      case LogicalKeyboardKey.keyF:
        return 'camiones';
      case LogicalKeyboardKey.keyP:
        return 'productos';
      case LogicalKeyboardKey.keyA:
        return 'almacenes';
      case LogicalKeyboardKey.keyK:
        return 'kardex';
      case LogicalKeyboardKey.keyU:
        return 'usuarios';
      case LogicalKeyboardKey.keyD:
        return 'dispositivos';
      case LogicalKeyboardKey.keyS:
        return 'seguridad';
      case LogicalKeyboardKey.keyR:
        return 'reportes';
      default:
        return null;
    }
  }

  void _toggleSidebar() =>
      setState(() => _sidebarVisible = !_sidebarVisible);

  void ejecutarAccion(String comando) {
    final partes = comando.split(':');
    if (partes.first != 'go' || partes.length < 2) return;

    final destino = HomeShell.aliasAcciones[partes[1]] ?? partes[1];

    switch (destino) {
      case 'inicio':
      case 'terceros':
      case 'clientes':
      case 'proveedores':
      case 'usuarios':
      case 'camiones':
      case 'conductores':
      case 'transportes':
      case 'categorias':
      case 'productos':
      case 'almacenes':
      case 'kardex':
      case 'entradas':
      case 'salidas':
      case 'reportes':
      case 'dispositivos':
      case 'seguridad':
      case 'documentos_empresa':
      case 'configuracion':
      case 'diseno_ticket':
        _irA(partes[1]);

      case 'pesaje_automatico':
        _irA('entradas');
      case 'pesaje_manual':
        _abrirNuevoPesaje();

      case 'ajustes':
        _abrirAjustesInventario();
      case 'auditoria':
        _abrirAuditoria();
      case 'sesiones':
        _abrirSesiones();
      case 'diagnostico':
        _abrirDiagnostico();
      case 'licencia':
        _abrirLicencia();
      case 'conexiones':
        _abrirConexiones();
      case 'ayuda':
        _abrirAyuda();

      case 'vehiculo':
        _irA('camiones');
      case 'conductor':
        _irA('conductores');

      default:
        break;
    }
  }

  void _buscarEn(String destino, String texto) {
    switch (destino) {
      case 't':
        _irA('entradas');
      case 'p':
        _irA('entradas');
      case 'c':
        _irA('conductores');
      default:
        break;
    }
    FocusSearchBus.instance.registrarTexto(texto);
  }

  void _mostrarMenuNavegacion() {
    mostrarNavMovil(
      context,
      selectedIndex: _index,
      onItemSelected: _cambiarIndice,
      onAction: ejecutarAccion,
      onLogout: _cerrarSesion,
      onOpenConfig: _abrirConfiguracion,
    );
  }

  List<MenuNode> _modulosVisibles() {
    final authState = context.read<AuthBloc>().state;
    final rol = authState is AuthAuthenticated ? authState.user.rol : 'OPERADOR';
    final arbol = AppSidebar.filtrarMenu(AppSidebar.menuTree, rol);
    final out = <MenuNode>[];
    void recorrer(List<MenuNode> nodos) {
      for (final n in nodos) {
        if (n.isLeaf) {
          if (n.index != null) out.add(n);
        } else if (n.children != null) {
          recorrer(n.children!);
        }
      }
    }

    recorrer(arbol);
    return out;
  }

  void _toggleCommandPalette() =>
      setState(() => _commandPaletteOpen = !_commandPaletteOpen);

  void _cambiarIndice(int nuevo) {
    if (di.sl<ModalManager>().hasOpenModals) return;

    final ruta = ModalRoute.of(context);
    if (ruta != null && !ruta.isCurrent) {
      Navigator.of(context).popUntil((r) => r == ruta);
    }

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

  String? _rutaSuperior() {
    String? nombre;
    Navigator.of(context).popUntil((ruta) {
      nombre = ruta.settings.name;
      return true;
    });
    return nombre;
  }

  void _pushSiNoEsta(String nombre, Widget Function() builder) {
    if (_rutaSuperior() == nombre) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: RouteSettings(name: nombre),
        builder: (_) => builder(),
      ),
    );
  }

  bool _hayTextoEnFoco() {
    final contexto = FocusManager.instance.primaryFocus?.context;
    if (contexto == null) return false;
    return contexto.findAncestorStateOfType<EditableTextState>() != null;
  }

  bool _enShellVisible() {
    final ruta = ModalRoute.of(context);
    if (ruta == null || !ruta.isCurrent) return false;
    if (di.sl<ModalManager>().hasOpenModals) return false;
    if (_rutaSuperior() != null) return false;  // 🆕 NO capturar si hay pantalla encima
    return true;
  }

  void _cancelarOperacion() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
      return;
    }
    if (_index != 0) _irA('inicio');
  }

  void _refrescarModuloActual() {
    final catalogosPorIndice = <int, CatalogResource>{
      1: AppCatalogos.tercerosResource,
      3: AppCatalogos.camionResource,
      4: AppCatalogos.conductorResource,
      5: AppCatalogos.transporteResource,
      6: AppCatalogos.categoriaResource,
      7: AppCatalogos.productoResource,
      8: AppCatalogos.almacenResource,
    };

    final recurso = catalogosPorIndice[_index];
    if (recurso != null) {
      di.sl<CatalogCrudCubit>().cargar(recurso);
      return;
    }
    if (_index == 0 || _index == 9 || _index == 10 || _index == 11) {
      context.read<WeighingBloc>().add(const ListWeighingsEvent());
      return;
    }
    setState(() {});
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

  Future<void> _salirDelSistema() async {
    final confirmar = await di.sl<ModalManager>().showModal<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('Salir del sistema')),
        content: Text(context.tr('¿Deseas cerrar Balansoft-WS?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('Cancelar')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('Salir')),
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

  // ── Nuevos métodos de atajos (F2, F4, F5, F6) ──────────────────────

  /// F2: crea un registro nuevo en el catálogo de la pantalla actual.
  /// Si la pantalla no es un catálogo, no hace nada.
  void _nuevoRegistroEstandar() {
    final recurso = switch (_index) {
      1 => AppCatalogos.tercerosResource,
      3 => AppCatalogos.camionResource,
      4 => AppCatalogos.conductorResource,
      5 => AppCatalogos.transporteResource,
      6 => AppCatalogos.categoriaResource,
      7 => AppCatalogos.productoResource,
      8 => AppCatalogos.almacenResource,
      18 => AppCatalogos.clienteResource,
      19 => AppCatalogos.proveedorResource,
      29 => AppCatalogos.conceptoKardexResource,
      _ => null,
    };
    if (recurso == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CatalogEditScreen(recurso: recurso),
      ),
    );
  }

  /// F4: guardar. Si la pantalla actual tiene un formulario abierto con
  /// `FormState`, delega. Si no, no hace nada (el formulario ya maneja F4).
  void _guardarActual() {
    // No-op en shell. Los formularios capturan F4 ellos mismos.
  }

  /// F5: imprimir/exportar según la pantalla.
  void _imprimirActual() {
    // Por ahora no-op. En una siguiente iteración conectar con:
    // - Entradas/Salidas: imprimir último boleto.
    // - Reportes: exportar.
    // - Kardex: exportar.
  }

  /// F6: buscar. Si la pantalla tiene un buscador enfocable, lo enfoca.
  /// Si no, abre la paleta de comandos.
  void _buscarActual() {
    if (FocusSearchBus.instance.enfocar()) return;
    _toggleCommandPalette();
  }

  // ── Acciones existentes ─────────────────────────────────────────────

  void _abrirNuevoPesaje() {
    _pushSiNoEsta('nuevo_pesaje', () => const WeighingFormScreen());
  }

  void _abrirNuevoVehiculo() {
    _pushSiNoEsta(
      'nuevo_vehiculo',
      () => CatalogEditScreen(recurso: AppCatalogos.camionResource),
    );
  }

  void _abrirNuevoConductor() {
    _pushSiNoEsta(
      'nuevo_conductor',
      () => CatalogEditScreen(recurso: AppCatalogos.conductorResource),
    );
  }

  void _abrirConfiguracion() => _irA('configuracion');

  void _abrirAuditoria() {
    _pushSiNoEsta('auditoria', () => const AuditoriaScreen());
  }

  void _abrirSesiones() {
    _pushSiNoEsta('sesiones', () => const SesionesScreen());
  }

  void _abrirAjustesInventario() {
    _pushSiNoEsta('ajustes_inventario', () => const AjustesInventarioScreen());
  }

  void _abrirMovimientos() {
    _pushSiNoEsta(
      'movimientos',
      () => const WeighingListScreen(titulo: 'Movimientos'),
    );
  }

  void _abrirAyuda() {
    _pushSiNoEsta('ayuda', () => const AyudaScreen());
  }

  void _abrirDiagnostico() {
    _pushSiNoEsta('diagnostico', () => const SystemDiagnosticsScreen());
  }

  void _abrirLicencia() {
    _pushSiNoEsta('licencia', () => const LicenseAdminScreen());
  }

  void _abrirConexiones() {
    _pushSiNoEsta('conexiones', () => const ConnectionsScreen());
  }

  Future<void> _cerrarSesion() async {
    final authBloc = context.read<AuthBloc>();
    final confirmar = await di.sl<ModalManager>().showModal<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('Cerrar sesión')),
        content: Text(context.tr('¿Deseas cerrar la sesión actual?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('Cancelar')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('Cerrar sesión')),
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
        _irA('clientes');
        return;
      case 'go:proveedores':
        _irA('proveedores');
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
        if (command.startsWith('go:')) {
          ejecutarAccion(command);
          return;
        }
        final partes = command.split(':');
        if (partes.length == 3 && partes[0] == 'buscar') {
          _buscarEn(partes[1], partes[2]);
        } else if (partes.length >= 2) {
          _buscarEn(partes[0], partes.skip(1).join(':'));
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final usarSidebar = MediaQuery.sizeOf(context).shortestSide >= 600;

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
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => AutoBackupService.instance.registrarActividad(),
        child: Scaffold(
          body: Stack(
            children: [
              if (!usarSidebar)
                _buildMobileBody(idx, contenido)
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
      ),
    );
  }

  Widget _buildMobileBody(int idx, Widget contenido) {
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
          modulos: _modulosVisibles(),
          alSeleccionar: _cambiarIndice,
          abrirMas: _abrirMenuMas,
        ),
      ],
    );
  }

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
                  onAction: ejecutarAccion,
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
    required this.modulos,
    required this.alSeleccionar,
    required this.abrirMas,
  });

  final int indiceActual;
  final List<MenuNode> modulos;
  final ValueChanged<int> alSeleccionar;
  final void Function(BuildContext) abrirMas;

  bool get _hayMas => modulos.length > 4;

  List<MenuNode> get _tabs => _hayMas ? modulos.take(4).toList() : modulos;

  int _navLocal() {
    for (var i = 0; i < _tabs.length; i++) {
      if (_tabs[i].index == indiceActual) return i;
    }
    return _hayMas ? 4 : 0;
  }

  void _alNavegar(BuildContext context, int local) {
    if (_hayMas && local == 4) {
      abrirMas(context);
      return;
    }
    alSeleccionar(_tabs[local].index ?? 0);
  }

  String _lang(BuildContext context) {
    try {
      return Localizations.localeOf(context).languageCode;
    } catch (_) {
      return 'es';
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = _lang(context);
    final destinations = <NavigationDestination>[
      for (final m in _tabs)
        NavigationDestination(
          icon: Icon(m.icon),
          selectedIcon: Icon(m.activeIcon ?? m.icon),
          label: AppSidebar.traducir(m.label, lang),
        ),
      if (_hayMas)
        const NavigationDestination(
          icon: Icon(Icons.more_horiz),
          label: 'Más',
        ),
    ];

    return NavigationBar(
      selectedIndex: _navLocal(),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: destinations,
      onDestinationSelected: (i) => _alNavegar(context, i),
    );
  }
}