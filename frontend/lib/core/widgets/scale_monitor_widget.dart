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

/// Fuentes disponibles para el display del monitor.
/// Se pueden cambiar en runtime desde el engranaje del display.
class DisplayFont {
  final String label;
  final String? fontFamily;
  const DisplayFont(this.label, this.fontFamily);
}

const List<DisplayFont> kDisplayFonts = [
  DisplayFont('DSEG7 Classic Bold', 'DSEG7ClassicBold'),
  DisplayFont('DSEG7 Classic Regular', 'DSEG7ClassicRegular'),
  DisplayFont('DSEG7 Modern Bold', 'DSEG7ModernBold'),
  DisplayFont('DSEG14 Classic Bold', 'DSEG14ClassicBold'),
  DisplayFont('DSEG14 Classic Regular', 'DSEG14ClassicRegular'),
  DisplayFont('DSEG14 Modern Bold', 'DSEG14ModernBold'),
  DisplayFont('Monoespaciada (sistema)', null),
];

/// Widget que muestra el peso en tiempo real proveniente de la balanza (BSDD).
/// Con `balanzaId` lee vía el HAL del backend (API); sin él cae a TCP directo.
///
/// Presentación: indicador industrial (display DSEG + LEDs).
class ScaleMonitorWidget extends StatefulWidget {
  final ScaleTcpClient client;
  final String label;
  final double initialWeight;
  final ValueChanged<double>? onPesoLeido;
  final bool mostrarBotones;

  /// id_balanza seleccionada para lectura vía API (HAL). Null → TCP directo.
  final String? balanzaId;
  final String? balanzaDescripcion;

  /// Permite elegir la fuente del display desde el engranaje.
  final bool permitirCambiarFuente;

  const ScaleMonitorWidget({
    super.key,
    required this.client,
    this.label = 'Báscula en vivo',
    this.initialWeight = 0,
    this.onPesoLeido,
    this.mostrarBotones = true,
    this.balanzaId,
    this.balanzaDescripcion,
    this.permitirCambiarFuente = true,
  });

  @override
  State<ScaleMonitorWidget> createState() => _ScaleMonitorWidgetState();
}

class _ScaleMonitorWidgetState extends State<ScaleMonitorWidget> {
  late double _peso = widget.initialWeight;
  bool _neto = false;

  /// Índice de la fuente seleccionada en [kDisplayFonts].
  int _fontIndex = 0;

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
    }
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (peso != null) widget.onPesoLeido?.call(peso);
        setState(() {});
      });
    } else {
      if (peso != null) widget.onPesoLeido?.call(peso);
      setState(() {});
    }
  }

  ScaleStatus _statusActual({required bool conectado, required bool estable}) {
    if (!conectado) return ScaleStatus.desconectado;
    if (!estable) return ScaleStatus.inestable;
    return ScaleStatus.estable;
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

  /// Abre un menú desplegable con las fuentes disponibles.
  Future<void> _abrirMenuFuentes() async {
    final seleccionado = await showMenu<int>(
      context: context,
      position: const RelativeRect.fromLTRB(0, 0, 0, 0),
      items: [
        const PopupMenuItem<int>(
          enabled: false,
          height: 32,
          child: Text(
            'Fuente del display',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ),
        const PopupMenuDivider(),
        for (var i = 0; i < kDisplayFonts.length; i++)
          PopupMenuItem<int>(
            value: i,
            child: Row(
              children: [
                Icon(
                  i == _fontIndex
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: i == _fontIndex ? SwsColors.success : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    kDisplayFonts[i].label,
                    style: TextStyle(
                      fontFamily: kDisplayFonts[i].fontFamily,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    if (seleccionado != null && mounted) {
      setState(() => _fontIndex = seleccionado);
    }
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

    final fuenteActual = kDisplayFonts[_fontIndex.clamp(0, kDisplayFonts.length - 1)];

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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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

            // ── Display tipo indicador ────────────────────────────────
            _DisplayIndicador(
              peso: peso,
              unidad: cliente.ultimoPeso?.unidad ?? 'kg',
              neto: _neto,
              conectado: conectado,
              status: status,
              fontFamily: fuenteActual.fontFamily,
              onAbrirFuentes:
                  widget.permitirCambiarFuente ? _abrirMenuFuentes : null,
            ),
            const SizedBox(height: 8),

            // ── Fila de LEDs triangulares (estilo indicador) ─────────────
            _FilaLeds(
              status: status,
              neto: _neto,
              unidad: (cliente.ultimoPeso?.unidad ?? 'kg').toLowerCase(),
            ),

            // ── Botón "Tomar peso" ───────────────────────────────────
            if (widget.mostrarBotones && conectado) ...[
              const SizedBox(height: 10),
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
// Display principal (negro + dígitos DSEG con glow)
// ═══════════════════════════════════════════════════════════════════════════
class _DisplayIndicador extends StatelessWidget {
  final double peso;
  final String unidad;
  final bool neto;
  final bool conectado;
  final ScaleStatus status;

  /// Familia de fuente DSEG a usar (null → monospace del sistema).
  final String? fontFamily;

  /// Callback del engranaje. Null → no se muestra el botón.
  final VoidCallback? onAbrirFuentes;

  const _DisplayIndicador({
    required this.peso,
    required this.unidad,
    required this.neto,
    required this.conectado,
    required this.status,
    this.fontFamily,
    this.onAbrirFuentes,
  });

  Color _colorDigitos() {
    if (!conectado) return const Color(0xFF3A3A3A);
    switch (status) {
      case ScaleStatus.estable:
      case ScaleStatus.aceptable:
        return const Color(0xFF39FF14);
      case ScaleStatus.inestable:
        return const Color(0xFFFFC107);
      case ScaleStatus.over:
      case ScaleStatus.under:
        return const Color(0xFFFF3B30);
      default:
        return const Color(0xFF5A5A5A);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorDigitos();
    final texto = peso.toStringAsFixed(2);
    final apagado = color == const Color(0xFF3A3A3A);

    List<Shadow>? glowShadows([double base = 1.0]) {
      if (apagado) return null;
      return [
        Shadow(
          color: color.withValues(alpha: 0.85 * base),
          blurRadius: 12 * base,
        ),
        Shadow(
          color: color.withValues(alpha: 0.55 * base),
          blurRadius: 24 * base,
        ),
      ];
    }

    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                  padding: const EdgeInsets.only(right: 14),
                  child: Text(
                    'NET',
                    style: TextStyle(
                      fontFamily: fontFamily,
                      fontSize: 22,
                      fontWeight: FontWeight.w400,
                      height: 1.0,
                      color: Colors.greenAccent.withValues(alpha: 0.9),
                      shadows: [
                        Shadow(
                          color: Colors.greenAccent.withValues(alpha: 0.7),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      texto,
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: fontFamily,
                        fontSize: 68,
                        fontWeight: FontWeight.w400,
                        height: 1.0,
                        letterSpacing: 2,
                        color: color,
                        shadows: glowShadows(),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Text(
                unidad.toUpperCase(),
                style: TextStyle(
                  fontFamily: fontFamily,
                  fontSize: 22,
                  fontWeight: FontWeight.w400,
                  height: 1.0,
                  letterSpacing: 1,
                  color: apagado ? color : color.withValues(alpha: 0.9),
                  shadows: glowShadows(0.7),
                ),
              ),
            ],
          ),
        ),

        // ── Engranaje para cambiar la fuente (esquina superior derecha) ──
        if (onAbrirFuentes != null)
          Positioned(
            top: 2,
            right: 2,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onAbrirFuentes,
                borderRadius: BorderRadius.circular(20),
                child: Tooltip(
                  message: 'Cambiar fuente del display',
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    child: const Icon(
                      Icons.settings,
                      size: 18,
                      color: Color(0xFF6A6A6A),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
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