import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Tarjeta informativa para módulos que aún no cuentan con persistencia
/// de backend. Presenta el alcance esperado sin fabricar datos falsos.
class ProximaFase extends StatelessWidget {
  final String titulo;
  final String descripcion;
  final IconData icono;
  final List<String> alcance;

  const ProximaFase({
    super.key,
    required this.titulo,
    required this.descripcion,
    required this.icono,
    this.alcance = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: SwsColors.blue100,
                  foregroundColor: SwsColors.primary,
                  child: Icon(icono, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    titulo,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Chip(
                  label: Text(
                    'PRÓXIMA FASE',
                    style: TextStyle(fontSize: 10, letterSpacing: 0.6),
                  ),
                  backgroundColor: SwsColors.warning,
                  labelStyle: TextStyle(color: Colors.white),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.symmetric(horizontal: 6),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              descripcion,
              style: const TextStyle(color: SwsColors.gray600, height: 1.4),
            ),
            if (alcance.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final a in alcance)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Icon(Icons.check_circle_outline,
                            size: 14, color: SwsColors.success),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          a,
                          style: const TextStyle(
                              fontSize: 12.5, color: SwsColors.gray600),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}