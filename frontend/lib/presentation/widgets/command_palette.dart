import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';

/// Paleta de comandos global (Ctrl+K).
/// Permite navegar y ejecutar acciones escribiendo términos, prefijos cortos
/// o atajos (según docs/NAV.md).
class CommandPalette extends StatefulWidget {
  final VoidCallback onClose;
  final void Function(String command) onExecute;

  const CommandPalette({
    super.key,
    required this.onClose,
    required this.onExecute,
  });

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String _query = '';
  int _selectedIndex = 0;

  late final List<_Command> _commands = [
    // Navegación por nombre
    const _Command(
      label: 'Dashboard / Inicio',
      icon: Icons.dashboard_outlined,
      shortcut: 'Ctrl+H',
      action: 'go:inicio',
    ),
    const _Command(
      label: 'Pesaje Manual',
      icon: Icons.edit_note,
      shortcut: 'Ctrl+Shift+N',
      action: 'go:pesaje_manual',
    ),
    const _Command(
      label: 'Pesaje Automático',
      icon: Icons.smart_toy_outlined,
      shortcut: 'Ctrl+N',
      action: 'go:pesaje_automatico',
    ),
    const _Command(
      label: 'Entradas',
      icon: Icons.arrow_downward_outlined,
      shortcut: 'Ctrl+2',
      action: 'go:entradas',
    ),
    const _Command(
      label: 'Salidas',
      icon: Icons.arrow_upward_outlined,
      shortcut: 'Ctrl+3',
      action: 'go:salidas',
    ),
    const _Command(
      label: 'Ajustes de Inventario',
      icon: Icons.tune,
      shortcut: 'Ctrl+A',
      action: 'go:ajustes',
    ),
    const _Command(
      label: 'Terceros (Clientes / Proveedores / Ambos)',
      icon: Icons.people_outline,
      shortcut: 'Alt+C',
      action: 'go:terceros',
    ),
    const _Command(
      label: 'Flota y Transporte',
      icon: Icons.local_shipping_outlined,
      shortcut: 'Alt+F',
      action: 'go:flota',
    ),
    const _Command(
      label: 'Inventario Base',
      icon: Icons.inventory_2_outlined,
      shortcut: 'Alt+P',
      action: 'go:inventario_base',
    ),
    const _Command(
      label: 'Kardex',
      icon: Icons.table_rows_outlined,
      shortcut: 'Alt+K',
      action: 'go:kardex',
    ),
    const _Command(
      label: 'Reportes',
      icon: Icons.analytics_outlined,
      shortcut: 'Alt+R',
      action: 'go:reportes',
    ),
    const _Command(
      label: 'Auditoría',
      icon: Icons.fact_check_outlined,
      action: 'go:auditoria',
    ),
    const _Command(
      label: 'Dispositivos de Campo',
      icon: Icons.sensors_outlined,
      shortcut: 'Alt+D',
      action: 'go:dispositivos',
    ),
    const _Command(
      label: 'Seguridad y Accesos',
      icon: Icons.lock_outline,
      shortcut: 'Alt+S',
      action: 'go:seguridad',
    ),
    const _Command(
      label: 'Empresa y Documentos',
      icon: Icons.business_outlined,
      action: 'go:empresa',
    ),
    const _Command(
      label: 'Configuración General',
      icon: Icons.settings_outlined,
      shortcut: 'Ctrl+,',
      action: 'go:configuracion',
    ),
    const _Command(
      label: 'Usuarios del Sistema',
      icon: Icons.admin_panel_settings_outlined,
      shortcut: 'Alt+U',
      action: 'go:usuarios',
    ),
    // Acciones rápidas
    const _Command(
      label: 'Nuevo Ticket de Pesaje',
      icon: Icons.add_circle_outline,
      shortcut: 'Ctrl+N',
      action: 'new:ticket',
    ),
    const _Command(
      label: 'Nuevo Vehículo / Chuto',
      icon: Icons.directions_car_outlined,
      shortcut: 'Ctrl+Shift+V',
      action: 'new:truck',
    ),
    const _Command(
      label: 'Nuevo Conductor',
      icon: Icons.person_add_outlined,
      shortcut: 'Ctrl+Shift+D',
      action: 'new:driver',
    ),
    // Configuración
    const _Command(
      label: 'Cambiar Tema (Claro/Oscuro)',
      icon: Icons.dark_mode_outlined,
      shortcut: 'Ctrl+Shift+L',
      action: 'cfg:theme',
    ),
    const _Command(
      label: 'Pantalla Completa',
      icon: Icons.fullscreen,
      shortcut: 'F11',
      action: 'cfg:fullscreen',
    ),
    const _Command(
      label: 'Maximizar / Restaurar ventana',
      icon: Icons.crop_square_outlined,
      shortcut: 'F9',
      action: 'cfg:maximize',
    ),
    const _Command(
      label: 'Salir del sistema',
      icon: Icons.power_settings_new_outlined,
      shortcut: 'Ctrl+Q',
      action: 'cfg:exit',
    ),
  ];

  List<_Command> get _filtered {
    if (_query.isEmpty) return _commands;
    final q = _query.toLowerCase();
    return _commands
        .where(
          (c) =>
              c.label.toLowerCase().contains(q) ||
              c.action.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final filtered = _filtered;

    if (key == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1).clamp(0, filtered.length - 1);
      });
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex = (_selectedIndex - 1).clamp(0, filtered.length - 1);
      });
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.enter) {
      if (filtered.isNotEmpty) {
        widget.onExecute(filtered[_selectedIndex].action);
        widget.onClose();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKeyEvent,
      child: GestureDetector(
        onTap: widget.onClose,
        child: Container(
          color: Colors.black54,
          child: Center(
            child: GestureDetector(
              onTap: () {},
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                elevation: 8,
                child: Container(
                  width: 480,
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.6,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).dividerColor,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: TextField(
                          controller: _controller,
                          decoration: InputDecoration(
                            hintText:
                                'Buscar módulo, comando o acción...',
                            hintStyle: const TextStyle(fontSize: 13),
                            prefixIcon:
                                const Icon(Icons.search, size: 20),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: widget.onClose,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding:
                                const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _query = value;
                              _selectedIndex = 0;
                            });
                          },
                        ),
                      ),
                      const Divider(height: 1),
                      if (filtered.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Sin resultados',
                            style: TextStyle(
                              color: SwsColors.gray500,
                            ),
                          ),
                        )
                      else
                        Flexible(
                          child: ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.only(bottom: 8),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final cmd = filtered[index];
                              final isSelected = index == _selectedIndex;
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  cmd.icon,
                                  size: 20,
                                  color: isSelected
                                      ? SwsColors.accent
                                      : SwsColors.gray500,
                                ),
                                title: Text(
                                  cmd.label,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                                trailing: cmd.shortcut != null
                                    ? Text(
                                        cmd.shortcut!,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: SwsColors.gray400,
                                          fontFamily: 'monospace',
                                        ),
                                      )
                                    : null,
                                selected: isSelected,
                                selectedTileColor:
                                    SwsColors.accent.withValues(alpha: 0.08),
                                onTap: () {
                                  widget.onExecute(cmd.action);
                                  widget.onClose();
                                },
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Command {
  final String label;
  final IconData icon;
  final String? shortcut;
  final String action;

  const _Command({
    required this.label,
    required this.icon,
    this.shortcut,
    required this.action,
  });
}
