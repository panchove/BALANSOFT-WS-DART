import 'package:flutter/material.dart';

/// Accesos rápidos flotantes compactos (solo icono y badge de atajo).
class QuickActionsBar extends StatelessWidget {
  final VoidCallback onPesajeManual;
  final VoidCallback onPesajeAuto;
  final VoidCallback onAjustesInventario;
  final VoidCallback onMovimientos;
  final VoidCallback onAuditoria;
  final VoidCallback onAyuda;

  const QuickActionsBar({
    super.key,
    required this.onPesajeManual,
    required this.onPesajeAuto,
    required this.onAjustesInventario,
    required this.onMovimientos,
    required this.onAuditoria,
    required this.onAyuda,
  });

  void _handleTap(BuildContext context, String label, VoidCallback action) {
    action();
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(label),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        width: 200,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _QuickActionCard(
              icon: Icons.edit_note,
              label: 'Pesaje Manual',
              shortcut: 'Alt+1',
              onTap: () => _handleTap(context, 'Pesaje Manual', onPesajeManual),
            ),
            _QuickActionCard(
              icon: Icons.smart_toy_outlined,
              label: 'Pesaje Auto',
              shortcut: 'Alt+2',
              onTap: () => _handleTap(context, 'Pesaje Auto', onPesajeAuto),
            ),
            _QuickActionCard(
              icon: Icons.tune,
              label: 'Ajustes Inv.',
              shortcut: 'Alt+5',
              onTap: () => _handleTap(context, 'Ajustes Inv.', onAjustesInventario),
            ),
            _QuickActionCard(
              icon: Icons.swap_horiz,
              label: 'Movimientos',
              onTap: () => _handleTap(context, 'Movimientos', onMovimientos),
            ),
            _QuickActionCard(
              icon: Icons.fact_check_outlined,
              label: 'Auditoría',
              shortcut: 'Alt+A',
              onTap: () => _handleTap(context, 'Auditoría', onAuditoria),
            ),
            _QuickActionCard(
              icon: Icons.help_outline,
              label: 'Ayuda',
              onTap: () => _handleTap(context, 'Ayuda', onAyuda),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? shortcut;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    this.shortcut,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: Tooltip(
        message: shortcut != null ? '$label ($shortcut)' : label,
        waitDuration: const Duration(milliseconds: 300),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            splashColor: theme.colorScheme.primary.withValues(alpha: 0.12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    color: Colors.white.withValues(alpha: 0.9),
                    size: 20,
                  ),
                  if (shortcut != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        shortcut!,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}