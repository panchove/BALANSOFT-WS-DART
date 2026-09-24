import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/datasources/local/local_storage.dart';
import '../../../domain/entities/printer_preset.dart';
import '../../../domain/entities/weighing.dart';
import '../../../injection.dart' as di;
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

  @override
  void initState() {
    super.initState();
    _cargarPreset();
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

  Future<void> _guardarPreset() async {
    setState(() => _guardando = true);
    try {
      await di.sl<LocalStorage>().savePrinterPreset(_preset);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Diseño y estilización del boleto guardados exitosamente'),
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
    // estrecho y centrado (140mm de ~196mm útiles), sin importar cuántos se
    // apilen por hoja (1..4). En térmico el ancho es el del rollo.
    final anchoBaseHoja = _preset.orientacion == 'landscape' ? 620.0 : 480.0;
    final anchoHojaNormal = anchoBaseHoja * (140 / 195.9);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diseño y Estilización del Ticket'),
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
          // ─── Tarjeta 1: Tamaño de Papel, Orientación, Boletos por Hoja y Alto ───
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.aspect_ratio, color: SwsColors.accent),
                      SizedBox(width: 8),
                      Text(
                        'Dimensiones del Boleto y Distribución por Hoja',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                          items: const [
                            DropdownMenuItem(value: 'Letter', child: Text('Carta / Letter (216x279 mm)')),
                            DropdownMenuItem(value: 'HalfLetter', child: Text('Media Carta (216x140 mm)')),
                            DropdownMenuItem(value: 'A4', child: Text('A4 (210x297 mm)')),
                            DropdownMenuItem(value: '80mm', child: Text('Rollo Térmico 80mm')),
                            DropdownMenuItem(value: '58mm', child: Text('Rollo Térmico 58mm')),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => _preset = _preset.copyWith(tamanoPapel: val));
                          },
                        ),
                      ),

                      // Boletos por Hoja
                      SizedBox(
                        width: 220,
                        child: DropdownButtonFormField<int>(
                          initialValue: _preset.boletosPorHoja,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Boletos por Hoja',
                            prefixIcon: Icon(Icons.view_stream_outlined),
                            helperText: 'Copias apiladas por página',
                          ),
                          items: const [
                            DropdownMenuItem(value: 1, child: Text('1 boleto por hoja')),
                            DropdownMenuItem(value: 2, child: Text('2 boletos por hoja')),
                            DropdownMenuItem(value: 3, child: Text('3 boletos por hoja (Tercio)')),
                            DropdownMenuItem(value: 4, child: Text('4 boletos por hoja')),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => _preset = _preset.copyWith(boletosPorHoja: val));
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
                          items: const [
                            DropdownMenuItem(value: 0.0, child: Text('Auto (Distribuido equitativo)')),
                            DropdownMenuItem(value: 70.0, child: Text('70 mm')),
                            DropdownMenuItem(value: 90.0, child: Text('90 mm (Estándar 3/hoja)')),
                            DropdownMenuItem(value: 100.0, child: Text('100 mm')),
                            DropdownMenuItem(value: 120.0, child: Text('120 mm (Estándar 2/hoja)')),
                            DropdownMenuItem(value: 140.0, child: Text('140 mm')),
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
                            const Text('Orientación del Boleto', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(value: 'portrait', icon: Icon(Icons.crop_portrait), label: Text('Vertical')),
                                ButtonSegment(value: 'landscape', icon: Icon(Icons.crop_landscape), label: Text('Horizontal')),
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
                            const Text('Formato por Defecto', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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

                      // Copias
                      SizedBox(
                        width: 140,
                        child: DropdownButtonFormField<int>(
                          initialValue: _preset.copias,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Copias',
                            prefixIcon: Icon(Icons.copy_outlined),
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
                  const Row(
                    children: [
                      Icon(Icons.palette_outlined, color: SwsColors.accent),
                      SizedBox(width: 8),
                      Text(
                        'Estilización Visual y Contenido',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Encabezado y Datos de Empresa'),
                    subtitle: const Text('Muestra el título de la empresa, RIF y número de boleto'),
                    value: _preset.mostrarEncabezado,
                    onChanged: (val) => setState(() => _preset = _preset.copyWith(mostrarEncabezado: val)),
                  ),
                  SwitchListTile(
                    title: const Text('Observaciones y Detalles del Peso'),
                    subtitle: const Text('Muestra observaciones adicionales, transporte y conductor'),
                    value: _preset.mostrarDetalles,
                    onChanged: (val) => setState(() => _preset = _preset.copyWith(mostrarDetalles: val)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

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
                          'Previsualización de Hoja (${_preset.tamanoPapel} ${_preset.orientacion.toUpperCase()}) — ${_preset.boletosPorHoja} boleto(s) por hoja',
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
                          for (int i = 0; i < (isTermico ? 1 : _preset.boletosPorHoja); i++) ...[
                            if (i > 0) ...[
                              const SizedBox(height: 10),
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
                                  Text(
                                    'Línea de corte $i',
                                    style: const TextStyle(fontSize: 9, color: Colors.grey),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                            ],
                            _buildDemoTicketBlock(isTermico),
                          ],
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
                        label: const Text('Probar e Imprimir Boleto'),
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

  Widget _buildDemoTicketBlock(bool isTermico) {
    final double textScale = _preset.boletosPorHoja == 4
        ? 9.5
        : (_preset.boletosPorHoja == 3 ? 10.2 : 11.0);

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
            const Center(
              child: Text(
                'VARIEDADES S&S',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
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
          _filaLecturaDemo('Balanza', 'Fecha/Hora', 'Peso Camion', 'Peso Remolque', 'Peso Total', bold: true),
          _filaLecturaDemo('Balanza Entrada: BALANZA PRINCIPAL', '24/09/2026 11:33', '37.914,00', '0,00', '37.914,00'),
          _filaLecturaDemo('Balanza Salida: BALANZA PRINCIPAL', '24/09/2026 11:58', '22.084,00', '0,00', '22.084,00'),
          const Divider(color: Colors.black45, height: 6),
          _filaLecturaDemo('PESO NETO (DESPACHO):', '', '15.830,00', '0,00', '-15.830,00', bold: true),
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
            const Text(
              'Prueba de diseño y estilización del boleto de pesaje',
              style: TextStyle(fontSize: 9.0, fontStyle: FontStyle.italic),
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
