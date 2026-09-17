import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_theme.dart';
import '../providers/bloc/auth/auth_bloc.dart';

/// Sidebar moderno con tamaños de fuente e iconos optimizados para alta legibilidad.
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

  static const _menuTree = [
    _MenuNode(
      label: 'Inicio',
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard,
      clave: 'inicio',
    ),
    _MenuNode(
      label: 'INFORMACIÓN',
      isSectionHeader: true,
      children: [
        _MenuNode(
          label: 'Entidades',
          icon: Icons.people_outline,
          children: [
            _MenuNode(
              label: 'Terceros (C/P/A)',
              icon: Icons.people_outline,
              activeIcon: Icons.people,
              clave: 'terceros',
            ),
            _MenuNode(
              label: 'Usuarios del Sistema',
              icon: Icons.admin_panel_settings_outlined,
              activeIcon: Icons.admin_panel_settings,
              clave: 'usuarios',
              adminOnly: true,
            ),
          ],
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
            ),
            _MenuNode(
              label: 'Conductores',
              icon: Icons.badge_outlined,
              activeIcon: Icons.badge,
              clave: 'conductores',
            ),
            _MenuNode(
              label: 'Empresas de Transporte',
              icon: Icons.fire_truck_outlined,
              activeIcon: Icons.fire_truck,
              clave: 'transportes',
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
            ),
            _MenuNode(
              label: 'Productos',
              icon: Icons.inventory_2_outlined,
              activeIcon: Icons.inventory_2,
              clave: 'productos',
            ),
            _MenuNode(
              label: 'Almacenes',
              icon: Icons.warehouse_outlined,
              activeIcon: Icons.warehouse,
              clave: 'almacenes',
            ),
          ],
        ),
        _MenuNode(
          label: 'Kardex',
          icon: Icons.table_rows_outlined,
          activeIcon: Icons.table_rows,
          clave: 'kardex',
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
        ),
        _MenuNode(
          label: 'Despachos (Salidas)',
          icon: Icons.arrow_upward_outlined,
          activeIcon: Icons.arrow_upward,
          clave: 'salidas',
        ),
        _MenuNode(
          label: 'Inventario (Stock Físico)',
          icon: Icons.inventory_outlined,
          activeIcon: Icons.inventory,
          clave: 'reportes',
        ),
      ],
    ),
    _MenuNode(
      label: 'MANTENIMIENTO Y CONFIGURACIÓN',
      isSectionHeader: true,
      children: [
        _MenuNode(
          label: 'Dispositivos de Campo',
          icon: Icons.sensors_outlined,
          activeIcon: Icons.sensors,
          clave: 'dispositivos',
          adminOnly: true,
        ),
        _MenuNode(
          label: 'Seguridad y Accesos',
          icon: Icons.lock_outline,
          activeIcon: Icons.lock,
          clave: 'seguridad',
          adminOnly: true,
        ),
        _MenuNode(
          label: 'Empresa y Documentos',
          icon: Icons.business_outlined,
          activeIcon: Icons.business,
          clave: 'documentos_empresa',
          adminOnly: true,
        ),
        _MenuNode(
          label: 'Configuración General',
          icon: Icons.settings_outlined,
          activeIcon: Icons.settings,
          clave: 'configuracion',
        ),
      ],
    ),
  ];

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
                      _menuTree,
                      esOperador: _esOperador(),
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

  bool _esOperador() {
    final authState = context.read<AuthBloc>().state;
    return authState is AuthAuthenticated && authState.user.isOperador;
  }

  List<Widget> _buildNodes(
    List<_MenuNode> nodes, {
    required bool esOperador,
  }) {
    final widgets = <Widget>[];

    for (final node in nodes) {
      if (node.adminOnly && esOperador) continue;

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
          widgets.addAll(_buildNodes(node.children!, esOperador: esOperador));
        }
      } else if (node.isLeaf) {
        final idx = _indexForClave(node.clave!);
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
                      esOperador: esOperador,
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

  int _indexForClave(String clave) {
    final leaves = _allLeaves(_menuTree);
    final i = leaves.indexWhere((n) => n.clave == clave);
    return i == -1 ? 0 : i;
  }

  static List<_MenuNode> _allLeaves(List<_MenuNode> nodes) {
    final result = <_MenuNode>[];
    for (final n in nodes) {
      if (n.isLeaf) {
        result.add(n);
      } else if (n.children != null) {
        result.addAll(_allLeaves(n.children!));
      }
    }
    return result;
  }
}

// ─── Modelo de Datos ──────────────────────────────────────────────────

class _MenuNode {
  final String label;
  final IconData? icon;
  final IconData? activeIcon;
  final String? clave;
  final List<_MenuNode>? children;
  final bool adminOnly;
  final bool isSectionHeader;
  final bool isSubItem;

  const _MenuNode({
    required this.label,
    this.icon,
    this.activeIcon,
    this.clave,
    this.children,
    this.adminOnly = false,
    this.isSectionHeader = false,
    this.isSubItem = false,
  });

  bool get isLeaf => children == null && !isSectionHeader;

  _MenuNode copyWith({bool? isSubItem}) {
    return _MenuNode(
      label: label,
      icon: icon,
      activeIcon: activeIcon,
      clave: clave,
      children: children,
      adminOnly: adminOnly,
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