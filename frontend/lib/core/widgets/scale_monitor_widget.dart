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

/// Velocidades serie admitidas por el `CHECK ck_balanzas_baudrate` de la BD.
/// Cualquier otro valor lo rechazaría Pydantic (422) y la base de datos.
const List<int> kScaleBaudrates = [
  1200,
  2400,
  4800,
  9600,
  19200,
  38400,
  57600,
  115200,
];

/// Frecuencias de refresco del display cuando el peso llega por API (ms).
const List<int> kMonitorRefreshMs = [250, 500, 1000, 2000];

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

  /// Velocidad serial (baudios) **actual** de la báscula que alimenta el
  /// display. `null` → el engranaje no ofrece el ajuste (báscula TCP, que no
  /// usa puerto serie, o formulario sin báscula seleccionada).
  final int? baudrate;

  /// Guarda la nueva velocidad y devuelve cuando terminó. `null` → el ajuste
  /// no se muestra. La persistencia (PUT `/balanzas/{id}`) la hace el padre:
  /// el widget solo es UI.
  final Future<void> Function(int baudrate)? onBaudrateCambiado;

  /// `false` para roles sin permiso de edición (la API exige ADMIN): el
  /// selector se muestra deshabilitado y con el motivo, para que el operador
  /// entienda por qué no puede tocarlo.
  final bool puedeEditarBaudrate;

  /// Frecuencia de refresco del display cuando el peso llega por API.
  final Duration intervaloActualizacion;

  /// Aviso al elegir otra frecuencia. `null` → no se ofrece el ajuste.
  final ValueChanged<Duration>? onIntervaloCambiado;

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
    this.baudrate,
    this.onBaudrateCambiado,
    this.puedeEditarBaudrate = false,
    this.intervaloActualizacion = ScaleApiClient.intervaloPorDefecto,
    this.onIntervaloCambiado,
  });

  @override
  State<ScaleMonitorWidget> createState() => _ScaleMonitorWidgetState();
}

class _ScaleMonitorWidgetState extends State<ScaleMonitorWidget> {
  late double _peso = widget.initialWeight;
  final bool _neto = false;

  /// Índice de la fuente seleccionada en [kDisplayFonts].
  int _fontIndex = 0;

  /// Frecuencia de refresco vigente (se aplica al cliente de API).
  late Duration _intervalo = widget.intervaloActualizacion;

  @override
  void initState() {
    super.initState();
    _configurarCliente();
    _aplicarIntervalo();
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
    if (oldWidget.intervaloActualizacion != widget.intervaloActualizacion) {
      _intervalo = widget.intervaloActualizacion;
      _aplicarIntervalo();
    }
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

  /// Traslada la frecuencia elegida al sondeo del HAL (solo API; el TCP
  /// directo ya empuja cada trama que llega).
  void _aplicarIntervalo() {
    final cliente = widget.client;
    if (cliente is ScaleApiClient) cliente.setIntervalo(_intervalo);
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

  /// Abre el diálogo de configuración del display: fuente, velocidad serial de
  /// la báscula y frecuencia de refresco del monitor.
  ///
  /// El widget es solo UI: la velocidad la persiste el padre (PUT
  /// `/balanzas/{id}`) y la frecuencia, la estación (preferencia local).
  Future<void> _abrirConfiguracion() async {
    final resultado = await showDialog<_ConfigDisplay>(
      context: context,
      builder: (_) => _ConfigDisplayDialog(
        fontIndex: _fontIndex,
        permitirFuente: widget.permitirCambiarFuente,
        baudrate: widget.baudrate,
        puedeEditarBaudrate: widget.puedeEditarBaudrate,
        intervaloMs: _intervalo.inMilliseconds,
        permitirIntervalo: widget.onIntervaloCambiado != null,
      ),
    );
    if (resultado == null || !mounted) return;

    if (resultado.fontIndex != _fontIndex) {
      setState(() => _fontIndex = resultado.fontIndex);
    }

    final baudrate = resultado.baudrate;
    final cambiarBaudrate = baudrate != null &&
        baudrate != widget.baudrate &&
        widget.onBaudrateCambiado != null;
    if (cambiarBaudrate) {
      try {
        await widget.onBaudrateCambiado!(baudrate);
        if (!mounted) return;
        _avisar('display_baudrate_ok'.tr().replaceFirst('{}', '$baudrate'));
      } catch (_) {
        if (!mounted) return;
        _avisar('display_baudrate_error'.tr(), error: true);
      }
    }

    if (resultado.intervaloMs != _intervalo.inMilliseconds) {
      final nuevo = Duration(milliseconds: resultado.intervaloMs);
      setState(() => _intervalo = nuevo);
      _aplicarIntervalo();
      widget.onIntervaloCambiado?.call(nuevo);
    }
  }

  void _avisar(String texto, {bool error = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: error ? SwsColors.danger : SwsColors.success,
        duration: const Duration(seconds: 2),
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

    final estadoColor = esVerde
      ? SwsColors.success
      : esAmarillo
          ? SwsColors.warning
          : SwsColors.gray500;
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

    final puedeConfigurar = widget.permitirCambiarFuente ||
        (widget.baudrate != null && widget.onBaudrateCambiado != null) ||
        widget.onIntervaloCambiado != null;

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
                    // Altura fija para evitar saltos en la cabecera
                    children: [
                      SizedBox(
                        height: 20,
                        child: Text(
                          context.tr(widget.label),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 2),
                      SizedBox(
                        height: 16,
                        child: Text(
                          '${cliente.host}:${cliente.port} · $estadoTexto',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: conectado
                                ? estadoColor
                                : SwsColors.gray500,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
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
              onAbrirConfiguracion:
                  puedeConfigurar ? _abrirConfiguracion : null,
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

            if (cliente.error.isNotEmpty && !conectado) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.link_off,
                      size: 14, color: SwsColors.gray500),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Báscula desconectada',
                      style: TextStyle(
                        fontSize: 11,
                        color: SwsColors.gray500,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
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
  final VoidCallback? onAbrirConfiguracion;

  const _DisplayIndicador({
    required this.peso,
    required this.unidad,
    required this.neto,
    required this.conectado,
    required this.status,
    this.fontFamily,
    this.onAbrirConfiguracion,
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
    
    // padLeft asegura que el texto ocupe siempre el mismo ancho, evitando 
    // que se expanda y contraiga al cambiar entre 0.00 y 1043.00
    final texto = peso.toStringAsFixed(2).padLeft(8);
    
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
          // ALTURA FIJA: Evita que el widget cambie de tamaño
          height: 110, 
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                unidad,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  height: 1.0,
                  letterSpacing: 1,
                  color: apagado ? color : color.withValues(alpha: 0.9),
                  shadows: glowShadows(0.7),
                ),
              ),
            ],
          ),
        ),

        // ── Engranaje de configuración (esquina superior derecha) ────────
        if (onAbrirConfiguracion != null)
          Positioned(
            top: 2,
            right: 2,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onAbrirConfiguracion,
                borderRadius: BorderRadius.circular(20),
                child: Tooltip(
                  message: context.tr('display_config_title'),
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

// ═══════════════════════════════════════════════════════════════════════════
// Diálogo de configuración del display (fuente · baudios · refresco)
// ═══════════════════════════════════════════════════════════════════════════

/// Valores elegidos en el diálogo de configuración del display.
class _ConfigDisplay {
  final int fontIndex;
  final int? baudrate;
  final int intervaloMs;

  const _ConfigDisplay({
    required this.fontIndex,
    this.baudrate,
    required this.intervaloMs,
  });
}

class _ConfigDisplayDialog extends StatefulWidget {
  final int fontIndex;
  final bool permitirFuente;
  final int? baudrate;
  final bool puedeEditarBaudrate;
  final int intervaloMs;
  final bool permitirIntervalo;

  const _ConfigDisplayDialog({
    required this.fontIndex,
    required this.permitirFuente,
    required this.baudrate,
    required this.puedeEditarBaudrate,
    required this.intervaloMs,
    required this.permitirIntervalo,
  });

  @override
  State<_ConfigDisplayDialog> createState() => _ConfigDisplayDialogState();
}

class _ConfigDisplayDialogState extends State<_ConfigDisplayDialog> {
  late int _fontIndex = widget.fontIndex;
  late int? _baudrate = widget.baudrate;
  late int _intervaloMs = widget.intervaloMs;

  /// Etiqueta legible de una frecuencia de refresco.
  String _etiquetaIntervalo(int ms) {
    if (ms % 1000 == 0) return '${ms ~/ 1000} s';
    return '$ms ms';
  }

  Widget _titulo(BuildContext context, String clave) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          context.tr(clave),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      );

  Widget _ayuda(BuildContext context, String clave, {bool aviso = false}) =>
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          context.tr(clave),
          style: TextStyle(
            fontSize: 11.5,
            color: aviso
                ? SwsColors.warning
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final tieneBaudrate = widget.baudrate != null;
    final opcionesBaudrate = <int>{
      ...kScaleBaudrates,
      if (widget.baudrate != null) widget.baudrate!,
    }.toList()
      ..sort();
    final opcionesRefresco = <int>{
      ...kMonitorRefreshMs,
      _intervaloMs,
    }.toList()
      ..sort();

    return AlertDialog(
      title: Text(context.tr('display_config_title')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.permitirFuente) ...[
                _titulo(context, 'display_config_font'),
                DropdownButtonFormField<int>(
                  key: const Key('display_font_dropdown'),
                  initialValue: _fontIndex,
                  isExpanded: true,
                  items: [
                    for (var i = 0; i < kDisplayFonts.length; i++)
                      DropdownMenuItem<int>(
                        value: i,
                        child: Text(
                          kDisplayFonts[i].label,
                          style: TextStyle(fontFamily: kDisplayFonts[i].fontFamily),
                        ),
                      ),
                  ],
                  onChanged: (v) =>
                      setState(() => _fontIndex = v ?? _fontIndex),
                ),
                const SizedBox(height: 16),
              ],
              if (tieneBaudrate) ...[
                _titulo(context, 'display_config_baudrate'),
                DropdownButtonFormField<int>(
                  key: const Key('display_baudrate_dropdown'),
                  initialValue: _baudrate,
                  isExpanded: true,
                  items: [
                    for (final b in opcionesBaudrate)
                      DropdownMenuItem<int>(value: b, child: Text('$b')),
                  ],
                  onChanged: widget.puedeEditarBaudrate
                      ? (v) => setState(() => _baudrate = v ?? _baudrate)
                      : null,
                ),
                _ayuda(
                  context,
                  widget.puedeEditarBaudrate
                      ? 'display_config_baudrate_help'
                      : 'display_config_baudrate_admin_only',
                  aviso: !widget.puedeEditarBaudrate,
                ),
                const SizedBox(height: 16),
              ],
              if (widget.permitirIntervalo) ...[
                _titulo(context, 'display_config_refresh'),
                DropdownButtonFormField<int>(
                  key: const Key('display_refresh_dropdown'),
                  initialValue: _intervaloMs,
                  isExpanded: true,
                  items: [
                    for (final ms in opcionesRefresco)
                      DropdownMenuItem<int>(
                        value: ms,
                        child: Text(_etiquetaIntervalo(ms)),
                      ),
                  ],
                  onChanged: (v) =>
                      setState(() => _intervaloMs = v ?? _intervaloMs),
                ),
                _ayuda(context, 'display_config_refresh_help'),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('display_config_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('cancel')),
        ),
        FilledButton(
          key: const Key('display_config_apply'),
          onPressed: () => Navigator.of(context).pop(
            _ConfigDisplay(
              fontIndex: _fontIndex,
              baudrate: tieneBaudrate ? _baudrate : null,
              intervaloMs: _intervaloMs,
            ),
          ),
          child: Text(context.tr('apply')),
        ),
      ],
    );
  }
}