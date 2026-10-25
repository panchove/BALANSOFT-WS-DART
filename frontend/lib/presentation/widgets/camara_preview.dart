import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/constants/api_constants.dart';
import '../../core/i18n/translations.dart';
import '../../core/theme/app_theme.dart';
import '../../data/datasources/remote/api_client.dart';
import '../../injection.dart' as di;

/// Mirada **en vivo** de una cámara: refresca el *frame* continuamente.
///
/// Es el «modo video» de la captura de placa. La cámara no tiene un flujo
/// MJPEG universal (la ruta y el formato dependen de la marca), así que el
/// widget **repite** `GET /camaras/{id}/snapshot` a un ritmo alto (≈5 fps) y
/// pinta cada cuadro encima del anterior: el operador ve la imagen moverse y
/// puede colocar el vehículo antes de capturar.
///
/// Expone el **último cuadro recibido** por [onFrame]: así el botón «Capturar»
/// guarda exactamente lo que el operador tiene delante, no una foto nueva.
class CamaraPreview extends StatefulWidget {
  const CamaraPreview({
    super.key,
    required this.camaraId,
    this.height = 180,
    this.onFrame,
    this.activo = true,
    this.fps = 5,
  });

  /// Identificador de la cámara registrada (`/camaras/{id}/snapshot`).
  final String camaraId;

  /// Alto de la vista previa.
  final double height;

  /// Notifica cada cuadro válido (el más reciente) para capturarlo tal cual.
  final void Function(Uint8List bytes)? onFrame;

  /// Si es `false` el refresco se detiene (p. ej. al cerrar el panel).
  final bool activo;

  /// Cuadros por segundo del refresco.
  final int fps;

  @override
  State<CamaraPreview> createState() => _CamaraPreviewState();
}

class _CamaraPreviewState extends State<CamaraPreview> {
  final ApiClient _api = di.sl<ApiClient>();

  Uint8List? _frame;
  bool _sinSenal = false;
  bool _cargando = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _reiniciar();
  }

  @override
  void didUpdateWidget(CamaraPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.camaraId != widget.camaraId ||
        oldWidget.activo != widget.activo) {
      _reiniciar();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _reiniciar() {
    _timer?.cancel();
    if (!widget.activo) return;
    setState(() {
      _sinSenal = false;
      _frame = null;
    });
    unawaited(_traerCuadro());
    final intervalo = Duration(milliseconds: (1000 / widget.fps).round());
    _timer = Timer.periodic(intervalo, (_) => unawaited(_traerCuadro()));
  }

  /// Trae un cuadro. Si ya hay una petición en curso no lanza otra: con una
  /// cámara lenta (IP por WiFi) el turno anterior puede tardar más que el
  /// intervalo y encolar peticiones saturaría la red local.
  Future<void> _traerCuadro() async {
    if (_cargando) return;
    _cargando = true;
    try {
      final bytes = await _api.getBytes(ApiConstants.camaraSnapshot(widget.camaraId));
      if (!mounted) return;
      if (bytes.isEmpty) {
        setState(() => _sinSenal = true);
        return;
      }
      setState(() {
        _frame = bytes;
        _sinSenal = false;
      });
      widget.onFrame?.call(bytes);
    } catch (_) {
      if (!mounted) return;
      setState(() => _sinSenal = _frame == null);
    } finally {
      _cargando = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: widget.height,
        width: double.infinity,
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_frame != null)
              Image.memory(
                _frame!,
                key: const Key('camara_frame'),
                fit: BoxFit.cover,
                gaplessPlayback: true,
              )
            else
              Center(
                child: _sinSenal
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.videocam_off_outlined,
                              color: Colors.white70, size: 30),
                          const SizedBox(height: 6),
                          Text(
                            'camara_sin_senal'.tr(),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      )
                    : const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
              ),
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.fiber_manual_record,
                        color: SwsColors.danger, size: 9),
                    const SizedBox(width: 4),
                    Text(
                      'camara_en_vivo'.tr(),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
