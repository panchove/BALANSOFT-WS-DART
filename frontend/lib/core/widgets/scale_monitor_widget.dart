import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../../data/services/scale_api_client.dart';
import '../../data/services/scale_tcp_client.dart';

/// Widget que muestra el peso en tiempo real proveniente de la balanza (BSDD).
/// Con `balanzaId` lee vía el HAL del backend (API); sin él cae a TCP directo.
class ScaleMonitorWidget extends StatefulWidget {
  final ScaleTcpClient client;
  final String label;
  final double initialWeight;
  final ValueChanged<double>? onPesoLeido;
  final bool mostrarBotones;

  /// id_balanza seleccionada para lectura vía API (HAL). Null → TCP directo.
  final String? balanzaId;
  final String? balanzaDescripcion;

  const ScaleMonitorWidget({
    super.key,
    required this.client,
    this.label = 'Báscula en vivo',
    this.initialWeight = 0,
    this.onPesoLeido,
    this.mostrarBotones = true,
    this.balanzaId,
    this.balanzaDescripcion,
  });

  @override
  State<ScaleMonitorWidget> createState() => _ScaleMonitorWidgetState();
}

class _ScaleMonitorWidgetState extends State<ScaleMonitorWidget> {
  late double _peso = widget.initialWeight;

  @override
  void initState() {
    super.initState();
    _configurarCliente();
    widget.client.addListener(_onCambioPeso);
    widget.client.conectar();
  }

  @override
  void didUpdateWidget(ScaleMonitorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.balanzaId != widget.balanzaId ||
        oldWidget.balanzaDescripcion != widget.balanzaDescripcion) {
      _configurarCliente();
      widget.client.conectar();
    }
  }

  void _configurarCliente() {
    final cliente = widget.client;
    if (cliente is ScaleApiClient) {
      cliente.configurarApi(
        balanzaId: widget.balanzaId,
        descripcion: widget.balanzaDescripcion ?? '',
      );
    }
  }

  @override
  void dispose() {
    widget.client.removeListener(_onCambioPeso);
    super.dispose();
  }

  void _onCambioPeso() {
    if (!mounted) return;
    setState(() {
      final peso = widget.client.pesoActual;
      if (peso != null) {
        _peso = peso;
        widget.onPesoLeido?.call(peso);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cliente = widget.client;
    final conectado = cliente.conectado;
    final conectando = cliente.conectando;
    final peso = _peso;

    Color estadoColor;
    String estadoTexto;
    IconData estadoIcono;
    if (conectado) {
      final estable = cliente.ultimoPeso?.estable ?? true;
      estadoColor = estable ? SwsColors.success : SwsColors.warning;
      estadoTexto = estable ? 'Estable' : 'Inestable';
      estadoIcono = Icons.wifi;
    } else if (conectando) {
      estadoColor = SwsColors.warning;
      estadoTexto = 'Conectando...';
      estadoIcono = Icons.wifi_tethering;
    } else {
      estadoColor = SwsColors.danger;
      estadoTexto = 'Desconectado';
      estadoIcono = Icons.wifi_off;
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: conectado
              ? SwsColors.success.withValues(alpha: 0.4)
              : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: estadoColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(estadoIcono, size: 20, color: estadoColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        '${cliente.host}:${cliente.port} · $estadoTexto',
                        style: TextStyle(
                          fontSize: 11,
                          color: estadoColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (conectado)
                  Text(
                    cliente.ultimoPeso?.unidad ?? 'kg',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: SwsColors.gray500,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Column(
              children: [
                Text(
                  peso.toStringAsFixed(1),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                    color: conectado ? SwsColors.primary : SwsColors.gray400,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'kg',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: SwsColors.gray500,
                  ),
                ),
              ],
            ),
            if (widget.mostrarBotones && conectado) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        final p = widget.client.pesoActual;
                        if (p != null) {
                          widget.onPesoLeido?.call(p);
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Peso capturado de la báscula'),
                              backgroundColor: SwsColors.success,
                              duration: Duration(seconds: 1),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.bolt, size: 18),
                      label: const Text('Tomar peso'),
                      style: FilledButton.styleFrom(
                        backgroundColor: SwsColors.success,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (cliente.error.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.error_outline, size: 14, color: SwsColors.danger),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      cliente.error,
                      style: const TextStyle(
                          fontSize: 11, color: SwsColors.danger),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}