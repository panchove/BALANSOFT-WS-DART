import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/config/menu_config.dart';
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
  /// Usa el árbol dinámico cargado desde `menu.json` (MenuConfig.arbol).
  static List<MenuNode> get menuTree => MenuConfig.arbol;

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

  @override
  void initState() {
    super.initState();
    _inicializarGruposColapsados(MenuConfig.arbol);
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
                      filtrarMenu(MenuConfig.arbol, _rolActual()),
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
      // Mantener separadores aunque estén entre grupos/secciones
      if (node.esSeparador) {
        result.add(node);
        continue;
      }

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
      final hijos = node.children;
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
      'Sesiones y Equipos': 'menu_sesiones',
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
      if (node.esSeparador) {
        widgets.add(
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            height: 1,
            width: double.infinity,
            color: Colors.white.withValues(alpha: 0.25),
          ),
        );
        continue;
      }
      final labelTraducido = _traducir(context, node.label);
      if (node.isSectionHeader) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 6, left: 8),
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
            key: Key('menu_${node.clave ?? labelTraducido}'),
            icon: node.icon ?? Icons.circle_outlined,
            activeIcon: node.activeIcon ?? node.icon ?? Icons.circle_outlined,
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
            key: Key('menu_grupo_${node.label}'),
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
    super.key,
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
    super.key,
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
