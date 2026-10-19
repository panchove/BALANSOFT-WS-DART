import 'package:flutter/material.dart';
import '../../core/i18n/translations.dart';

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
    final lang = Localizations.localeOf(context).languageCode;
    final lPesajeManual = AppTranslations.tr('qa_pesaje_manual', langCode: lang);
    final lPesajeAuto = AppTranslations.tr('qa_pesaje_auto', langCode: lang);
    final lAjustesInv = AppTranslations.tr('qa_ajustes_inv', langCode: lang);
    final lMovimientos = AppTranslations.tr('qa_movimientos', langCode: lang);
    final lAuditoria = AppTranslations.tr('qa_auditoria', langCode: lang);
    final lAyuda = AppTranslations.tr('qa_ayuda', langCode: lang);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _QuickActionCard(
              icon: Icons.edit_note,
              label: lPesajeManual,
              shortcut: 'Ctrl+Shift+N',
              onTap: () => _handleTap(context, lPesajeManual, onPesajeManual),
            ),
            _QuickActionCard(
              icon: Icons.smart_toy_outlined,
              label: lPesajeAuto,
              shortcut: 'Ctrl+N',
              onTap: () => _handleTap(context, lPesajeAuto, onPesajeAuto),
            ),
            _QuickActionCard(
              icon: Icons.tune,
              label: lAjustesInv,
              shortcut: 'Ctrl+A',
              onTap: () => _handleTap(context, lAjustesInv, onAjustesInventario),
            ),
            _QuickActionCard(
              icon: Icons.swap_horiz,
              label: lMovimientos,
              onTap: () => _handleTap(context, lMovimientos, onMovimientos),
            ),
            _QuickActionCard(
              icon: Icons.fact_check_outlined,
              label: lAuditoria,
              onTap: () => _handleTap(context, lAuditoria, onAuditoria),
            ),
            _QuickActionCard(
              icon: Icons.help_outline,
              label: lAyuda,
              onTap: () => _handleTap(context, lAyuda, onAyuda),
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
    final oscuro = theme.brightness == Brightness.dark;
    final icono = oscuro
        ? Colors.white.withValues(alpha: 0.9)
        : theme.colorScheme.onSurface;
    final fondo = oscuro
        ? Colors.white.withValues(alpha: 0.05)
        : theme.colorScheme.surfaceContainerHighest;
    final borde = oscuro
        ? Colors.white.withValues(alpha: 0.1)
        : theme.colorScheme.outlineVariant;
    final sombra = oscuro
        ? Colors.black.withValues(alpha: 0.15)
        : theme.colorScheme.shadow.withValues(alpha: 0.08);
    final badgeFondo = oscuro
        ? Colors.white.withValues(alpha: 0.12)
        : theme.colorScheme.primary.withValues(alpha: 0.1);
    final badgeTexto = oscuro
        ? Colors.white.withValues(alpha: 0.7)
        : theme.colorScheme.primary;

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
                color: fondo,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: borde,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: sombra,
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
                    color: icono,
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
                        color: badgeFondo,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        shortcut!,
                        style: TextStyle(
                          color: badgeTexto,
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