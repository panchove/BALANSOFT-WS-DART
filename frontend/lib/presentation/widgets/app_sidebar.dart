import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
class AppSidebar extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final VoidCallback onCollapse;
  final VoidCallback onLogout;
  final VoidCallback onOpenConfig;

  const AppSidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.onCollapse,
    required this.onLogout,
    required this.onOpenConfig,
  });

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
  static const _menuTree = [
    _MenuNode(
      label: 'INFORMACIÓN',
      isSectionHeader: true,
      children: [
        _MenuNode(
          label: 'Inicio',
          icon: Icons.dashboard_outlined,
          activeIcon: Icons.dashboard,
          clave: 'inicio',
          index: 0,
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR', 'TRABAJADOR'},
        ),
        _MenuNode(
          label: 'Terceros',
          icon: Icons.people_outline,
          activeIcon: Icons.people,
          clave: 'terceros',
          index: 1,
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        _MenuNode(
          label: 'Flota y Transporte',
          icon: Icons.local_shipping_outlined,
          children: [
            _MenuNode(
              label: 'Camiones / Vehículos',
              icon: Icons.directions_car_outlined,
              activeIcon: Icons.directions_car,
              clave: 'camiones',
              index: 3,
              rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
            ),
            _MenuNode(
              label: 'Conductores',
              icon: Icons.badge_outlined,
              activeIcon: Icons.badge,
              clave: 'conductores',
              index: 4,
              rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
            ),
            _MenuNode(
              label: 'Empresas de Transporte',
              icon: Icons.fire_truck_outlined,
              activeIcon: Icons.fire_truck,
              clave: 'transportes',
              index: 5,
              rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
            ),
          ],
        ),
        _MenuNode(
          label: 'Inventario Base',
          icon: Icons.warehouse_outlined,
          children: [
            _MenuNode(
              label: 'Categorías',
              icon: Icons.category_outlined,
              activeIcon: Icons.category,
              clave: 'categorias',
              index: 6,
              rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
            ),
            _MenuNode(
              label: 'Productos',
              icon: Icons.inventory_2_outlined,
              activeIcon: Icons.inventory_2,
              clave: 'productos',
              index: 7,
              rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
            ),
            _MenuNode(
              label: 'Almacenes',
              icon: Icons.warehouse_outlined,
              activeIcon: Icons.warehouse,
              clave: 'almacenes',
              index: 8,
              rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
            ),
          ],
        ),
        _MenuNode(
          label: 'Kardex',
          icon: Icons.table_rows_outlined,
          activeIcon: Icons.table_rows,
          clave: 'kardex',
          index: 9,
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
      ],
    ),
    _MenuNode(
      label: 'REPORTES',
      isSectionHeader: true,
      children: [
        _MenuNode(
          label: 'Ingresos (Entradas)',
          icon: Icons.arrow_downward_outlined,
          activeIcon: Icons.arrow_downward,
          clave: 'entradas',
          index: 10,
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        _MenuNode(
          label: 'Despachos (Salidas)',
          icon: Icons.arrow_upward_outlined,
          activeIcon: Icons.arrow_upward,
          clave: 'salidas',
          index: 11,
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
        _MenuNode(
          label: 'Inventario (Stock Físico)',
          icon: Icons.inventory_outlined,
          activeIcon: Icons.inventory,
          clave: 'reportes',
          index: 12,
          rolesPermitidos: {'ADMIN', 'OPERADOR', 'AUDITOR'},
        ),
      ],
    ),
    _MenuNode(
      label: 'MANTENIMIENTO Y CONFIGURACIÓN',
      isSectionHeader: true,
      children: [
        _MenuNode(
          label: 'Usuarios del Sistema',
          icon: Icons.admin_panel_settings_outlined,
          activeIcon: Icons.admin_panel_settings,
          clave: 'usuarios',
          index: 2,
          rolesPermitidos: {'ADMIN', 'AUDITOR'},
        ),
        _MenuNode(
          label: 'Dispositivos de Campo',
          icon: Icons.sensors_outlined,
          activeIcon: Icons.sensors,
          clave: 'dispositivos',
          index: 13,
          rolesPermitidos: {'ADMIN'},
        ),
        _MenuNode(
          label: 'Seguridad y Accesos',
          icon: Icons.lock_outline,
          activeIcon: Icons.lock,
          clave: 'seguridad',
          index: 14,
          rolesPermitidos: {'ADMIN'},
        ),
        _MenuNode(
          label: 'Empresa y Documentos',
          icon: Icons.business_outlined,
          activeIcon: Icons.business,
          clave: 'documentos_empresa',
          index: 15,
          rolesPermitidos: {'ADMIN', 'AUDITOR'},
        ),
        _MenuNode(
          label: 'Configuración General',
          icon: Icons.settings_outlined,
          activeIcon: Icons.settings,
          clave: 'configuracion',
          index: 16,
          rolesPermitidos: {'ADMIN'},
        ),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _cargarAccesos();
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
          width: 280,
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
                      _filtrarArbol(_menuTree),
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
  /// quedan sin hijos visibles.
  List<_MenuNode> _filtrarArbol(List<_MenuNode> nodes) {
    final rol = _rolActual();
    final repo = di.sl<AccesosRepository>();
    final result = <_MenuNode>[];

    for (final node in nodes) {
      // Hoja: visible si su clave la permite el rol (repositorio con fallback
      // a la matriz por defecto).
      if (node.isLeaf) {
        final clave = node.clave;
        if (clave == null || repo.puedeVer(rol, clave)) result.add(node);
        continue;
      }

      // Nodo con hijos: filtra recursivamente y conserva solo si hay visibles.
      final hijos = node.isSectionHeader ? node.children : node.children;
      final filtrados = _filtrarArbol(hijos ?? const []);
      if (filtrados.isEmpty) continue;
      result.add(node.copyWith(children: filtrados));
    }
    return result;
  }

  List<Widget> _buildNodes(
    List<_MenuNode> nodes, {
    required String rol,
  }) {
    final widgets = <Widget>[];

    for (final node in nodes) {
      if (node.isSectionHeader) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 22, bottom: 8, left: 8),
            child: Text(
              node.label,
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
        final idx = node.index ?? 0;
        final isSelected = widget.selectedIndex == idx;

        widgets.add(
          _SidebarLeafTile(
            icon: node.icon!,
            activeIcon: node.activeIcon ?? node.icon!,
            label: node.label,
            isSelected: isSelected,
            isSubItem: node.isSubItem,
            onTap: () => widget.onItemSelected(idx),
          ),
        );
      } else {
        final groupKey = node.label;
        final isCollapsed = _collapsedGroups.contains(groupKey);

        widgets.add(
          _SidebarGroupHeader(
            label: node.label,
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

class _MenuNode {
  final String label;
  final IconData? icon;
  final IconData? activeIcon;
  final String? clave;
  final int? index;
  final List<_MenuNode>? children;

  /// Roles con acceso al módulo (matriz por defecto). Si es `null`, el nodo
  /// (grupo/encabezado) no filtra por rol y depende de sus hijos.
  final Set<String>? rolesPermitidos;
  final bool isSectionHeader;
  final bool isSubItem;

  const _MenuNode({
    required this.label,
    this.icon,
    this.activeIcon,
    this.clave,
    this.index,
    this.children,
    this.rolesPermitidos,
    this.isSectionHeader = false,
    this.isSubItem = false,
  });

  bool get isLeaf => children == null && !isSectionHeader;

  _MenuNode copyWith({bool? isSubItem, List<_MenuNode>? children}) {
    return _MenuNode(
      label: label,
      icon: icon,
      activeIcon: activeIcon,
      clave: clave,
      index: index,
      children: children ?? this.children,
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