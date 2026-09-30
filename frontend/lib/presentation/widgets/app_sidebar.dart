import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/i18n/translations.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/accesos_repository.dart';
import '../../injection.dart' as di;
import '../providers/bloc/auth/auth_bloc.dart';

/// Sidebar moderno con tamaños de fuente e iconos optimizados para alta legibilidad.
///
/// Cada hoja declara **explícitamente** su `index` en la lista `_pages` del
/// `home_shell.dart`. Así, reordenar visualmente el menú no rompe la navegación.
///
/// Mapa actual de `_pages` (home_shell.dart):
///   0  inicio
///   1  terceros
///   2  usuarios
///   3  camiones
///   4  conductores
///   5  transportes
///   6  categorias
///   7  productos
///   8  almacenes
///   9  kardex
///   10 entradas
///   11 salidas
///   12 reportes
///   13 dispositivos
///   14 seguridad
///   15 documentos_empresa
///   16 configuracion
///   17 diseno_ticket
///
/// Las hojas que **no** son páginas del shell (pesajes, ajustes de inventario,
/// auditoría, diagnóstico, licencia, conexiones, ayuda) se declaran como nodos
/// de acción (`accion`) y no ocupan índice: el shell ejecuta el comando.
class AppSidebar extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final void Function(String comando) onAction;
  final VoidCallback onCollapse;
  final VoidCallback onLogout;
  final VoidCallback onOpenConfig;

  const AppSidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.onAction,
    required this.onCollapse,
    required this.onLogout,
    required this.onOpenConfig,
  });

  /// Árbol de menú compartido con el bottom bar / menú móvil de Android.
  static const menuTree = _AppSidebarState.menuTree;

  static List<MenuNode> filtrarMenu(List<MenuNode> nodes, String rol) =>
      _AppSidebarState.filtrarMenu(nodes, rol);

  static String traducir(String label, String lang) =>
      _AppSidebarState.traducir(label, lang);

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  final Set<String> _collapsedGroups = {};
  final ScrollController _scrollController = ScrollController();

  /// Árbol de menú. Cada hoja tiene `index` que apunta a `_pages` en
  /// `home_shell.dart`. NO usar el orden visual para inferir el índice.
  /// `rolesPermitidos` = roles que pueden VER el módulo según la matriz por
  /// defecto (`AccesosDefault`); los grupos/encabezados no filtran solos.
  /// Árbol de menú compartido (desktop sidebar y menú móvil). Cada hoja
  /// apunta a `_pages` en `home_shell.dart`.
  static const menuTree = <MenuNode>[
    MenuNode(
      label: 'INFORMACIÓN',
      isSectionHeader: true,
      children: [
        MenuNode(
          label: 'Inicio',
          icon: Icons.dashboard_outlined,
          activeIcon: Icons.dashboard,
          clave: 'inicio',
          index: 0,
          shortcut: 'Ctrl+1',
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR', 'TRABAJADOR'},
        ),
        MenuNode(
          label: 'Pesaje Automático',
          icon: Icons.smart_toy_outlined,
          activeIcon: Icons.smart_toy,
          accion: 'go:pesaje_automatico',
          shortcut: 'F1',
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        MenuNode(
          label: 'Pesaje Manual',
          icon: Icons.edit_note,
          activeIcon: Icons.edit_note,
          accion: 'go:pesaje_manual',
          shortcut: 'F2',
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        MenuNode(
          label: 'Terceros',
          icon: Icons.people_outline,
          activeIcon: Icons.people,
          clave: 'terceros',
          index: 1,
          shortcut: 'Alt+C',
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        MenuNode(
          label: 'Flota y Transporte',
          icon: Icons.local_shipping_outlined,
          children: [
            MenuNode(
              label: 'Camiones / Vehículos',
              icon: Icons.directions_car_outlined,
              activeIcon: Icons.directions_car,
              clave: 'camiones',
              index: 3,
              shortcut: 'Alt+F',
              rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
            ),
            MenuNode(
              label: 'Conductores',
              icon: Icons.badge_outlined,
              activeIcon: Icons.badge,
              clave: 'conductores',
              index: 4,
              shortcut: 'F8',
              rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
            ),
            MenuNode(
              label: 'Empresas de Transporte',
              icon: Icons.fire_truck_outlined,
              activeIcon: Icons.fire_truck,
              clave: 'transportes',
              index: 5,
              shortcut: 'Ctrl+⇧+T',
              rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
            ),
          ],
        ),
        MenuNode(
          label: 'Inventario Base',
          icon: Icons.warehouse_outlined,
          children: [
            MenuNode(
              label: 'Categorías',
              icon: Icons.category_outlined,
              activeIcon: Icons.category,
              clave: 'categorias',
              index: 6,
              rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
            ),
            MenuNode(
              label: 'Productos',
              icon: Icons.inventory_2_outlined,
              activeIcon: Icons.inventory_2,
              clave: 'productos',
              index: 7,
              shortcut: 'Alt+P',
              rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
            ),
            MenuNode(
              label: 'Almacenes',
              icon: Icons.warehouse_outlined,
              activeIcon: Icons.warehouse,
              clave: 'almacenes',
              index: 8,
              shortcut: 'Alt+A',
              rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
            ),
            MenuNode(
              label: 'Ajustes de Inventario',
              icon: Icons.tune,
              activeIcon: Icons.tune,
              accion: 'go:ajustes',
              shortcut: 'Ctrl+A',
              rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
            ),
          ],
        ),
        MenuNode(
          label: 'Kardex',
          icon: Icons.table_rows_outlined,
          activeIcon: Icons.table_rows,
          clave: 'kardex',
          index: 9,
          shortcut: 'Alt+K',
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
      ],
    ),
    MenuNode(
      label: 'REPORTES',
      icon: Icons.bar_chart_outlined,
      children: [
        MenuNode(
          label: 'Ingresos (Entradas)',
          icon: Icons.arrow_downward_outlined,
          activeIcon: Icons.arrow_downward,
          clave: 'entradas',
          index: 10,
          shortcut: 'Ctrl+2',
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        MenuNode(
          label: 'Despachos (Salidas)',
          icon: Icons.arrow_upward_outlined,
          activeIcon: Icons.arrow_upward,
          clave: 'salidas',
          index: 11,
          shortcut: 'Ctrl+3',
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        MenuNode(
          label: 'Reportes Generales',
          icon: Icons.analytics_outlined,
          activeIcon: Icons.analytics,
          clave: 'reportes',
          index: 12,
          shortcut: 'Ctrl+4',
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        MenuNode(
          label: 'Auditoría del Sistema',
          icon: Icons.fact_check_outlined,
          activeIcon: Icons.fact_check,
          accion: 'go:auditoria',
          rolesPermitidos: {'ADMIN', 'AUDITOR'},
        ),
      ],
    ),
    MenuNode(
      label: 'MANTENIMIENTO',
      icon: Icons.settings_outlined,
      children: [
        MenuNode(
          label: 'Usuarios del Sistema',
          icon: Icons.admin_panel_settings_outlined,
          activeIcon: Icons.admin_panel_settings,
          clave: 'usuarios',
          index: 2,
          shortcut: 'Alt+U',
          rolesPermitidos: {'ADMIN', 'AUDITOR'},
        ),
        MenuNode(
          label: 'Seguridad y Accesos',
          icon: Icons.lock_outline,
          activeIcon: Icons.lock,
          clave: 'seguridad',
          index: 14,
          shortcut: 'Alt+S',
          rolesPermitidos: {'ADMIN'},
        ),
        MenuNode(
          label: 'Dispositivos de Campo',
          icon: Icons.sensors_outlined,
          activeIcon: Icons.sensors,
          clave: 'dispositivos',
          index: 13,
          shortcut: 'Alt+D',
          rolesPermitidos: {'ADMIN'},
        ),
        MenuNode(
          label: 'Empresa y Documentos',
          icon: Icons.business_outlined,
          activeIcon: Icons.business,
          clave: 'documentos_empresa',
          index: 15,
          rolesPermitidos: {'ADMIN', 'AUDITOR'},
        ),
        MenuNode(
          label: 'Diseño de Ticket',
          icon: Icons.receipt_long_outlined,
          activeIcon: Icons.receipt_long,
          clave: 'diseno_ticket',
          index: 17,
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        MenuNode(
          label: 'Configuración',
          icon: Icons.settings_outlined,
          activeIcon: Icons.settings,
          clave: 'configuracion',
          index: 16,
          shortcut: 'Ctrl+,',
          rolesPermitidos: {'ADMIN'},
        ),
      ],
    ),
    MenuNode(
      label: 'AYUDA Y SOPORTE',
      isSectionHeader: true,
      children: [
        MenuNode(
          label: 'Ayuda',
          icon: Icons.help_outline,
          activeIcon: Icons.help,
          accion: 'go:ayuda',
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR', 'TRABAJADOR'},
        ),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _inicializarGruposColapsados(menuTree); // <-- Agregar esta línea
    _cargarAccesos();
  }

  void _inicializarGruposColapsados(List<MenuNode> nodes) {
    for (final node in nodes) {
      if (!node.isLeaf && !node.isSectionHeader) {
        _collapsedGroups.add(node.label);
      }
      if (node.children != null) {
        _inicializarGruposColapsados(node.children!);
      }
    }
  }

  Future<void> _cargarAccesos() async {
    final repo = di.sl<AccesosRepository>();
    if (!repo.cargado) await repo.cargar();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SwsColors.primary,
      child: SafeArea(
        right: false,
        child: SizedBox(
          width: 380,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Scrollbar(
                  controller: _scrollController,
                  thickness: 4,
                  radius: const Radius.circular(8),
                  child: ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    children: _buildNodes(
                      filtrarMenu(menuTree, _rolActual()),
                      rol: _rolActual(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _rolDefault = 'OPERADOR';

  String _rolActual() {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) return authState.user.rol;
    return _rolDefault;
  }

  /// Poda el árbol eliminando hojas sin permiso y los grupos/secciones que se
  /// quedan sin hijos visibles. Reutilizable por el menú móvil.
  static List<MenuNode> filtrarMenu(List<MenuNode> nodes, String rol) {
    final repo = di.sl<AccesosRepository>();
    final result = <MenuNode>[];

    for (final node in nodes) {
      // Hoja: visible si su clave la permite el rol (repositorio con fallback
      // a la matriz por defecto). Las hojas-acción no tienen clave de matriz:
      // se filtran directamente por `rolesPermitidos`.
      if (node.isLeaf) {
        if (node.accion != null) {
          final roles = node.rolesPermitidos;
          if (roles == null || roles.contains(rol.toUpperCase())) {
            result.add(node);
          }
          continue;
        }
        final clave = node.clave;
        if (clave == null || repo.puedeVer(rol, clave)) result.add(node);
        continue;
      }

      // Nodo con hijos: filtra recursivamente y conserva solo si hay visibles.
      final hijos = node.isSectionHeader ? node.children : node.children;
      final filtrados = filtrarMenu(hijos ?? const [], rol);
      if (filtrados.isEmpty) continue;
      result.add(node.copyWith(children: filtrados));
    }
    return result;
  }

  static String traducir(String label, String lang) {
    const map = {
      'INFORMACIÓN': 'menu_informacion',
      'Inicio': 'menu_inicio',
      'Pesaje Automático': 'menu_pesaje_automatico',
      'Pesaje Manual': 'menu_pesaje_manual',
      'Terceros': 'menu_terceros',
      'Flota y Transporte': 'menu_flota_transporte',
      'Camiones / Vehículos': 'menu_camiones',
      'Conductores': 'menu_conductores',
      'Empresas de Transporte': 'menu_transportes',
      'Inventario Base': 'menu_inventario_base',
      'Categorías': 'menu_categorias',
      'Productos': 'menu_productos',
      'Almacenes': 'menu_almacenes',
      'Ajustes de Inventario': 'menu_ajustes_inventario',
      'Kardex': 'menu_kardex',
      'REPORTES': 'menu_reportes',
      'Ingresos (Entradas)': 'menu_entradas',
      'Despachos (Salidas)': 'menu_salidas',
      'Reportes Generales': 'menu_reportes_generales',
      'Auditoría del Sistema': 'menu_auditoria',
      'MANTENIMIENTO': 'menu_mantenimiento',
      'Usuarios del Sistema': 'menu_usuarios',
      'Dispositivos de Campo': 'menu_dispositivos',
      'Seguridad y Accesos': 'menu_seguridad',
      'Empresa y Documentos': 'menu_documentos_empresa',
      'Diseño de Ticket': 'menu_diseno_ticket',
      'Configuración': 'menu_configuracion',
      'Configuración General': 'menu_configuracion',
      'AYUDA Y SOPORTE': 'menu_ayuda_soporte',
      'Ayuda': 'menu_ayuda',
      'Cerrar Sesión': 'logout_btn',
    };
    final key = map[label];
    return key != null ? AppTranslations.tr(key, langCode: lang) : label;
  }

  String _traducir(BuildContext context, String label) {
    String lang = 'es';
    try {
      lang = Localizations.localeOf(context).languageCode;
    } catch (_) {}
    return AppSidebar.traducir(label, lang);
  }

  List<Widget> _buildNodes(
    List<MenuNode> nodes, {
    required String rol,
  }) {
    final widgets = <Widget>[];

    for (final node in nodes) {
      final labelTraducido = _traducir(context, node.label);
      if (node.isSectionHeader) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 22, bottom: 8, left: 8),
            child: Text(
              labelTraducido,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.45),
                letterSpacing: 1.2,
              ),
            ),
          ),
        );

        if (node.children != null) {
          widgets.addAll(_buildNodes(node.children!, rol: rol));
        }
      } else if (node.isLeaf) {
        // El índice viene EXPLÍCITO en el nodo. No se calcula por orden.
        // Las hojas-acción (`accion`) las ejecuta el shell.
        final idx = node.index;
        final isSelected = idx != null && widget.selectedIndex == idx;

        widgets.add(
          _SidebarLeafTile(
            icon: node.icon!,
            activeIcon: node.activeIcon ?? node.icon!,
            label: labelTraducido,
            shortcut: node.shortcut,
            isSelected: isSelected,
            isSubItem: node.isSubItem,
            onTap: () {
              final accion = node.accion;
              if (accion != null) {
                widget.onAction(accion);
              } else {
                widget.onItemSelected(idx ?? 0);
              }
            },
          ),
        );
      } else {
        final groupKey = node.label;
        final isCollapsed = _collapsedGroups.contains(groupKey);

        widgets.add(
          _SidebarGroupHeader(
            label: labelTraducido,
            icon: node.icon,
            isCollapsed: isCollapsed,
            onTap: () => setState(() {
              if (isCollapsed) {
                _collapsedGroups.remove(groupKey);
              } else {
                _collapsedGroups.add(groupKey);
              }
            }),
          ),
        );

        if (!isCollapsed && node.children != null) {
          widgets.add(
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(left: 12, top: 2, bottom: 4),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 1.5,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _buildNodes(
                      node.children!
                          .map((c) => c.copyWith(isSubItem: true))
                          .toList(),
                      rol: rol,
                    ),
                  ),
                ),
              ),
            ),
          );
        }
      }
    }
    return widgets;
  }
}

// ─── Modelo de Datos ──────────────────────────────────────────────────

class MenuNode {
  final String label;
  final IconData? icon;
  final IconData? activeIcon;
  final String? clave;
  final int? index;
  final List<MenuNode>? children;

  /// Comando de acción para hojas que **no** son páginas del shell (p. ej.
  /// `go:diagnostico`). Si está presente, el shell ejecuta el comando en vez
  /// de cambiar de índice.
  final String? accion;

  /// Etiqueta del atajo mostrado a la derecha (p. ej. `Ctrl + ,`).
  final String? shortcut;

  /// Roles con acceso al módulo (matriz por defecto). Si es `null`, el nodo
  /// (grupo/encabezado) no filtra por rol y depende de sus hijos.
  final Set<String>? rolesPermitidos;
  final bool isSectionHeader;
  final bool isSubItem;

  const MenuNode({
    required this.label,
    this.icon,
    this.activeIcon,
    this.clave,
    this.index,
    this.children,
    this.accion,
    this.shortcut,
    this.rolesPermitidos,
    this.isSectionHeader = false,
    this.isSubItem = false,
  });

  bool get isLeaf => children == null && !isSectionHeader;

  /// Hoja que abre una pantalla del shell (tiene índice) vs. hoja-acción.
  bool get isPage => isLeaf && accion == null;

  MenuNode copyWith({bool? isSubItem, List<MenuNode>? children}) {
    return MenuNode(
      label: label,
      icon: icon,
      activeIcon: activeIcon,
      clave: clave,
      index: index,
      children: children ?? this.children,
      accion: accion,
      shortcut: shortcut,
      rolesPermitidos: rolesPermitidos,
      isSectionHeader: isSectionHeader,
      isSubItem: isSubItem ?? this.isSubItem,
    );
  }
}

// ─── Item Selección (Leaf) ────────────────────────────────────────────

class _SidebarLeafTile extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String? shortcut;
  final bool isSelected;
  final bool isSubItem;
  final VoidCallback onTap;

  const _SidebarLeafTile({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.isSubItem,
    required this.onTap,
    this.shortcut,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: isSubItem ? 8.0 : 0.0,
        top: 2,
        bottom: 2,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  isSelected ? activeIcon : icon,
                  size: isSubItem ? 19 : 21,
                  color: isSelected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.65),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: isSubItem ? 13.5 : 14.5,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ),
                if (shortcut != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        shortcut!,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                          color: Colors.white.withValues(
                            alpha: isSelected ? 0.85 : 0.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Grupo Desplegable (Desplegable Nivel 2) ─────────────────────────

class _SidebarGroupHeader extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isCollapsed;
  final VoidCallback onTap;

  const _SidebarGroupHeader({
    required this.label,
    this.icon,
    required this.isCollapsed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 21,
                    color: Colors.white.withValues(alpha: 0.65),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: isCollapsed ? 0 : 0.25,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
