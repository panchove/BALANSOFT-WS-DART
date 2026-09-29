import 'package:flutter/material.dart';
import '../../core/i18n/translations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/number_utils.dart';
import '../../core/utils/save_file_utils.dart';
import '../../data/datasources/local/local_storage.dart';
import '../../data/datasources/remote/api_client.dart';
import '../../data/repositories/weighing_repository.dart';
import '../../domain/entities/printer_preset.dart';
import '../../domain/entities/weighing.dart';
import '../../injection.dart' as di;

/// Modal para previsualizar el comprobante/boleto con distribución de cantidad por hoja antes de confirmar la impresión.
class TicketPreviewDialog extends StatefulWidget {
  final Weighing weighing;
  final PrinterPreset? initialPreset;
  final void Function(String formato, PrinterPreset preset)? onConfirmPrint;
  // Perfil de la empresa para el encabezado. Si no se inyecta, se descarga del
  // backend (di.sl<ApiClient>().getEmpresaPerfil()); si se inyecta se usa tal
  // cual (los tests y los call sites pueden pasarlo sin tocar el GetIt).
  final Future<Map<String, dynamic>>? empresaPerfilFuture;

  const TicketPreviewDialog({
    super.key,
    required this.weighing,
    this.initialPreset,
    this.onConfirmPrint,
    this.empresaPerfilFuture,
  });

  @override
  State<TicketPreviewDialog> createState() => _TicketPreviewDialogState();
}

class _TicketPreviewDialogState extends State<TicketPreviewDialog> {
  late PrinterPreset _preset;
  bool _loadingPreset = true;
  bool _imprimiendo = false;
  late String _formato;
  // Perfil de la estación: nombre, RIF, teléfono, dirección y logo. El PDF/TXT
  // los imprime el backend con estos mismos datos, así que el preview y la
  // impresión salen idénticos.
  Map<String, dynamic> _empresa = const {};
  // URL absoluta del logo ya resuelta (evita tocar el GetIt durante el build).
  String? _empresaLogoAbsoluta;

  @override
  void initState() {
    super.initState();
    _cargarEmpresa();
    if (widget.initialPreset != null) {
      _preset = widget.initialPreset!;
      _formato = _preset.formatoPredeterminado;
      _loadingPreset = false;
    } else {
      _cargarPreset();
    }
  }

  Future<void> _cargarEmpresa() async {
    try {
      final perfil = widget.empresaPerfilFuture != null
          ? await widget.empresaPerfilFuture!
          : await di.sl<ApiClient>().getEmpresaPerfil();
      String? logo;
      try {
        final url = (perfil['logo_url'] ?? '').toString().trim();
        logo = url.isEmpty ? null : di.sl<ApiClient>().mediaUrl(url);
      } catch (_) {
        logo = null;
      }
      if (mounted) {
        setState(() {
          _empresa = perfil;
          _empresaLogoAbsoluta = logo;
        });
      }
    } catch (_) {
      // Sin perfil no hay encabezado de empresa, pero el boleto se sigue viendo.
    }
  }

  String get _empresaNombre {
    final nombre = (_empresa['nombre_comercial'] ?? _empresa['nombre_fiscal'] ?? '')
        .toString()
        .trim();
    return nombre.isEmpty ? 'demo_company'.tr() : nombre;
  }

  String get _empresaRif => (_empresa['rif_nit'] ?? '').toString().trim();

  String get _empresaTelefono => (_empresa['telefono'] ?? '').toString().trim();

  String get _empresaDireccion =>
      (_empresa['direccion'] ?? '').toString().trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Línea de contacto del emisor (teléfono + dirección), como en el PDF.
  String? get _lineaContactoEmpresa {
    final partes = <String>[];
    if (_empresaTelefono.isNotEmpty) {
      partes.add('${'ticket_company_phone'.tr()} $_empresaTelefono');
    }
    if (_empresaDireccion.isNotEmpty) {
      partes.add('${'ticket_company_address'.tr()} $_empresaDireccion');
    }
    return partes.isEmpty ? null : partes.join('  ·  ');
  }

  /// Encabezado del emisor en layout horizontal, espejo del backend
  /// (`_build_boleto_simple`): LOGO a la izquierda | nombre+RIF arriba y
  /// contacto debajo. SIN línea divisoria vertical entre ambas columnas.
  /// [conLogo] es false en el ticket térmico, donde el logo no cabe.
  Widget _encabezadoEmpresa({required bool conLogo, required double escala}) {
    final contacto = _lineaContactoEmpresa;
    final rifTxt = _empresaRif.isNotEmpty ? 'RIF: $_empresaRif' : '';
    final linea1 = [_empresaNombre, rifTxt]
        .where((s) => s.isNotEmpty)
        .join(' - ');

    // Bloque de texto derecho (nombre + RIF / dirección + contacto).
    final bloqueDerecho = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          linea1,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12 * escala,
            color: Colors.black,
          ),
        ),
        if (contacto != null) ...[
          const SizedBox(height: 2),
          Text(
            contacto,
            style: TextStyle(fontSize: 9 * escala, color: Colors.black54),
          ),
        ],
      ],
    );

    // Layout horizontal: logo (22%) + espacio + datos (78%). SIN Container gris.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 22,
          child: conLogo && _empresaLogoAbsoluta != null
              ? Center(
                  child: Image.network(
                    _empresaLogoAbsoluta!,
                    height: 38 * escala,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    loadingBuilder: (context, child, progress) => progress ==
                            null
                        ? child
                        : const SizedBox(height: 38, width: 38),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(width: 10), // solo espacio, sin línea divisoria
        Expanded(flex: 78, child: bloqueDerecho),
      ],
    );
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
          ? await repo.getTicketTxt(widget.weighing.boleto, tipoTicket: _preset.tipoTicket)
          : await repo.getTicketPdf(
              widget.weighing.boleto,
              boletosPorHoja: _preset.boletosPorHoja,
              tamanoPapel: _preset.tamanoPapel,
              orientacion: _preset.orientacion,
              mostrarEncabezado: _preset.mostrarEncabezado,
              mostrarDetalles: _preset.mostrarDetalles,
              tipoTicket: _preset.tipoTicket,
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
            content: Text('${'ticket_print_error'.tr()}$e'),
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
                    items: [
                      DropdownMenuItem(value: '80mm', child: Text('paper_thermal_80'.tr())),
                      DropdownMenuItem(value: '58mm', child: Text('paper_thermal_58'.tr())),
                      const DropdownMenuItem(value: 'HalfLetter', child: Text('Media Carta')),
                      const DropdownMenuItem(value: 'Letter', child: Text('Carta')),
                      const DropdownMenuItem(value: 'A4', child: Text('A4')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _preset = _preset.copyWith(tamanoPapel: val));
                    },
                  ),
                  // Cantidad por Hoja
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('ticket_per_sheet'.tr(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                      DropdownButton<int>(
                        value: _preset.boletosPorHoja,
                        isDense: true,
                        underline: const SizedBox(),
                        style: const TextStyle(fontSize: 12),
                        items:[
                          DropdownMenuItem(value: 1, child: Text('sheet_1_short'.tr())),
                          DropdownMenuItem(value: 2, child: Text('sheet_2_short'.tr())),
                          DropdownMenuItem(value: 3, child: Text('sheet_3_short'.tr())),
                          DropdownMenuItem(value: 4, child: Text('sheet_4_short'.tr())),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _preset = _preset.copyWith(boletosPorHoja: val));
                        },
                      ),
                    ],
                  ),
                  // Orientación
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(value: 'portrait', icon: const Icon(Icons.crop_portrait, size: 14), label: Text('vertical'.tr(), style: const TextStyle(fontSize: 11))),
                      ButtonSegment(value: 'landscape', icon: const Icon(Icons.crop_landscape, size: 14), label: Text('horizontal'.tr(), style: const TextStyle(fontSize: 11))),
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
                  // Tipo de Ticket
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'simple', label: Text('Simple', style: TextStyle(fontSize: 11))),
                      ButtonSegment(value: 'avanzado', label: Text('Avanzado', style: TextStyle(fontSize: 11))),
                    ],
                    selected: {_preset.tipoTicket},
                    onSelectionChanged: (val) {
                      setState(() => _preset = _preset.copyWith(tipoTicket: val.first));
                    },
                    style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  ),
                  // Copias
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('ticket_copies'.tr(), style: const TextStyle(fontSize: 11)),
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
                                Text('ticket_cut_i'.tr(null, ['$i']),
                                    style: const TextStyle(fontSize: 9, color: Colors.grey)),
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
          child: Text('btn_cancel'.tr()),
        ),
        FilledButton.icon(
          icon: _imprimiendo
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.print, size: 16),
          label: Text(
            _imprimiendo
                ? 'ticket_printing'.tr()
                : 'ticket_confirm_print'.tr(null, ['${_preset.copias}']),
          ),
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
        w.densidad != null ||
        (_preset.tipoTicket == 'avanzado' && ((w.guiaSunagro?.isNotEmpty ?? false) || (w.medida?.isNotEmpty ?? false)));

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
          // Encabezado de la empresa (logo + nombre + RIF + contacto)
          if (_preset.mostrarEncabezado) ...[
            _encabezadoEmpresa(
              conLogo: true,
              escala: widget.initialPreset?.boletosPorHoja == 3 ? 0.9 : 1.0,
            ),
            const Divider(color: Colors.black, thickness: 1, height: 8),
          ],
          Center(
            child: Text(
              'ticket_title'.tr(),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const Divider(color: Colors.black45, height: 6),

          // ── DATOS ──
          _filaPreview('ticket_ticket_number'.tr(), numBoleto, bold: true),
          _filaPreview('ticket_datetime'.tr(), _formatDate(w.createdAt)),
          _filaPreview('ticket_truck'.tr(), w.idVehiculo ?? 'ticket_no_plate'.tr()),
          _filaPreview(
              'ticket_trailer'.tr(),
              w.remolque
                  ? (w.remolquePlaca ?? 'yes'.tr())
                  : 'no'.tr()),
          _filaPreview('ticket_transport'.tr(), w.transporteNombre ?? 'N/A'),
          _filaPreview('ticket_driver'.tr(), w.conductorNombre ?? w.idConductor ?? 'N/A'),
          _filaPreview('ticket_product'.tr(), w.productoNombre ?? 'N/A'),
          _filaPreview('ticket_warehouse'.tr(), w.almacenNombre ?? 'N/A'),
          _filaPreview('ticket_selection'.tr(),
              (w.tipoTercero?.trim().isNotEmpty ?? false) ? w.tipoTercero!.toUpperCase() : 'N/A'),
          _filaPreview('ticket_company_name'.tr(), w.terceroNombre ?? 'N/A'),

          const SizedBox(height: 4),
          const Divider(color: Colors.black, thickness: 1, height: 6),
          Center(
            child: Text('ticket_weight_reading'.tr(),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5)),
          ),
          const Divider(color: Colors.black45, height: 6),

          // ── Tabla: Balanza | Fecha/Hora | Peso Camión | Peso Remolque | Peso Total ──
          _filaLectura(
              'ticket_scale'.tr(),
              'ticket_datetime'.tr(),
              'ticket_truck_weight'.tr(),
              'ticket_trailer_weight'.tr(),
              'ticket_total_weight'.tr(),
              bold: true),
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
            Center(
              child: Text('ticket_additional_data'.tr(),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5)),
            ),
            const Divider(color: Colors.black45, height: 6),
            if (w.documento?.isNotEmpty ?? false) _filaPreview('Documento:', w.documento!),
            if (_preset.tipoTicket == 'avanzado' && (w.guiaSunagro?.isNotEmpty ?? false))
              _filaPreview('Guía SUNAGRO:', w.guiaSunagro!),
            if (_preset.tipoTicket == 'avanzado' && (w.medida?.isNotEmpty ?? false))
              _filaPreview('Medida:', w.medida!),
            if ((w.unidades ?? w.litros) != null)
              _filaPreview('Unidades:', _fmtNumero(w.unidades ?? w.litros)),
            if (w.densidad != null) _filaPreview('Densidad:', _fmtDensidad(w.densidad)),
            if (_preset.tipoTicket == 'avanzado' && (w.unidades ?? w.litros) != null && w.densidad != null)
              _filaPreview('Resultado:', _fmtNumero((w.unidades ?? w.litros)! * w.densidad!)),
            const Divider(color: Colors.black, thickness: 1, height: 6),
          ],

          // ── OBSERVACIONES ──
          if (_preset.mostrarDetalles && w.observaciones != null && w.observaciones!.isNotEmpty) ...[
            Center(
              child: Text('ticket_observations'.tr(),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5)),
            ),
            const Divider(color: Colors.black45, height: 6),
            Text(w.observaciones!, style: const TextStyle(fontSize: 9.5, fontStyle: FontStyle.italic)),
          ],

          if (_preset.tipoTicket == 'avanzado') ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _LineaFirma(label: 'ticket_sign_operator'.tr()),
                _LineaFirma(label: 'ticket_sign_driver'.tr()),
              ],
            ),
          ],
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
            // En el rollo térmico no cabe el logo: solo los datos del emisor.
            _encabezadoEmpresa(conLogo: false, escala: 1.0),
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
          _filaPreview('Remolque:', w.remolque ? (w.remolquePlaca ?? 'Sí') : 'No'),
          _filaPreview('Transporte:', w.transporteNombre ?? 'N/A'),
          _filaPreview('ticket_driver'.tr(), w.conductorNombre ?? w.idConductor ?? 'N/A'),
          _filaPreview('ticket_product'.tr(), w.productoNombre ?? 'N/A'),
          _filaPreview('ticket_warehouse'.tr(), w.almacenNombre ?? 'N/A'),
          _filaPreview('ticket_customer_supplier'.tr(),
              w.terceroNombre ?? 'N/A'),
          const SizedBox(height: 4),
          const Divider(color: Colors.black, thickness: 1, height: 4),
          Center(
            child: Text('ticket_weight_reading'.tr(),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 9.5)),
          ),
          const Divider(color: Colors.black45, height: 4),
          _filaPreview('ticket_entry'.tr(),
              '${_formatDate(w.fechaHoraEntrada)}   ${NumberUtils.formatKg(w.pesoTotalEntrada)}'),
          if (w.fechaHoraSalida != null)
            _filaPreview('ticket_exit'.tr(),
                '${_formatDate(w.fechaHoraSalida)}   ${NumberUtils.formatKg(w.pesoTotalSalida ?? 0)}'),
          const Divider(color: Colors.black45, height: 4),
          _filaPreview('ticket_net_weight'.tr(), pesoNetoFormateado, bold: true),
          const Divider(color: Colors.black, thickness: 1, height: 4),
          if ((w.documento?.isNotEmpty ?? false) || (w.unidades ?? w.litros) != null || w.densidad != null || (_preset.tipoTicket == 'avanzado' && ((w.guiaSunagro?.isNotEmpty ?? false) || (w.medida?.isNotEmpty ?? false)))) ...[
            Center(
              child: Text('ticket_additional_data'.tr(),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 9.5)),
            ),
            const Divider(color: Colors.black45, height: 4),
            if (w.documento?.isNotEmpty ?? false) _filaPreview('Documento:', w.documento!),
            if (_preset.tipoTicket == 'avanzado' && (w.guiaSunagro?.isNotEmpty ?? false))
              _filaPreview('Guía SUNAGRO:', w.guiaSunagro!),
            if (_preset.tipoTicket == 'avanzado' && (w.medida?.isNotEmpty ?? false))
              _filaPreview('Medida:', w.medida!),
            if ((w.unidades ?? w.litros) != null)
              _filaPreview('Unidades:', _fmtNumero(w.unidades ?? w.litros)),
            if (w.densidad != null) _filaPreview('Densidad:', _fmtDensidad(w.densidad)),
            if (_preset.tipoTicket == 'avanzado' && (w.unidades ?? w.litros) != null && w.densidad != null)
              _filaPreview('Resultado:', _fmtNumero((w.unidades ?? w.litros)! * w.densidad!)),
            const Divider(color: Colors.black, thickness: 1, height: 4),
          ],
          if (_preset.mostrarDetalles && w.observaciones != null && w.observaciones!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('ticket_obs'.tr(null, ['${w.observaciones}']),
                style: const TextStyle(fontSize: 9, fontStyle: FontStyle.italic)),
          ],
          if (_preset.tipoTicket == 'avanzado') ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _LineaFirma(label: 'ticket_sign_operator'.tr()),
                _LineaFirma(label: 'ticket_sign_driver'.tr()),
              ],
            ),
          ],
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