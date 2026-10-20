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
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/i18n/translations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/datasources/local/local_storage.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../domain/entities/printer_preset.dart';
import '../../../domain/entities/weighing.dart';
import '../../../injection.dart' as di;
import '../../providers/bloc/auth/auth_bloc.dart';
import '../../widgets/ticket_preview_dialog.dart';

/// Módulo dedicado a la configuración, estilización y diseño del ticket o boleto de pesaje.
class TicketDesignScreen extends StatefulWidget {
  const TicketDesignScreen({super.key});

  @override
  State<TicketDesignScreen> createState() => _TicketDesignScreenState();
}

class _TicketDesignScreenState extends State<TicketDesignScreen> {
  PrinterPreset _preset = const PrinterPreset();
  bool _cargando = true;
  bool _guardando = false;

  // ── Configuración de la empresa (solo ADMIN) ─────────────────────────────
  // El tope de ediciones y la impresión automática pertenecen a `empresas`
  // (van al backend), no a la preferencia local de este dispositivo.
  bool _esAdmin = false;
  bool _cargandoEmpresa = false;
  bool _guardandoEmpresa = false;
  final _maxEdicionesCtrl = TextEditingController();
  bool _impresionAutomatica = false;
  String? _protocoloImpresion;
  final _impresoraNombreCtrl = TextEditingController();
  final _impresoraHostCtrl = TextEditingController();
  final _impresoraPuertoCtrl = TextEditingController();

  /// Valores del `Literal` del backend (`ck_empresas_protocolo_impresion`).
  static const List<String> _protocolos = [
    'predeterminada_so',
    'raw_9100',
    'lpd_cups',
    'nombre_impresora',
  ];

  @override
  void initState() {
    super.initState();
    _cargarPreset();
    // El `AuthBloc` no está resuelto durante `initState`, así que la lectura de
    // la empresa va después del primer frame (mismo patrón que Tipografía).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _esAdmin = _rolActual() == 'ADMIN';
        setState(() {});
        _cargarEmpresa();
      }
    });
  }

  @override
  void dispose() {
    _maxEdicionesCtrl.dispose();
    _impresoraNombreCtrl.dispose();
    _impresoraHostCtrl.dispose();
    _impresoraPuertoCtrl.dispose();
    super.dispose();
  }

  String? _rolActual() {
    final state = context.read<AuthBloc>().state;
    return state is AuthAuthenticated ? state.user.rol : null;
  }

  Future<void> _cargarPreset() async {
    try {
      final p = await di.sl<LocalStorage>().getPrinterPreset();
      if (mounted) {
        setState(() {
          _preset = p;
          _cargando = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// Lee de la empresa el tope de ediciones y la configuración de impresión.
  /// Solo ADMIN (los demás no pueden cambiarla y no se les muestra).
  Future<void> _cargarEmpresa() async {
    if (!_esAdmin) return;
    setState(() => _cargandoEmpresa = true);
    try {
      final p = await di.sl<ApiClient>().getEmpresaPerfil();
      if (!mounted) return;
      final max = p['max_ediciones_boleto'];
      final proto = p['protocolo_impresion'];
      setState(() {
        _maxEdicionesCtrl.text =
            (max is num && max > 0) ? max.toInt().toString() : '';
        _impresionAutomatica = p['impresion_automatica'] == true;
        _protocoloImpresion = (proto is String && _protocolos.contains(proto))
            ? proto
            : null;
        _impresoraNombreCtrl.text = '${p['impresora_nombre'] ?? ''}';
        _impresoraHostCtrl.text = '${p['impresora_host'] ?? ''}';
        _impresoraPuertoCtrl.text = (p['impresora_puerto'] is num)
            ? (p['impresora_puerto'] as num).toInt().toString()
            : '';
        _cargandoEmpresa = false;
      });
    } catch (e) {
      debugPrint('Diseño de ticket: no se pudo leer la empresa: $e');
      if (mounted) setState(() => _cargandoEmpresa = false);
    }
  }

  void _avisar(String mensaje, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(mensaje), backgroundColor: color),
      );
  }

  /// Guarda en `empresas` el tope de ediciones y la impresión automática
  /// (`PUT /api/v1/empresa`, solo ADMIN). Un `null` explícito limpia el campo.
  Future<void> _guardarEmpresa() async {
    if (!_esAdmin) {
      _avisar('cfg_solo_admin'.tr(), SwsColors.warning);
      return;
    }
    final maxTxt = _maxEdicionesCtrl.text.trim();
    final max = maxTxt.isEmpty ? null : int.tryParse(maxTxt);
    if (maxTxt.isNotEmpty && (max == null || max < 0)) {
      _avisar('cfg_error_guardar'.tr(), SwsColors.danger);
      return;
    }
    final puertoTxt = _impresoraPuertoCtrl.text.trim();
    final puerto = puertoTxt.isEmpty ? null : int.tryParse(puertoTxt);
    if (puertoTxt.isNotEmpty && (puerto == null || puerto < 1 || puerto > 65535)) {
      _avisar('cfg_error_guardar'.tr(), SwsColors.danger);
      return;
    }

    setState(() => _guardandoEmpresa = true);
    try {
      await di.sl<ApiClient>().updateEmpresaPerfil({
        'max_ediciones_boleto': max,
        'impresion_automatica': _impresionAutomatica,
        'protocolo_impresion': _protocoloImpresion,
        'impresora_nombre': _impresoraNombreCtrl.text.trim().isEmpty
            ? null
            : _impresoraNombreCtrl.text.trim(),
        'impresora_host': _impresoraHostCtrl.text.trim().isEmpty
            ? null
            : _impresoraHostCtrl.text.trim(),
        'impresora_puerto': puerto,
      });
      await _cargarEmpresa();
      _avisar('cfg_edicion_guardada'.tr(), SwsColors.success);
    } catch (e) {
      debugPrint('Diseño de ticket: no se pudo guardar la empresa: $e');
      _avisar('cfg_error_guardar'.tr(), SwsColors.danger);
    } finally {
      if (mounted) setState(() => _guardandoEmpresa = false);
    }
  }

  Future<void> _guardarPreset() async {
    setState(() => _guardando = true);
    try {
      await di.sl<LocalStorage>().savePrinterPreset(_preset);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ticket_design_saved'.tr()),
            backgroundColor: SwsColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar diseño: $e'),
            backgroundColor: SwsColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _probarImpresion() {
    final now = DateTime.now();
    final weighingPrueba = Weighing(
      boleto: 'DEMO-001',
      numeroBoleto: 'TA-00000001',
      idVehiculo: 'ALT369',
      remolque: false,
      idTransporte: 'TRANSPORTE BALANSOFT',
      idConductor: 'FULANO DE TAL (V-12345678)',
      idProducto: 'PRODUCTO PRUEBA 01',
      idAlmacen: 'ALMACEN 01',
      terceroNombre: 'PROVEEDOR DEMO S.A.',
      pesoEntradaVehiculo: 22914.0,
      pesoSalidaVehiculo: 7084.0,
      pesoNeto: -15830.0, // Despacho
      fechaHoraEntrada: now.subtract(const Duration(minutes: 25)),
      fechaHoraSalida: now,
      estadoBoleto: 'CERRADO',
      createdAt: now,
      updatedAt: now,
      observaciones: 'Prueba de diseño y estilización del boleto de pesaje',
    );

    showDialog<void>(
      context: context,
      builder: (ctx) => TicketPreviewDialog(
        weighing: weighingPrueba,
        initialPreset: _preset,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_cargando) {
      return Scaffold(
        appBar: AppBar(title: const Text('Diseño de Ticket')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final isTermico = _preset.tamanoPapel == '80mm' || _preset.tamanoPapel == '58mm';

    // Espejo de _build_pdf (backend): en papel normal el boleto SIEMPRE es
    // estrecho y centrado (140mm de ~196mm útiles). En térmico el ancho es el
    // del rollo. El «copias» solo multiplica los tickets, no el ancho.
    final anchoBaseHoja = _preset.orientacion == 'landscape' ? 620.0 : 480.0;
    final anchoHojaNormal = anchoBaseHoja * (140 / 195.9);

    return Scaffold(
      appBar: AppBar(
        title: Text('ticket_design_title'.tr()),
        actions: [
          IconButton(
            tooltip: 'Probar e Imprimir Boleto',
            icon: const Icon(Icons.print_outlined),
            onPressed: _probarImpresion,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ─── Tarjeta 1: Tamaño de Papel, Orientación, Cantidad de Tickets y Alto ───
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.aspect_ratio, color: SwsColors.accent),
                      const SizedBox(width: 8),
                      Text(
                        'ticket_dimensions'.tr(),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    crossAxisAlignment: WrapCrossAlignment.start,
                    children: [
                      // Tamaño de papel
                      SizedBox(
                        width: 240,
                        child: DropdownButtonFormField<String>(
                          initialValue: _preset.tamanoPapel,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Tamaño de Papel',
                            prefixIcon: Icon(Icons.insert_drive_file_outlined),
                          ),
                          items:[
                            DropdownMenuItem(value: 'Letter', child: Text('paper_letter'.tr())),
                            DropdownMenuItem(value: 'HalfLetter', child: Text('paper_half_letter'.tr())),
                            DropdownMenuItem(value: 'A4', child: Text('paper_a4'.tr())),
                            DropdownMenuItem(value: '80mm', child: Text('paper_roll_80'.tr())),
                            DropdownMenuItem(value: '58mm', child: Text('paper_roll_58'.tr())),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => _preset = _preset.copyWith(tamanoPapel: val));
                          },
                        ),
                      ),

                      // Alto del Boleto en mm
                      SizedBox(
                        width: 200,
                        child: DropdownButtonFormField<double>(
                          initialValue: _preset.altoBoletoMm,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Alto del Boleto (mm)',
                            prefixIcon: Icon(Icons.height_outlined),
                            helperText: '0.0 = Distribuido aut.',
                          ),
                          items:[
                            DropdownMenuItem(value: 0.0, child: Text('auto_distributed'.tr())),
                            const DropdownMenuItem(value: 70.0, child: Text('70 mm')),
                            DropdownMenuItem(value: 90.0, child: Text('width_90'.tr())),
                            const DropdownMenuItem(value: 100.0, child: Text('100 mm')),
                            DropdownMenuItem(value: 120.0, child: Text('width_120'.tr())),
                            const DropdownMenuItem(value: 140.0, child: Text('140 mm')),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => _preset = _preset.copyWith(altoBoletoMm: val));
                          },
                        ),
                      ),

                      // Orientación
                      SizedBox(
                        width: 260,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('ticket_orientation'.tr(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            SegmentedButton<String>(
                              segments:[
                                ButtonSegment(value: 'portrait', icon: const Icon(Icons.crop_portrait), label: Text('vertical'.tr())),
                                ButtonSegment(value: 'landscape', icon: const Icon(Icons.crop_landscape), label: Text('horizontal'.tr())),
                              ],
                              selected: {_preset.orientacion},
                              onSelectionChanged: (val) {
                                setState(() => _preset = _preset.copyWith(orientacion: val.first));
                              },
                            ),
                          ],
                        ),
                      ),

                      // Formato Predeterminado
                      SizedBox(
                        width: 220,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('default_format'.tr(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(value: 'PDF', label: Text('PDF')),
                                ButtonSegment(value: 'TXT', label: Text('TXT')),
                              ],
                              selected: {_preset.formatoPredeterminado},
                              onSelectionChanged: (val) {
                                setState(() => _preset = _preset.copyWith(formatoPredeterminado: val.first));
                              },
                            ),
                          ],
                        ),
                      ),

                      // Cantidad de tickets a imprimir
                      SizedBox(
                        width: 220,
                        child: DropdownButtonFormField<int>(
                          initialValue: _preset.copias,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'tickets_to_print'.tr(),
                            prefixIcon: const Icon(Icons.copy_outlined),
                            helperText: 'tickets_to_print_helper'.tr(),
                          ),
                          items: [1, 2, 3, 4, 5]
                              .map((c) => DropdownMenuItem(value: c, child: Text('$c')))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _preset = _preset.copyWith(copias: val));
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ─── Tarjeta 2: Estilización Visual y Contenidos ───
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.palette_outlined, color: SwsColors.accent),
                      const SizedBox(width: 8),
                      Text(
                        'visual_styling'.tr(),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: Text('header_company'.tr()),
                    subtitle: Text('header_company_desc'.tr()),
                    value: _preset.mostrarEncabezado,
                    onChanged: (val) => setState(() => _preset = _preset.copyWith(mostrarEncabezado: val)),
                  ),
                  SwitchListTile(
                    title: Text('obs_details'.tr()),
                    subtitle: Text('obs_details_desc'.tr()),
                    value: _preset.mostrarDetalles,
                    onChanged: (val) => setState(() => _preset = _preset.copyWith(mostrarDetalles: val)),
                  ),
                  SwitchListTile(
                    title: Text('show_qr'.tr()),
                    subtitle: Text('show_qr_desc'.tr()),
                    value: _preset.mostrarQr,
                    onChanged: (val) => setState(() => _preset = _preset.copyWith(mostrarQr: val)),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ticket_type'.tr(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        Text('ticket_type_desc'.tr(), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        const SizedBox(height: 8),
                        SegmentedButton<String>(
                          segments: [
                            ButtonSegment(value: 'simple', label: Text('basic_ticket'.tr())),
                            ButtonSegment(value: 'avanzado', label: Text('advanced_ticket'.tr())),
                          ],
                          selected: {_preset.tipoTicket},
                          onSelectionChanged: (val) {
                            setState(() => _preset = _preset.copyWith(tipoTicket: val.first));
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ─── Tarjeta 2b: Edición de boletos e impresión automática (ADMIN) ───
          if (_esAdmin) _buildEdicionImpresionCard(),

          // ─── Tarjeta 3: Previsualización en vivo del Boleto y Hoja ───
          Card(
            color: isDark ? SwsColors.darkCard : SwsColors.light,
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.preview_outlined, color: SwsColors.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          AppTranslations.tr(
                            'diseno_ticket_preview_titulo',
                            args: [
                              _preset.tamanoPapel,
                              _preset.orientacion.toUpperCase(),
                            ],
                          ),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Container(
                      width: _preset.tamanoPapel == '58mm'
                          ? 260
                          : (_preset.tamanoPapel == '80mm'
                              ? 320
                              : anchoHojaNormal),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.grey.shade400),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Vista de un único ticket: «Cantidad de tickets» es
                          // cuántas copias completas se imprimen, no un apilado.
                          _buildDemoTicketBlock(isTermico),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.preview),
                        label: Text('test_print_ticket'.tr()),
                        onPressed: _probarImpresion,
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        icon: _guardando
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.save),
                        label: Text(_guardando ? 'Guardando...' : 'Guardar Diseño de Ticket'),
                        style: FilledButton.styleFrom(backgroundColor: SwsColors.success),
                        onPressed: _guardando ? null : _guardarPreset,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tarjeta de configuración **de la empresa** (solo ADMIN): tope de ediciones
  /// por boleto y envío a impresora tras generar el ticket.
  ///
  /// El envío automático real aún no está implementado (no hay integración con
  /// la cola de impresión del SO); se persiste la configuración y se avisa al
  /// usuario para no prometer un comportamiento que todavía no ocurre.
  Widget _buildEdicionImpresionCard() {
    final theme = Theme.of(context);
    final hayDestinoImpresion = _protocoloImpresion == 'raw_9100' ||
        _protocoloImpresion == 'lpd_cups' ||
        _protocoloImpresion == 'nombre_impresora';

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.settings_suggest_outlined,
                    color: SwsColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'cfg_edicion_impresion'.tr(),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('ADMIN', style: TextStyle(fontSize: 11)),
                  backgroundColor: SwsColors.accent.withValues(alpha: 0.15),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_cargandoEmpresa)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else ...[
              // Tope de ediciones
              SizedBox(
                width: 320,
                child: TextField(
                  controller: _maxEdicionesCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: InputDecoration(
                    labelText: 'cfg_max_ediciones'.tr(),
                    helperText: 'cfg_max_ediciones_hint'.tr(),
                    helperMaxLines: 2,
                    prefixIcon:
                        const Icon(Icons.edit_note_outlined, size: 18),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Divider(color: theme.colorScheme.outlineVariant),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('cfg_impresion_automatica'.tr()),
                subtitle: Text(
                  'cfg_impresion_pendiente'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                value: _impresionAutomatica,
                onChanged: (v) => setState(() => _impresionAutomatica = v),
              ),
              SizedBox(
                width: 340,
                child: DropdownButtonFormField<String>(
                  initialValue: _protocoloImpresion,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'cfg_protocolo_impresion'.tr(),
                    prefixIcon: const Icon(Icons.print_outlined, size: 18),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'predeterminada_so',
                      child: Text('cfg_protocolo_so'.tr()),
                    ),
                    DropdownMenuItem(
                      value: 'raw_9100',
                      child: Text('cfg_protocolo_raw'.tr()),
                    ),
                    DropdownMenuItem(
                      value: 'lpd_cups',
                      child: Text('cfg_protocolo_lpd'.tr()),
                    ),
                    DropdownMenuItem(
                      value: 'nombre_impresora',
                      child: Text('cfg_protocolo_nombre'.tr()),
                    ),
                  ],
                  onChanged: (v) => setState(() => _protocoloImpresion = v),
                ),
              ),
              if (hayDestinoImpresion) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 260,
                      child: TextField(
                        controller: _impresoraNombreCtrl,
                        decoration: InputDecoration(
                          labelText: 'cfg_impresora_nombre'.tr(),
                          prefixIcon:
                              const Icon(Icons.local_print_shop_outlined,
                                  size: 18),
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: TextField(
                        controller: _impresoraHostCtrl,
                        decoration: InputDecoration(
                          labelText: 'cfg_impresora_host'.tr(),
                          prefixIcon: const Icon(Icons.lan_outlined, size: 18),
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 140,
                      child: TextField(
                        controller: _impresoraPuertoCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          labelText: 'cfg_impresora_puerto'.tr(),
                          prefixIcon:
                              const Icon(Icons.numbers_outlined, size: 18),
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  icon: _guardandoEmpresa
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text('save'.tr()),
                  onPressed: _guardandoEmpresa ? null : _guardarEmpresa,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDemoTicketBlock(bool isTermico) {
    const double textScale = 11.0;

    return DefaultTextStyle(
      style: TextStyle(
        fontSize: textScale,
        fontFamily: _preset.formatoPredeterminado == 'TXT' ? 'monospace' : 'Roboto',
        color: Colors.black,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_preset.mostrarEncabezado) ...[
            Center(
              child: Text(
                'demo_company'.tr(),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
              ),
            ),
            const Center(child: Text('RIF: J-31490236-2', style: TextStyle(fontSize: 9.5))),
            const Divider(color: Colors.black, thickness: 1, height: 6),
          ],
          const Center(
            child: Text(
              'BOLETO DE PESAJE DE BALANSOFT',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, letterSpacing: 0.3),
            ),
          ),
          const Divider(color: Colors.black45, height: 6),
          _filaDemo('Serie - Boleto:', 'TA-00000001', bold: true),
          _filaDemo('Fecha/Hora:', '24/09/2026 11:58'),
          _filaDemo('Camión:', 'ALT369'),
          _filaDemo('Remolque:', 'No'),
          _filaDemo('Transporte:', 'TRANSPORTE BALANSOFT'),
          _filaDemo('Conductor:', 'FULANO DE TAL (V-12345678)'),
          _filaDemo('Producto:', 'PRODUCTO PRUEBA 01'),
          _filaDemo('Almacén:', 'ALMACEN 01'),
          _filaDemo('Cliente/Proveedor:', 'PROVEEDOR DEMO S.A.'),
          _filaDemo('Selección:', 'PROVEEDOR'),
          _filaDemo('Razón Social:', 'PROVEEDOR DEMO S.A.'),
          const SizedBox(height: 4),
          const Divider(color: Colors.black, thickness: 1, height: 6),
          const Center(
            child: Text('LECTURA DE PESOS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5)),
          ),
          const Divider(color: Colors.black45, height: 6),
          const Divider(color: Colors.black45, height: 6),
          // Tabla de lecturas: la MISMA rejilla que el PDF y el preview de la app
          // —(vacío) | Fec, Hrs | CAMIÓN | REMOLQUE | TOTAL—, con una fila por
          // pesada, la de TOTALES (los netos por vehículo) y el PESO NETO.
          _filaLecturaDemo('', 'Fec, Hrs', 'CAMIÓN', 'REMOLQUE', 'TOTAL', bold: true, cabecera: true),
          _filaLecturaDemo('ENTRADA:', '24/09/2026 – 11:33', '37.914,00 kg', '0,00 kg', '37.914,00 kg'),
          _filaLecturaDemo('SALIDA:', '24/09/2026 – 11:58', '22.084,00 kg', '0,00 kg', '22.084,00 kg'),
          _filaLecturaDemo('', 'TOTALES:', '15.830,00 kg', '0,00 kg', '15.830,00 kg'),
          const Divider(color: Colors.black45, height: 6),
          _filaLecturaDemo('PESO NETO:', '15.830,00 kg', '(DESPACHO)', '', '', bold: true),
          _filaLecturaDemo('PESO DECLARADO / DIFERENCIA:', '', '', '15.800,00', '+30,00', bold: true),
          _filaLecturaDemo('DESVIACIÓN:', '', '', '', '0,19 %', bold: true),
          const Divider(color: Colors.black, thickness: 1, height: 6),
          const Center(
            child: Text('DATOS ADICIONALES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5)),
          ),
          const Divider(color: Colors.black45, height: 6),
          _filaDemo('Documento:', 'G-000123'),
          _filaDemo('Unidades:', '250.000,00'),
          _filaDemo('Densidad:', '0,920000'),
          const Divider(color: Colors.black, thickness: 1, height: 6),
          const Center(
            child: Text('OBSERVACIONES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5)),
          ),
          const Divider(color: Colors.black45, height: 6),
          if (_preset.mostrarDetalles) ...[
            Text(
              'test_ticket_caption'.tr(),
              style: const TextStyle(fontSize: 9.0, fontStyle: FontStyle.italic),
            ),
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

  Widget _filaDemo(String label, String valor, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              valor,
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaLecturaDemo(
    String label,
    String fecha,
    String camion,
    String remolque,
    String total, {
    bool bold = false,
    bool cabecera = false,
  }) {
    final s = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontSize: 9.5,
    );
    // Mismo reparto de anchos que el PDF y el preview (`_REQUIERE_TABLA_PESOS`).
    const List<int> anchos = [75, 58, 74, 63, 57];
    final List<String> celdas = [label, fecha, camion, remolque, total];
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
                celdas[i],
                textAlign: cabecera
                    ? TextAlign.center
                    : (i == 0 ? TextAlign.left : TextAlign.right),
                style: s,
              ),
            ),
          ],
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
