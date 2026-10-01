import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/config/app_config.dart';
import '../../../core/i18n/translations.dart';
import '../../../core/theme/app_theme.dart';
import 'setup_layout_wrapper.dart';

/// Paso 1 de la instalación: ¿esta máquina es el SERVIDOR de la cuenta o un
/// TRABAJADOR?
///
/// Solo el equipo titular de la licencia puede instalarse como servidor; esa
/// condición la decide el servidor central al validar la cuenta (paso 3): si
/// la licencia ya está activada en otro equipo, el central rechaza la
/// instalación como servidor y esta estación continúa como trabajador.
class ModeSelectionScreen extends StatelessWidget {
  const ModeSelectionScreen({super.key});

  Future<void> _elegir(BuildContext context, String modo) async {
    await AppConfig.setModoEstacion(modo);
    if (!context.mounted) return;
    Navigator.of(context).pushReplacementNamed(
      modo == 'TRABAJADOR' ? '/worker_connection' : '/setup',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: SetupLayoutWrapper(
        children: [
          // ─── Icono principal con halo de acento ──────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: SwsColors.accentLight.withValues(alpha: 0.12),
              border: Border.all(
                color: SwsColors.accentLight.withValues(alpha: 0.30),
                width: 1,
              ),
            ),
            child: const Icon(
              Icons.account_tree_outlined,
              size: 48,
              color: SwsColors.accentLight,
            ),
          ),
          const SizedBox(height: 28),

          // ─── Título ──────────────────────────────────────────────────
          Text(
            'setup_mode_title'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: SwsColors.white,
            ),
          ),
          const SizedBox(height: 12),

          // ─── Subtítulo ───────────────────────────────────────────────
          Text(
            'setup_mode_subtitle'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: SwsColors.white.withValues(alpha: 0.60),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),

          // ─── Recordatorio: solo el titular de la licencia es servidor ──
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: SwsColors.warning.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: SwsColors.warning.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline,
                    color: SwsColors.warning, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'setup_mode_license_note'.tr(),
                    style: TextStyle(
                      fontSize: 12,
                      color: SwsColors.white.withValues(alpha: 0.80),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ─── Cards de selección ──────────────────────────────────────
          _ModeCard(
            key: const Key('modo_servidor_card'),
            title: 'setup_mode_server'.tr(),
            description: 'setup_mode_server_desc'.tr(),
            icon: Icons.dns_outlined,
            onTap: () => _elegir(context, 'SERVIDOR'),
          ),
          const SizedBox(height: 16),
          _ModeCard(
            key: const Key('modo_trabajador_card'),
            title: 'setup_mode_client'.tr(),
            description: 'setup_mode_client_desc'.tr(),
            icon: Icons.computer_outlined,
            onTap: () => _elegir(context, 'TRABAJADOR'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Card de modo (Servidor / Cliente)
// ─────────────────────────────────────────────────────────────────────────
class _ModeCard extends StatelessWidget {
  const _ModeCard({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            // Mismo tono translúcido que las cards del login
            color: SwsColors.surfaceGlass,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: SwsColors.surfaceGlassBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // Icono con fondo acento tenue
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: SwsColors.accentLight.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: SwsColors.accentLight.withValues(alpha: 0.30),
                    ),
                  ),
                  child: Icon(icon, size: 28, color: SwsColors.accentLight),
                ),
                const SizedBox(width: 20),

                // Textos
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: SwsColors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 13,
                          color: SwsColors.white.withValues(alpha: 0.60),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Flecha
                Icon(
                  Icons.arrow_forward_ios,
                  color: SwsColors.white.withValues(alpha: 0.38),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
