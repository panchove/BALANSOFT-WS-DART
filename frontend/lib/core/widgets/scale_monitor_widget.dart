import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../i18n/translations.dart';
import '../theme/app_theme.dart';
import '../../data/services/scale_api_client.dart';
import '../../data/services/scale_tcp_client.dart';

/// Estado resumido del pesaje para pintar el display y los LEDs.
enum ScaleStatus {
  estable,
  inestable,
  aceptable,
  under,
  over,
  net,
  desconectado,
}

/// Widget que muestra el peso en tiempo real proveniente de la balanza (BSDD).
/// Con `balanzaId` lee vía el HAL del backend (API); sin él cae a TCP directo.
///
/// Presentación: indicador industrial (display 7-seg verde + LEDs + teclado).
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
  bool _neto = false;

  @override
  void initState() {
    super.initState();
    _configurarCliente();
    widget.client.addListener(_onCambioPeso);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.client.conectar();
      }
    });
  }

  @override
  void didUpdateWidget(ScaleMonitorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.balanzaId != widget.balanzaId ||
        oldWidget.balanzaDescripcion != widget.balanzaDescripcion) {
      _configurarCliente();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.client.conectar();
        }
      });
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
    final peso = widget.client.pesoActual;
    if (peso != null) {
      _peso = peso;
      widget.onPesoLeido?.call(peso);
    }
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
        }
      });
    } else {
      setState(() {});
    }
  }

  // ─── Derivación de estado para pintar LEDs y colores ────────────────────
  ScaleStatus _statusActual({required bool conectado, required bool estable}) {
    if (!conectado) return ScaleStatus.desconectado;
    if (!estable) return ScaleStatus.inestable;
    return ScaleStatus.estable;
  }

  // ─── Handlers de los botones del indicador ──────────────────────────────
  void _onCero() {
    // Solo limpia el display local; el cero real lo maneja la balanza.
    setState(() => _peso = 0);
    widget.onPesoLeido?.call(0);
  }

  void _onTara() {
    setState(() => _neto = !_neto);
  }

  void _onClear() {
    setState(() {
      _peso = widget.initialWeight;
      _neto = false;
    });
  }

  void _onCapturar() {
    final p = widget.client.pesoActual;
    if (p == null) return;
    widget.onPesoLeido?.call(p);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr('Peso capturado de la báscula')),
        backgroundColor: SwsColors.success,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cliente = widget.client;
    final conectado = cliente.conectado;
    final conectando = cliente.conectando;
    final peso = _peso;
    final estable = cliente.ultimoPeso?.estable ?? true;

    final status = _statusActual(conectado: conectado, estable: estable);
    final esVerde = status == ScaleStatus.estable;
    final esAmarillo = status == ScaleStatus.inestable || conectando;
    final esRojo = status == ScaleStatus.desconectado;

    // Estado textual mostrado bajo el nombre de la balanza.
    final estadoColor = esVerde
        ? SwsColors.success
        : esAmarillo
            ? SwsColors.warning
            : SwsColors.danger;
    final estadoTexto = esVerde
        ? context.tr('Estable')
        : esAmarillo
            ? (conectando
                ? context.tr('Conectando...')
                : context.tr('Recibiendo peso…'))
            : context.tr('Desconectado');
    final estadoIcono = esVerde
        ? Icons.check_circle
        : esAmarillo
            ? Icons.sync
            : Icons.wifi_off;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: conectado
              ? SwsColors.success.withValues(alpha: 0.4)
              : Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Cabecera: nombre + estado ────────────────────────────────
            Row(
              children: [
                Icon(estadoIcono, size: 18, color: estadoColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr(widget.label),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${cliente.host}:${cliente.port} · $estadoTexto',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: estadoColor,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (conectado)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: estadoColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      cliente.ultimoPeso?.unidad ?? 'kg',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: estadoColor,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Display tipo indicador (7-seg, verde/ámbar/rojo) ─────────
            _DisplayIndicador(
              peso: peso,
              unidad: cliente.ultimoPeso?.unidad ?? 'kg',
              neto: _neto,
              conectado: conectado,
              status: status,
            ),
            const SizedBox(height: 8),

            // ── Fila de LEDs triangulares (estilo indicador) ─────────────
            _FilaLeds(
              status: status,
              neto: _neto,
              unidad: (cliente.ultimoPeso?.unidad ?? 'kg').toLowerCase(),
            ),

            // ── Teclado de funciones (solo si hay conexión) ──────────────
            if (widget.mostrarBotones && conectado) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _BtnIndicador(
                      icon: Icons.power_settings_new,
                      tooltip: 'Encendido',
                      onTap: () {},
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _BtnIndicador(
                      icon: Icons.exposure_zero,
                      tooltip: 'Cero (→0←)',
                      onTap: _onCero,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _BtnIndicador(
                      label: 'T',
                      tooltip: 'Tara (→T←)',
                      activo: _neto,
                      onTap: _onTara,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _BtnIndicador(
                      label: 'F',
                      tooltip: 'Función',
                      onTap: () {},
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _BtnIndicador(
                      label: 'C',
                      tooltip: 'Clear',
                      onTap: _onClear,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _BtnIndicador(
                      icon: Icons.print,
                      tooltip: 'Imprimir',
                      onTap: () {},
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Botón "Tomar peso" — captura estable
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: estable ? _onCapturar : null,
                  icon: Icon(
                    estable ? Icons.bolt : Icons.hourglass_top,
                    size: 18,
                  ),
                  label: Text(
                    estable
                        ? context.tr('Tomar peso')
                        : context.tr('Recibiendo peso…'),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: SwsColors.success,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],

            if (cliente.error.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.error_outline,
                      size: 14, color: SwsColors.danger),
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

// ═══════════════════════════════════════════════════════════════════════════
// Display principal (negro + dígitos 7-seg con glow)
// ═══════════════════════════════════════════════════════════════════════════
class _DisplayIndicador extends StatelessWidget {
  final double peso;
  final String unidad;
  final bool neto;
  final bool conectado;
  final ScaleStatus status;

  const _DisplayIndicador({
    required this.peso,
    required this.unidad,
    required this.neto,
    required this.conectado,
    required this.status,
  });

  Color _colorDigitos() {
    if (!conectado) return const Color(0xFF3A3A3A); // apagado
    switch (status) {
      case ScaleStatus.estable:
      case ScaleStatus.aceptable:
        return const Color(0xFF39FF14); // verde neón
      case ScaleStatus.inestable:
        return const Color(0xFFFFC107); // ámbar
      case ScaleStatus.over:
      case ScaleStatus.under:
        return const Color(0xFFFF3B30); // rojo
      default:
        return const Color(0xFF5A5A5A);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorDigitos();
    final texto = peso.toStringAsFixed(2);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2A2A2A), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (neto)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                'NET',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.greenAccent.withValues(alpha: 0.9),
                  letterSpacing: 1.2,
                ),
              ),
            ),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                texto,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 52,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                  height: 1.0,
                  color: color,
                  shadows: color == const Color(0xFF3A3A3A)
                      ? null
                      : [
                          Shadow(
                            color: color.withValues(alpha: 0.8),
                            blurRadius: 10,
                          ),
                        ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            unidad,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color == const Color(0xFF3A3A3A)
                  ? color
                  : color.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Fila de LEDs triangulares
// ═══════════════════════════════════════════════════════════════════════════
class _FilaLeds extends StatelessWidget {
  final ScaleStatus status;
  final bool neto;
  final String unidad;

  const _FilaLeds({
    required this.status,
    required this.neto,
    required this.unidad,
  });

  @override
  Widget build(BuildContext context) {
    final items = <_LedItem>[
      _LedItem('Under', status == ScaleStatus.under),
      _LedItem('OK',
          status == ScaleStatus.estable || status == ScaleStatus.aceptable),
      _LedItem('Over', status == ScaleStatus.over),
      _LedItem('~', status == ScaleStatus.inestable),
      _LedItem('Net', neto),
      _LedItem('<1>', false),
      _LedItem('<2>', false),
      _LedItem('lb', unidad == 'lb'),
      _LedItem('kg', unidad == 'kg'),
      _LedItem('🖨', false),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: items.map((e) => _LedChip(item: e)).toList(),
      ),
    );
  }
}

class _LedItem {
  final String label;
  final bool on;
  _LedItem(this.label, this.on);
}

class _LedChip extends StatelessWidget {
  final _LedItem item;
  const _LedChip({required this.item});

  @override
  Widget build(BuildContext context) {
    final color = item.on ? const Color(0xFF39FF14) : const Color(0xFF3A3A3A);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size(9, 5),
          painter: _TrianglePainter(color: color),
        ),
        const SizedBox(height: 2),
        Text(
          item.label,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 9.5,
            fontWeight: FontWeight.bold,
            color: item.on ? color : const Color(0xFF666666),
          ),
        ),
      ],
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;
  _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter old) => old.color != color;
}

// ═══════════════════════════════════════════════════════════════════════════
// Botón tipo teclado de indicador
// ═══════════════════════════════════════════════════════════════════════════
class _BtnIndicador extends StatelessWidget {
  final IconData? icon;
  final String? label;
  final VoidCallback onTap;
  final String tooltip;
  final bool activo;

  const _BtnIndicador({
    this.icon,
    this.label,
    required this.onTap,
    required this.tooltip,
    this.activo = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: activo ? const Color(0xFF39FF14) : Colors.white,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: const Color(0xFFB0B0B0),
                width: 1.2,
              ),
            ),
            child: Center(
              child: icon != null
                  ? Icon(icon, size: 20, color: Colors.black87)
                  : Text(
                      label ?? '',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}