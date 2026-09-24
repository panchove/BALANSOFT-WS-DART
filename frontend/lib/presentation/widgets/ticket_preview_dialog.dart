import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/number_utils.dart';
import '../../core/utils/save_file_utils.dart';
import '../../data/datasources/local/local_storage.dart';
import '../../data/repositories/weighing_repository.dart';
import '../../domain/entities/printer_preset.dart';
import '../../domain/entities/weighing.dart';
import '../../injection.dart' as di;

/// Modal para previsualizar el comprobante/boleto con distribución de cantidad por hoja antes de confirmar la impresión.
class TicketPreviewDialog extends StatefulWidget {
  final Weighing weighing;
  final PrinterPreset? initialPreset;
  final void Function(String formato, PrinterPreset preset)? onConfirmPrint;

  const TicketPreviewDialog({
    super.key,
    required this.weighing,
    this.initialPreset,
    this.onConfirmPrint,
  });

  @override
  State<TicketPreviewDialog> createState() => _TicketPreviewDialogState();
}

class _TicketPreviewDialogState extends State<TicketPreviewDialog> {
  late PrinterPreset _preset;
  bool _loadingPreset = true;
  bool _imprimiendo = false;
  late String _formato;

  @override
  void initState() {
    super.initState();
    if (widget.initialPreset != null) {
      _preset = widget.initialPreset!;
      _formato = _preset.formatoPredeterminado;
      _loadingPreset = false;
    } else {
      _cargarPreset();
    }
  }

  Future<void> _cargarPreset() async {
    try {
      final p = await di.sl<LocalStorage>().getPrinterPreset();
      if (mounted) {
        setState(() {
          _preset = p;
          _formato = p.formatoPredeterminado;
          _loadingPreset = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _preset = const PrinterPreset();
          _formato = 'PDF';
          _loadingPreset = false;
        });
      }
    }
  }

  Future<void> _imprimir() async {
    setState(() => _imprimiendo = true);
    try {
      if (widget.onConfirmPrint != null) {
        widget.onConfirmPrint!(_formato, _preset);
        if (mounted) Navigator.of(context).pop();
        return;
      }
      final repo = di.sl<WeighingRepository>();
      final response = _formato == 'TXT'
          ? await repo.getTicketTxt(widget.weighing.boleto)
          : await repo.getTicketPdf(
              widget.weighing.boleto,
              boletos_por_hoja: _preset.boletosPorHoja,
              tamano_papel: _preset.tamanoPapel,
              orientacion: _preset.orientacion,
              mostrar_encabezado: _preset.mostrarEncabezado,
              mostrar_detalles: _preset.mostrarDetalles,
            );
      final bytes = response.data;
      if (bytes is! List<int> || bytes.isEmpty) {
        throw Exception('El servidor no devolvió un $_formato válido.');
      }
      final extension = _formato == 'TXT' ? 'txt' : 'pdf';
      final nombreBoleto = widget.weighing.numeroBoleto ?? widget.weighing.boleto;
      final ruta = await SaveFileUtils.save(
        bytes,
        'ticket_$nombreBoleto.$extension',
        subcarpeta: 'tickets',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ticket ($_formato) guardado en: $ruta (${_preset.boletosPorHoja} por hoja, ${_preset.copias} copias)',
            ),
            backgroundColor: SwsColors.success,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al imprimir ticket: $e'),
            backgroundColor: SwsColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _imprimiendo = false);
    }
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return 'N/A';
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year;
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $h:$min';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final w = widget.weighing;
    final numBoleto = w.numeroBoleto ?? w.boleto;

    if (_loadingPreset) {
      return const AlertDialog(
        content: SizedBox(
          height: 100,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final isTermico = _preset.tamanoPapel == '80mm' || _preset.tamanoPapel == '58mm';
    final isLandscape = _preset.orientacion == 'landscape';

    // Espejo de _build_pdf (backend): en papel normal el boleto SIEMPRE es
    // estrecho y centrado (140mm de ~196mm útiles), sin importar cuántos se
    // apilen por hoja (1..4). En térmico el ancho es el del rollo.
    final anchoBase = isLandscape ? 720.0 : 520.0;
    final anchoPreview = isTermico ? 340.0 : anchoBase * (140 / 195.9);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.print, color: SwsColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Previsualización del Boleto: $numBoleto',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      content: SizedBox(
        width: isLandscape ? 820 : 700,
        height: 560,
        child: Column(
          children: [
            // ─── Barra de controles de previsualización ───
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? SwsColors.darkCard : SwsColors.light,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isDark ? SwsColors.darkBorder : Colors.grey.shade300),
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Papel
                  DropdownButton<String>(
                    value: _preset.tamanoPapel,
                    isDense: true,
                    style: const TextStyle(fontSize: 12),
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: '80mm', child: Text('80mm Térmico')),
                      DropdownMenuItem(value: '58mm', child: Text('58mm Térmico')),
                      DropdownMenuItem(value: 'HalfLetter', child: Text('Media Carta')),
                      DropdownMenuItem(value: 'Letter', child: Text('Carta')),
                      DropdownMenuItem(value: 'A4', child: Text('A4')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _preset = _preset.copyWith(tamanoPapel: val));
                    },
                  ),
                  // Cantidad por Hoja
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Por Hoja: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                      DropdownButton<int>(
                        value: _preset.boletosPorHoja,
                        isDense: true,
                        underline: const SizedBox(),
                        style: const TextStyle(fontSize: 12),
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('1 por hoja')),
                          DropdownMenuItem(value: 2, child: Text('2 por hoja')),
                          DropdownMenuItem(value: 3, child: Text('3 por hoja')),
                          DropdownMenuItem(value: 4, child: Text('4 por hoja')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _preset = _preset.copyWith(boletosPorHoja: val));
                        },
                      ),
                    ],
                  ),
                  // Orientación
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'portrait', icon: Icon(Icons.crop_portrait, size: 14), label: Text('Vertical', style: TextStyle(fontSize: 11))),
                      ButtonSegment(value: 'landscape', icon: Icon(Icons.crop_landscape, size: 14), label: Text('Horizontal', style: TextStyle(fontSize: 11))),
                    ],
                    selected: {_preset.orientacion},
                    onSelectionChanged: (val) {
                      setState(() => _preset = _preset.copyWith(orientacion: val.first));
                    },
                    style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  ),
                  // Formato
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'PDF', label: Text('PDF', style: TextStyle(fontSize: 11))),
                      ButtonSegment(value: 'TXT', label: Text('TXT', style: TextStyle(fontSize: 11))),
                    ],
                    selected: {_formato},
                    onSelectionChanged: (val) {
                      setState(() => _formato = val.first);
                    },
                    style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  ),
                  // Copias
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Copias: ', style: TextStyle(fontSize: 11)),
                      DropdownButton<int>(
                        value: _preset.copias,
                        isDense: true,
                        underline: const SizedBox(),
                        style: const TextStyle(fontSize: 12),
                        items: [1, 2, 3, 4, 5]
                            .map((c) => DropdownMenuItem(value: c, child: Text('$c')))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _preset = _preset.copyWith(copias: val));
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ─── Área gráfica de simulación de hoja y boletos ───
            Expanded(
              child: SingleChildScrollView(
                child: Center(
                  child: Container(
                    width: anchoPreview,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                      border: Border.all(color: Colors.grey.shade400),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int i = 0; i < (isTermico ? 1 : _preset.boletosPorHoja); i++) ...[
                          if (i > 0) ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Icon(Icons.content_cut, size: 12, color: Colors.grey),
                                Expanded(
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 4),
                                    height: 1,
                                    color: Colors.grey.shade400,
                                  ),
                                ),
                                Text('Corte $i', style: const TextStyle(fontSize: 9, color: Colors.grey)),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],
                          _buildSingleTicketBlock(w, isTermico, _formato),
                        ],
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            'Preset: ${_preset.tamanoPapel} | ${_preset.orientacion.toUpperCase()} | ${_preset.boletosPorHoja} por hoja | ${_preset.copias} copias',
                            style: const TextStyle(fontSize: 9, color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          icon: _imprimiendo
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.print, size: 16),
          label: Text(_imprimiendo ? 'Imprimiendo...' : 'Confirmar e Imprimir (${_preset.copias})'),
          style: FilledButton.styleFrom(backgroundColor: SwsColors.success),
          onPressed: _imprimiendo ? null : _imprimir,
        ),
      ],
    );
  }

  Widget _buildSingleTicketBlock(Weighing w, bool isTermico, String formato) {
    final numBoleto = w.numeroBoleto ?? w.boleto;
    if (isTermico) return _buildTicketTermico(w, numBoleto, formato);

    final double rawNeto = w.pesoNeto ?? 0.0;
    final String justificacion =
        rawNeto < 0 ? ' (DESPACHO)' : (rawNeto > 0 ? ' (INGRESO)' : '');

    final double peCam = w.pesoEntradaVehiculo;
    final double peRem = w.pesoEntradaRemolque ?? 0.0;
    final double? psCam = w.pesoSalidaVehiculo;
    final double? psRem = w.pesoSalidaRemolque;
    final bool haySalida = w.fechaHoraSalida != null && psCam != null;
    final double netoCam = peCam - (psCam ?? 0.0);
    final double netoRem = peRem - (psRem ?? 0.0);

    final bool tieneDatAdic = (w.documento?.isNotEmpty ?? false) ||
        (w.unidades ?? w.litros) != null ||
        w.densidad != null;

    return DefaultTextStyle(
      style: TextStyle(
        fontFamily: formato == 'TXT' ? 'monospace' : 'Roboto',
        color: Colors.black,
        fontSize: widget.initialPreset?.boletosPorHoja == 3 ? 10.5 : 11.5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Encabezado
          if (_preset.mostrarEncabezado) ...[
            const Center(
              child: Text(
                'VARIEDADES S&S',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            const Center(child: Text('RIF: J-31490236-2', style: TextStyle(fontSize: 9.5))),
            const Divider(color: Colors.black, thickness: 1, height: 8),
          ],
          const Center(
            child: Text(
              'BOLETO DE PESAJE DE BALANSOFT',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const Divider(color: Colors.black45, height: 6),

          // ── DATOS ──
          _filaPreview('Serie - Boleto:', numBoleto, bold: true),
          _filaPreview('Fecha/Hora:', _formatDate(w.createdAt)),
          _filaPreview('Camión:', w.idVehiculo ?? 'Sin Placa'),
          _filaPreview('Remolque:', w.remolque ? (w.remolquePlaca ?? w.idRemolque ?? 'Sí') : 'No'),
          _filaPreview('Transporte:', w.transporteNombre ?? w.idTransporte ?? 'N/A'),
          _filaPreview('Conductor:', w.conductorNombre ?? w.idConductor ?? 'N/A'),
          _filaPreview('Producto:', w.productoNombre ?? w.idProducto ?? 'N/A'),
          _filaPreview('Almacén:', w.almacenNombre ?? w.idAlmacen ?? 'N/A'),
          _filaPreview('Selección:',
              (w.tipoTercero?.trim().isNotEmpty ?? false) ? w.tipoTercero!.toUpperCase() : 'N/A'),
          _filaPreview('Razón Social:', w.terceroNombre ?? w.idTercero ?? 'N/A'),

          const SizedBox(height: 4),
          const Divider(color: Colors.black, thickness: 1, height: 6),
          const Center(
            child: Text('LECTURA DE PESOS',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5)),
          ),
          const Divider(color: Colors.black45, height: 6),

          // ── Tabla: Balanza | Fecha/Hora | Peso Camión | Peso Remolque | Peso Total ──
          _filaLectura('Balanza', 'Fecha/Hora', 'Peso Camion', 'Peso Remolque', 'Peso Total', bold: true),
          _filaLectura(
            'Balanza Entrada: ${w.balanzaNombre ?? ''}'.trimRight(),
            _formatDate(w.fechaHoraEntrada),
            _fmtNumero(peCam),
            _fmtNumero(peRem),
            _fmtNumero(peCam + peRem),
          ),
          if (haySalida)
            _filaLectura(
              'Balanza Salida: ${w.balanzaNombre ?? ''}'.trimRight(),
              _formatDate(w.fechaHoraSalida!),
              _fmtNumero(psCam),
              _fmtNumero(psRem),
              _fmtNumero(w.pesoTotalSalida!),
            ),
          const Divider(color: Colors.black45, height: 6),
          _filaLectura(
            'PESO NETO$justificacion:',
            '',
            _fmtNumero(netoCam),
            _fmtNumero(netoRem),
            _fmtNumero(rawNeto),
            bold: true,
          ),
          if (w.pesoNetoDeclarado != null) ...[
            _filaLectura(
              'PESO DECLARADO / DIFERENCIA:',
              '',
              '',
              _fmtNumero(w.pesoNetoDeclarado),
              _fmtConSigno(w.pesoDiferencia),
              bold: true,
            ),
            if (w.porcentajeDesviacion != null)
              _filaLectura('DESVIACIÓN:', '', '', '', '${w.porcentajeDesviacion!.toStringAsFixed(2)} %', bold: true),
          ],
          const Divider(color: Colors.black, thickness: 1, height: 6),

          // ── DATOS ADICIONALES ──
          if (tieneDatAdic) ...[
            const Center(
              child: Text('DATOS ADICIONALES',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5)),
            ),
            const Divider(color: Colors.black45, height: 6),
            if (w.documento?.isNotEmpty ?? false) _filaPreview('Documento:', w.documento!),
            if ((w.unidades ?? w.litros) != null)
              _filaPreview('Unidades:', _fmtNumero(w.unidades ?? w.litros)),
            if (w.densidad != null) _filaPreview('Densidad:', _fmtDensidad(w.densidad)),
            const Divider(color: Colors.black, thickness: 1, height: 6),
          ],

          // ── OBSERVACIONES ──
          if (_preset.mostrarDetalles && w.observaciones != null && w.observaciones!.isNotEmpty) ...[
            const Center(
              child: Text('OBSERVACIONES',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5)),
            ),
            const Divider(color: Colors.black45, height: 6),
            Text(w.observaciones!, style: const TextStyle(fontSize: 9.5, fontStyle: FontStyle.italic)),
          ],

          const SizedBox(height: 10),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _LineaFirma(label: 'Firma Operador'),
              _LineaFirma(label: 'Firma Conductor'),
            ],
          ),
        ],
      ),
    );
  }

  /// Variante compacta para papel térmico (80mm/58mm): sin columnas
  /// de camión/remolque/total porque no caben en el ancho del rollo.
  Widget _buildTicketTermico(Weighing w, String numBoleto, String formato) {
    final double rawNeto = w.pesoNeto ?? 0.0;
    final String justificacion =
        rawNeto < 0 ? ' (DESPACHO)' : (rawNeto > 0 ? ' (INGRESO)' : '');
    final String pesoNetoFormateado = '${NumberUtils.formatKg(rawNeto.abs())}$justificacion';

    return DefaultTextStyle(
      style: TextStyle(
        fontFamily: formato == 'TXT' ? 'monospace' : 'Roboto',
        color: Colors.black,
        fontSize: 10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_preset.mostrarEncabezado) ...[
            const Center(
              child: Text(
                'VARIEDADES S&S',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            const Center(child: Text('RIF: J-31490236-2', style: TextStyle(fontSize: 9))),
            const Divider(color: Colors.black, thickness: 1, height: 6),
          ],
          const Center(
            child: Text(
              'BOLETO DE PESAJE DE BALANSOFT',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5, letterSpacing: 0.5),
            ),
          ),
          const Divider(color: Colors.black45, height: 6),
          _filaPreview('Serie - Boleto:', numBoleto, bold: true),
          _filaPreview('Fecha/Hora:', _formatDate(w.createdAt)),
          _filaPreview('Camión:', w.idVehiculo ?? 'Sin Placa'),
          _filaPreview('Remolque:', w.remolque ? (w.remolquePlaca ?? w.idRemolque ?? 'Sí') : 'No'),
          _filaPreview('Transporte:', w.transporteNombre ?? w.idTransporte ?? 'N/A'),
          _filaPreview('Conductor:', w.conductorNombre ?? w.idConductor ?? 'N/A'),
          _filaPreview('Producto:', w.productoNombre ?? w.idProducto ?? 'N/A'),
          _filaPreview('Almacén:', w.almacenNombre ?? w.idAlmacen ?? 'N/A'),
          _filaPreview('Cliente/Proveedor:', w.terceroNombre ?? w.idTercero ?? 'N/A'),
          const SizedBox(height: 4),
          const Divider(color: Colors.black, thickness: 1, height: 4),
          const Center(
            child: Text('LECTURA DE PESOS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9.5)),
          ),
          const Divider(color: Colors.black45, height: 4),
          _filaPreview('Entrada:', '${_formatDate(w.fechaHoraEntrada)}   ${NumberUtils.formatKg(w.pesoTotalEntrada)}'),
          if (w.fechaHoraSalida != null)
            _filaPreview('Salida:', '${_formatDate(w.fechaHoraSalida)}   ${NumberUtils.formatKg(w.pesoTotalSalida ?? 0)}'),
          const Divider(color: Colors.black45, height: 4),
          _filaPreview('PESO NETO:', pesoNetoFormateado, bold: true),
          const Divider(color: Colors.black, thickness: 1, height: 4),
          if (_preset.mostrarDetalles && w.observaciones != null && w.observaciones!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('Obs: ${w.observaciones}', style: const TextStyle(fontSize: 9, fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _LineaFirma(label: 'Firma Operador'),
              _LineaFirma(label: 'Firma Conductor'),
            ],
          ),
        ],
      ),
    );
  }

  String _fmtNumero(double? v) => NumberUtils.formatWeight(v);

  String _fmtConSigno(double? v) {
    if (v == null) return '';
    final num = _fmtNumero(v.abs());
    if (v > 0) return '+$num';
    if (v < 0) return '-$num';
    return num;
  }

  String _fmtDensidad(double? v) {
    if (v == null) return '';
    final s = v.toStringAsFixed(8)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
    return s.replaceAll('.', ',');
  }

  /// Una fila de la tabla de lecturas (Balanza | Fecha/Hora | Camión | Remolque | Total).
  Widget _filaLectura(
    String label,
    String fecha,
    String camion,
    String remolque,
    String total, {
    bool bold = false,
  }) {
    final s = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontSize: 9.5,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 34, child: Text(label, style: s)),
          const SizedBox(width: 4),
          Expanded(flex: 22, child: Text(fecha, textAlign: TextAlign.right, style: s)),
          const SizedBox(width: 4),
          Expanded(flex: 14, child: Text(camion, textAlign: TextAlign.right, style: s)),
          const SizedBox(width: 4),
          Expanded(flex: 14, child: Text(remolque, textAlign: TextAlign.right, style: s)),
          const SizedBox(width: 4),
          Expanded(flex: 14, child: Text(total, textAlign: TextAlign.right, style: s)),
        ],
      ),
    );
  }

  Widget _filaPreview(String label, String valor, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: 10.5)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              valor,
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: 10.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _LineaFirma extends StatelessWidget {
  final String label;
  const _LineaFirma({required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(width: 100, height: 1, color: Colors.black54),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 8.5, color: Colors.black87)),
      ],
    );
  }
}
