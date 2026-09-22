import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import 'setup_layout_wrapper.dart';

class ModeSelectionScreen extends StatelessWidget {
  const ModeSelectionScreen({super.key});

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
          const Text(
            '¿Cómo funcionará esta máquina?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: SwsColors.white,
            ),
          ),
          const SizedBox(height: 12),

          // ─── Subtítulo ───────────────────────────────────────────────
          Text(
            'Balansoft-WS puede ejecutarse como Servidor (alojando la base de datos local y comunicándose con el peso) o como Estación Cliente (conectándose a un Servidor existente en tu red local).',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: SwsColors.white.withValues(alpha: 0.60),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 40),

          // ─── Cards de selección ──────────────────────────────────────
          _ModeCard(
            title: 'Servidor Principal',
            description:
                'Esta máquina alojará la base de datos local, se conectará a la balanza y procesará los pesajes.',
            icon: Icons.dns_outlined,
            onTap: () {
              Navigator.of(context).pushReplacementNamed('/setup');
            },
          ),
          const SizedBox(height: 16),
          _ModeCard(
            title: 'Estación Cliente',
            description:
                'Esta máquina solo operará el sistema conectándose a un Servidor Principal que ya esté configurado en tu red.',
            icon: Icons.computer_outlined,
            onTap: () {
              Navigator.of(context).pushReplacementNamed('/connections');
            },
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