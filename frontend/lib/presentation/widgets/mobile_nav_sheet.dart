import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_theme.dart';
import '../../data/repositories/accesos_repository.dart';
import '../../injection.dart' as di;
import '../providers/bloc/auth/auth_bloc.dart';
import 'app_sidebar.dart';

/// Menú de navegación móvil (Android). Reemplaza al sidebar del desktop: un
/// bottom sheet de lista agrupada que muestra **todos** los módulos accesibles
/// según el rol del usuario (misma matriz de `AppSidebar.menuTree`).
Future<void> mostrarNavMovil(
  BuildContext context, {
  required int selectedIndex,
  required ValueChanged<int> onItemSelected,
  required VoidCallback onLogout,
  required VoidCallback onOpenConfig,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MobileNavSheet(
      selectedIndex: selectedIndex,
      onItemSelected: onItemSelected,
      onLogout: onLogout,
      onOpenConfig: onOpenConfig,
    ),
  );
}

class _MobileNavSheet extends StatefulWidget {
  const _MobileNavSheet({
    required this.selectedIndex,
    required this.onItemSelected,
    required this.onLogout,
    required this.onOpenConfig,
  });

  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final VoidCallback onLogout;
  final VoidCallback onOpenConfig;

  @override
  State<_MobileNavSheet> createState() => _MobileNavSheetState();
}

class _MobileNavSheetState extends State<_MobileNavSheet> {
  static const _rolDefault = 'OPERADOR';

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

  String _rolActual(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) return authState.user.rol;
    return _rolDefault;
  }

  String _lang(BuildContext context) {
    try {
      return Localizations.localeOf(context).languageCode;
    } catch (_) {
      return 'es';
    }
  }

  void _seleccionar(int idx) {
    Navigator.of(context).pop();
    widget.onItemSelected(idx);
  }

  @override
  Widget build(BuildContext context) {
    final rol = _rolActual(context);
    final lang = _lang(context);
    final arbol = AppSidebar.filtrarMenu(AppSidebar.menuTree, rol);

    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: _buildNodos(context, arbol, lang: lang, rol: rol),
                ),
              ),
              const Divider(height: 1),
              _bottomActions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          const Icon(Icons.menu_open, size: 22, color: SwsColors.accent),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Menú',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _bottomActions(BuildContext context) {
    final lang = _lang(context);
    final habilitarConfiguracion =
        di.sl<AccesosRepository>().puedeVer(_rolActual(context), 'configuracion');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          if (habilitarConfiguracion) ...[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onOpenConfig();
                },
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: Text(AppSidebar.traducir('Configuración General', lang)),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onLogout();
              },
              icon: const Icon(Icons.logout, size: 18),
              label: Text(AppSidebar.traducir('Cerrar Sesión', lang)),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildNodos(
    BuildContext context,
    List<MenuNode> nodes, {
    required String lang,
    required String rol,
    int nivel = 0,
  }) {
    final widgets = <Widget>[];
    for (final node in nodes) {
      final label = AppSidebar.traducir(node.label, lang);
      if (node.isSectionHeader) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: SwsColors.accent,
              ),
            ),
          ),
        );
        if (node.children != null) {
          widgets.addAll(
            _buildNodos(context, node.children!, lang: lang, rol: rol),
          );
        }
      } else if (node.isLeaf) {
        final idx = node.index ?? 0;
        final isSelected = widget.selectedIndex == idx;
        widgets.add(
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            selected: isSelected,
            selectedTileColor: SwsColors.accent.withValues(alpha: 0.12),
            leading: Icon(
              isSelected
                  ? (node.activeIcon ?? node.icon)
                  : node.icon,
              color: isSelected ? SwsColors.accent : null,
            ),
            title: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            trailing: isSelected
                ? const Icon(Icons.check, size: 18, color: SwsColors.accent)
                : null,
            onTap: () => _seleccionar(idx),
          ),
        );
      } else {
        // Grupo sin encabezado de sección: subtítulo + hijos sangrados.
        widgets.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: SwsColors.gray500,
              ),
            ),
          ),
        );
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _buildNodos(
                context,
                node.children ?? const [],
                lang: lang,
                rol: rol,
                nivel: nivel + 1,
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }
}