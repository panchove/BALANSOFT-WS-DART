import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../injection.dart' as di;

/// Ayuda: Soporte Técnico e Información del Sistema.
class AyudaScreen extends StatelessWidget {
  const AyudaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final api = di.sl<ApiClient>();

    return Scaffold(
      appBar: AppBar(title: const Text('Ayuda')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: SwsColors.blue100,
                        foregroundColor: SwsColors.primary,
                        child: Icon(Icons.headset_mic_outlined, size: 20),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Soporte técnico',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  Text(
                    'El soporte está gestionado por el equipo BALANSOFT. '
                    'Incluye instalación del cliente, configuración de '
                    'básculas (serial/TCP), licencias y resolución de '
                    'incidencias en campo.',
                    style: TextStyle(color: SwsColors.gray600, height: 1.4),
                  ),
                  SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(Icons.mail_outline,
                        size: 20, color: SwsColors.primary),
                    title: Text('soporte@balansoft.ve'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(Icons.description_outlined,
                        size: 20, color: SwsColors.primary),
                    title: Text(
                        'docs/PRD.md y docs/MODELO_ESTANDAR.md definen el '
                        'comportamiento esperado del sistema.'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            color: SwsColors.blue100,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Información del sistema',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  _fila('Producto', 'BALANSOFT-WS'),
                  _fila('Cliente', 'Flutter (BLoC, offline-first)'),
                  _fila('Servidor', 'FastAPI + PostgreSQL 15+'),
                  _fila('API', api.baseUrl),
                  _fila('Modelo de estados',
                      'PENDIENTE → CERRADO/MODIFICADO → ANULADO'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fila(String etiqueta, String valor) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(etiqueta,
                  style: const TextStyle(
                      fontSize: 12.5, color: SwsColors.gray600)),
            ),
            Expanded(
              child: SelectableText(valor,
                  style: const TextStyle(fontSize: 12.5)),
            ),
          ],
        ),
      );
}