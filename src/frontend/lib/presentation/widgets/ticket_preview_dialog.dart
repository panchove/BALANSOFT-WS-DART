// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 17025 / OIML R 76-1 / ISO/IEC 25010
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Modal para previsualizar el comprobante/boleto y elegir la cantidad de tickets («copias») antes de confirmar la impresión.
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
              copias: _preset.copias,
              tamanoPapel: _preset.tamanoPapel,
              orientacion: _preset.orientacion,
              mostrarEncabezado: _preset.mostrarEncabezado,
              mostrarDetalles: _preset.mostrarDetalles,
              mostrarQr: _preset.mostrarQr,
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
              AppTranslations.tr(
                'ticket_guardado_en',
                args: [_formato, ruta, '${_preset.copias}'],
              ),
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
      return _conAtajoEnter(const AlertDialog(
        content: SizedBox(
          height: 100,
          child: Center(child: CircularProgressIndicator()),
        ),
      ));
    }

    final isTermico = _preset.tamanoPapel == '80mm' || _preset.tamanoPapel == '58mm';
    final isLandscape = _preset.orientacion == 'landscape';

    // Espejo de _build_pdf (backend): en papel normal el boleto SIEMPRE es
    // estrecho y centrado (140mm de ~196mm útiles). En térmico el ancho es el
    // del rollo. El «copias» solo multiplica los tickets, no el ancho.
    final anchoBase = isLandscape ? 720.0 : 520.0;
    final anchoPreview = isTermico ? 340.0 : anchoBase * (140 / 195.9);

    return _conAtajoEnter(AlertDialog(
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
                  // Cantidad de tickets a imprimir
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('tickets_to_print'.tr(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
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
                        // Un único ticket: «Cantidad de tickets» es cuántas
                        // copias completas se imprimen, no un apilado en hoja.
                        _buildSingleTicketBlock(w, isTermico, _formato),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            'Preset: ${_preset.tamanoPapel} | ${_preset.orientacion.toUpperCase()} | ${_preset.copias} ticket(s)',
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
    ));
  }

  /// Enter (o Enter del teclado numérico) confirma la impresión igual que el
  /// botón «Imprimir». La estación es teclado-céntrica: el operador teclea y
  /// pulsa Enter sin tocar el ratón.
  Widget _conAtajoEnter(Widget child) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _onEnter,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _onEnter,
      },
      child: Focus(autofocus: true, child: child),
    );
  }

  void _onEnter() {
    if (_loadingPreset || _imprimiendo) return;
    _imprimir();
  }

  Widget _buildSingleTicketBlock(Weighing w, bool isTermico, String formato) {
    final numBoleto = w.numeroBoleto ?? w.boleto;
    if (isTermico) return _buildTicketTermico(w, numBoleto, formato);

    final bool tieneDatAdic = (w.documento?.isNotEmpty ?? false) ||
        (w.unidades ?? w.litros) != null ||
        w.densidad != null ||
        (_preset.tipoTicket == 'avanzado' && ((w.guiaSunagro?.isNotEmpty ?? false) || (w.medida?.isNotEmpty ?? false)));

    return DefaultTextStyle(
      style: TextStyle(
        fontFamily: formato == 'TXT' ? 'monospace' : 'Roboto',
        color: Colors.black,
        fontSize: 11.5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Encabezado de la empresa (logo + nombre + RIF + contacto)
          if (_preset.mostrarEncabezado) ...[
            _encabezadoEmpresa(
              conLogo: true,
              escala: 1.0,
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

          // ── Tabla de lecturas de peso (la MISMA rejilla que el PDF y el TXT) ──
          ..._bloquePesos(w, conControl: true),
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

  /// Variante compacta para papel térmico (80mm/58mm): los campos van apilados
  /// "Etiqueta: valor", pero la LECTURA DE PESOS sale con la MISMA rejilla que
  /// la hoja —``_bloquePesos``—, igual que el PDF térmico.
  Widget _buildTicketTermico(Weighing w, String numBoleto, String formato) {
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
          _filaTermico('Serie - Boleto:', numBoleto, bold: true),
          _filaTermico('Fecha/Hora:', _formatDate(w.createdAt)),
          _filaTermico('Camión:', w.idVehiculo ?? 'Sin Placa'),
          _filaTermico('Remolque:', w.remolque ? (w.remolquePlaca ?? 'Sí') : 'No'),
          _filaTermico('Transporte:', w.transporteNombre ?? 'N/A'),
          _filaTermico('ticket_driver'.tr(), w.conductorNombre ?? w.idConductor ?? 'N/A'),
          _filaTermico('ticket_product'.tr(), w.productoNombre ?? 'N/A'),
          _filaTermico('ticket_warehouse'.tr(), w.almacenNombre ?? 'N/A'),
          _filaTermico('ticket_customer_supplier'.tr(),
              w.terceroNombre ?? 'N/A'),
          const SizedBox(height: 4),
          const Divider(color: Colors.black, thickness: 1, height: 4),
          Center(
            child: Text('ticket_weight_reading'.tr(),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 9.5)),
          ),
          const Divider(color: Colors.black45, height: 4),
          const Divider(color: Colors.black45, height: 4),
          // Tabla de lecturas (espejo del PDF térmico): la MISMA rejilla que la
          // hoja —(etiqueta) | Fec, Hrs | CAMIÓN | REMOLQUE | TOTAL—, con una
          // fila por pesada, la de TOTALES (netos por vehículo) y el PESO NETO.
          ..._bloquePesos(w, conControl: false, separador: 4),
          const Divider(color: Colors.black, thickness: 1, height: 4),
          if ((w.documento?.isNotEmpty ?? false) || (w.unidades ?? w.litros) != null || w.densidad != null || (_preset.tipoTicket == 'avanzado' && ((w.guiaSunagro?.isNotEmpty ?? false) || (w.medida?.isNotEmpty ?? false)))) ...[
            Center(
              child: Text('ticket_additional_data'.tr(),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 9.5)),
            ),
            const Divider(color: Colors.black45, height: 4),
            if (w.documento?.isNotEmpty ?? false) _filaTermico('Documento:', w.documento!),
            if (_preset.tipoTicket == 'avanzado' && (w.guiaSunagro?.isNotEmpty ?? false))
              _filaTermico('Guía SUNAGRO:', w.guiaSunagro!),
            if (_preset.tipoTicket == 'avanzado' && (w.medida?.isNotEmpty ?? false))
              _filaTermico('Medida:', w.medida!),
            if ((w.unidades ?? w.litros) != null)
              _filaTermico('Unidades:', _fmtNumero(w.unidades ?? w.litros)),
            if (w.densidad != null) _filaTermico('Densidad:', _fmtDensidad(w.densidad)),
            if (_preset.tipoTicket == 'avanzado' && (w.unidades ?? w.litros) != null && w.densidad != null)
              _filaTermico('Resultado:', _fmtNumero((w.unidades ?? w.litros)! * w.densidad!)),
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

  /// La tabla LECTURA DE PESOS del preview, con la MISMA rejilla que el PDF y el
  /// TXT (espejo de ``_filas_lectura_pesos`` en el backend)::
  ///
  ///     (vacío)     Fec, Hrs            CAMIÓN       REMOLQUE     TOTAL
  ///     ENTRADA:    08/09/2026 – 08:30  50.000,00 kg 12.500,00 kg 62.500,00 kg
  ///     SALIDA:     …                   (solo si el boleto ya tiene salida)
  ///     (vacío)     TOTALES:            (los NETOS por vehículo)
  ///     PESO NETO:  7.500,00 kg         (INGRESO / DESPACHO)
  ///
  /// ``conControl`` añade las dos filas de la HOJA (declarado / desviación), que
  /// el rollo no lleva.
  List<Widget> _bloquePesos(
    Weighing w, {
    required bool conControl,
    double separador = 6,
  }) {
    final double peCam = w.pesoEntradaVehiculo;
    final double peRem = w.pesoEntradaRemolque ?? 0.0;
    final double? psCam = w.pesoSalidaVehiculo;
    final double? psRem = w.pesoSalidaRemolque;
    final double neto = w.pesoNeto ?? 0.0;

    return [
      _filaPesos([
        '',
        'ticket_col_datetime'.tr(),
        'ticket_col_camion'.tr(),
        'ticket_col_remolque'.tr(),
        'ticket_col_total'.tr(),
      ], cabecera: true),
      _filaPesos([
        '${'ticket_col_entry'.tr()}:',
        _fechaTabla(w.fechaHoraEntrada),
        NumberUtils.formatKg(peCam),
        NumberUtils.formatKg(peRem),
        NumberUtils.formatKg(peCam + peRem),
      ]),
      if (w.fechaHoraSalida != null)
        _filaPesos([
          '${'ticket_col_exit'.tr()}:',
          _fechaTabla(w.fechaHoraSalida),
          _kg(psCam),
          _kg(psRem),
          NumberUtils.formatKg((psCam ?? 0) + (psRem ?? 0)),
        ]),
      _filaPesos([
        '',
        '${'ticket_col_totales'.tr()}:',
        NumberUtils.formatKg(peCam - (psCam ?? 0)),
        NumberUtils.formatKg(peRem - (psRem ?? 0)),
        NumberUtils.formatKg(neto),
      ]),
      Divider(color: Colors.black45, height: separador),
      _filaPesos([
        'ticket_net_weight'.tr(),
        NumberUtils.formatKg(neto.abs()),
        neto < 0 ? '(DESPACHO)' : (neto > 0 ? '(INGRESO)' : ''),
        '',
        '',
      ], bold: true),
      if (conControl && w.pesoNetoDeclarado != null) ...[
        _filaPesos([
          'PESO DECLARADO / DIFERENCIA:',
          '',
          '',
          _fmtNumero(w.pesoNetoDeclarado),
          _fmtConSigno(w.pesoDiferencia),
        ], bold: true),
        if (w.porcentajeDesviacion != null)
          _filaPesos([
            'DESVIACIÓN:',
            '',
            '',
            '',
            '${w.porcentajeDesviacion!.toStringAsFixed(2)} %',
          ], bold: true),
      ],
    ];
  }

  /// Celda de peso: los kilos, o vacío si no hay dato (como el backend).
  String _kg(double? valor) => valor == null ? '' : NumberUtils.formatKg(valor);

  /// Fecha y hora de la columna ``Fec, Hrs`` de la tabla: ``dd/mm/aaaa – HH:MM``
  /// (guion medio, igual que el backend). El bloque de DATOS sigue con
  /// ``_formatDate`` (espacio).
  String _fechaTabla(DateTime? fecha) {
    if (fecha == null) return '—';
    final String dia = fecha.day.toString().padLeft(2, '0');
    final String mes = fecha.month.toString().padLeft(2, '0');
    final String hora = fecha.hour.toString().padLeft(2, '0');
    final String minuto = fecha.minute.toString().padLeft(2, '0');
    return '$dia/$mes/${fecha.year} – $hora:$minuto';
  }

  /// Una fila de la tabla de lecturas: 5 columnas con el reparto de anchos del
  /// PDF (``_REQUIERE_TABLA_PESOS``: camión, remolque y total son las columnas
  /// de kilos). La etiqueta va a la izquierda, los valores a la derecha y la
  /// cabecera centrada, como en el PDF.
  Widget _filaPesos(
    List<String> celdas, {
    bool bold = false,
    bool cabecera = false,
  }) {
    const List<int> anchos = [75, 58, 74, 63, 57];
    final TextStyle estilo = TextStyle(
      fontWeight: (bold || cabecera) ? FontWeight.bold : FontWeight.normal,
      fontSize: 9.5,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < anchos.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              flex: anchos[i],
              child: Text(
                i < celdas.length ? celdas[i] : '',
                textAlign: cabecera
                    ? TextAlign.center
                    : (i == 0 ? TextAlign.left : TextAlign.right),
                style: estilo,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Fila "Etiqueta | valor" del bloque de DATOS, en DOS columnas con
  /// alineación PROPIA: la etiqueta pegada a la DERECHA de su columna y el
  /// valor a la IZQUIERDA de la siguiente (espejo de la tabla de 2 celdas del
  /// PDF). La usan los DOS formatos —la hoja (media carta/carta/A4) y el rollo
  /// térmico (80/58 mm)— porque el PDF imprime esa parte igual en todos; solo
  /// cambian el tamaño de la letra y el aire de cada fila.
  ///
  /// El reparto 47/53 sale del propio PDF: a 80 mm, la etiqueta más larga que
  /// puede ver el preview (`Cliente/Proveedor:`) ocupa el 46,7 % del ancho útil
  /// (`_ancho_etiqueta_termica`, que es lo que se le deja a su columna). El
  /// catálogo del ticket AVANZADO no se pinta aquí. Es una APROXIMACIÓN: el PDF
  /// mide la etiqueta de cada grupo con la fuente real (y el rollo de 58 mm
  /// recorta con su tope); el preview no puede reproducir esa medida.
  Widget _filaDatos(
    String label,
    String valor, {
    bool bold = false,
    double fontSize = 10.5,
    double padding = 1.2,
  }) {
    final TextStyle estilo = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontSize: fontSize,
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: padding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 47,
            child: Text(label, textAlign: TextAlign.right, style: estilo),
          ),
          const SizedBox(width: 3),
          Expanded(
            flex: 53,
            child: Text(valor, textAlign: TextAlign.left, style: estilo),
          ),
        ],
      ),
    );
  }

  /// Fila de datos de la HOJA (media carta, carta y A4).
  Widget _filaPreview(String label, String valor, {bool bold = false}) =>
      _filaDatos(label, valor, bold: bold);

  /// Fila de datos del rollo TÉRMICO (80/58 mm): letra algo menor.
  Widget _filaTermico(String label, String valor, {bool bold = false}) =>
      _filaDatos(label, valor, bold: bold, fontSize: 9.5, padding: 1.0);
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