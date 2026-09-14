import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/number_utils.dart';
import '../../../core/utils/save_file_utils.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../injection.dart' as di;

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

enum _ReporteAvanzado {
  transportista('Por transportista'),
  tercero('Por tercero'),
  pesoRango('Rango de peso'),
  comparativo('Comparativo mensual');

  final String etiqueta;
  const _ReporteAvanzado(this.etiqueta);
}

class _ReportsScreenState extends State<ReportsScreen> {
  DateTime _fecha = DateTime.now();
  int _year = DateTime.now().year;
  int _month = DateTime.now().month;
  bool _mensual = false;
  bool _avanzado = false;
  _ReporteAvanzado _tipoAvanzado = _ReporteAvanzado.transportista;
  DateTime _desde = DateTime.now().subtract(const Duration(days: 30));
  DateTime _hasta = DateTime.now();
  bool _estadoExportando = false;
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _cargar();
  }

  String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<Map<String, dynamic>> _cargar() async {
    final api = di.sl<ApiClient>();
    if (_avanzado) {
      final r = switch (_tipoAvanzado) {
        _ReporteAvanzado.transportista =>
          await api.getTransportistaReport(_fmt(_desde), _fmt(_hasta)),
        _ReporteAvanzado.tercero =>
          await api.getTerceroReport(_fmt(_desde), _fmt(_hasta)),
        _ReporteAvanzado.pesoRango =>
          await api.getPesoRangoReport(_fmt(_desde), _fmt(_hasta)),
        _ReporteAvanzado.comparativo =>
          await api.getComparativoReport(_year, _month),
      };
      return r.data as Map<String, dynamic>;
    }
    if (_mensual) {
      final r = await api.getMonthlyReport(_year, _month);
      return r.data as Map<String, dynamic>;
    }
    final r = await api.getDailyReport(_fmt(_fecha));
    return r.data as Map<String, dynamic>;
  }

  void _cambiarModo(String modo) {
    setState(() {
      _avanzado = modo == 'avanzado';
      _mensual = modo == 'mensual';
      _future = _cargar();
    });
  }

  Future<DateTime?> _elegirRango(DateTime inicial) async {
    return showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
  }

  Future<void> _exportExcel() async {
    setState(() => _estadoExportando = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final api = di.sl<ApiClient>();
      final params = <String, dynamic>{
        if (_mensual) ...{'year': _year, 'month': _month},
        if (!_mensual) 'fecha': _fmt(_fecha),
      };
      final response = await api.exportExcel(params);
      final nombre =
          'reporte_${_mensual ? '$_year-${_month.toString().padLeft(2, '0')}' : _fmt(_fecha)}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final ruta = await SaveFileUtils.save(
          response.data as List<int>, nombre, subcarpeta: 'reportes');
      messenger.showSnackBar(
        SnackBar(content: Text('Reporte exportado: $ruta')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('No se pudo exportar: $e'),
          backgroundColor: SwsColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _estadoExportando = false);
    }
  }

  Future<void> _elegirFecha() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() {
        _fecha = picked;
        _future = _cargar();
      });
    }
  }

  Future<void> _elegirMes() async {
    const meses = [
      'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
    ];
    final anioSel = await _seleccionar(
      'Año',
      List.generate(10, (i) => DateTime.now().year - 9 + i),
      _year,
    );
    if (anioSel == null) return;
    final mesSel = await _seleccionar(
      'Mes',
      List.generate(12, (i) => i + 1),
      _month,
      etiqueta: (m) => meses[m - 1],
    );
    if (mesSel == null || !mounted) return;
    setState(() {
      _year = anioSel;
      _month = mesSel;
      _future = _cargar();
    });
  }

  Future<T?> _seleccionar<T>(
    String titulo,
    List<T> opciones,
    T actual, {
    String Function(T)? etiqueta,
  }) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Seleccionar $titulo'),
        children: [
          for (final o in opciones)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, o),
              child: Text(
                etiqueta?.call(o) ?? '$o',
                style: TextStyle(
                  fontWeight: o == actual ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 600;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportes'),
        actions: [
          IconButton(
            tooltip: 'Recargar',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _future = _cargar()),
          ),
          IconButton(
            tooltip: 'Exportar Excel',
            icon: Icon(_estadoExportando ? Icons.hourglass_empty : Icons.download),
            onPressed: _estadoExportando ? null : _exportExcel,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              children: [
                _modoChips(),
                const SizedBox(height: 8),
                if (_avanzado)
                  _controlesAvanzados(isWide)
                else
                  (isWide
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: _mensual ? _elegirMes : _elegirFecha,
                            icon: const Icon(Icons.calendar_month_outlined, size: 18),
                            label: Text(
                              _mensual
                                  ? '$_year-${_month.toString().padLeft(2, '0')}'
                                  : _fmt(_fecha),
                            ),
                          ),
                        )
                      : SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _mensual ? _elegirMes : _elegirFecha,
                            icon: const Icon(Icons.calendar_month_outlined, size: 18),
                            label: Text(
                              _mensual
                                  ? '$_year-${_month.toString().padLeft(2, '0')}'
                                  : _fmt(_fecha),
                            ),
                          ),
                        )),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  final err = snap.error;
                  var msg = '$err';
                  if (err is DioException) {
                    msg = err.response?.data?['detail'] ?? err.message ?? 'Error';
                  }
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline,
                              size: 44, color: SwsColors.danger),
                          const SizedBox(height: 12),
                          const Text('No se pudo obtener el reporte:',
                              textAlign: TextAlign.center),
                          const SizedBox(height: 4),
                          Text(msg,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: SwsColors.gray600)),
                        ],
                      ),
                    ),
                  );
                }
                final data = snap.data!;
                return _avanzado
                    ? _buildAvanzado(data)
                    : (_mensual ? _buildMensual(data) : _buildDiario(data));
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _modoChips() {
    return SegmentedButton<String>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: 'diario', label: Text('Diario')),
        ButtonSegment(value: 'mensual', label: Text('Mensual')),
        ButtonSegment(value: 'avanzado', label: Text('Avanzados')),
      ],
      selected: _avanzado
          ? {'avanzado'}
          : (_mensual ? {'mensual'} : {'diario'}),
      onSelectionChanged: (s) => _cambiarModo(s.first),
    );
  }

  Widget _controlesAvanzados(bool isWide) {
    final conRango = _tipoAvanzado != _ReporteAvanzado.comparativo;
    final selectorTipo = SegmentedButton<_ReporteAvanzado>(
      showSelectedIcon: false,
      segments: [
        for (final t in _ReporteAvanzado.values)
          ButtonSegment(value: t, label: Text(t.etiqueta)),
      ],
      selected: {_tipoAvanzado},
      onSelectionChanged: (s) {
        setState(() {
          _tipoAvanzado = s.first;
          _future = _cargar();
        });
      },
    );
    if (!conRango) {
      return Column(
        children: [
          selectorTipo,
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _elegirMes,
            icon: const Icon(Icons.calendar_month_outlined, size: 18),
            label: Text('$_year-${_month.toString().padLeft(2, '0')}'),
          ),
        ],
      );
    }
    final rango = Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              final p = await _elegirRango(_desde);
              if (p != null && mounted) {
                setState(() {
                  _desde = p;
                  _future = _cargar();
                });
              }
            },
            icon: const Icon(Icons.play_arrow, size: 16),
            label: Text(_fmt(_desde), overflow: TextOverflow.ellipsis),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Icon(Icons.trending_flat, size: 16),
        ),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              final p = await _elegirRango(_hasta);
              if (p != null && mounted) {
                setState(() {
                  _hasta = p;
                  _future = _cargar();
                });
              }
            },
            icon: const Icon(Icons.skip_next, size: 16),
            label: Text(_fmt(_hasta), overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
    );
    return Column(
      children: [
        selectorTipo,
        const SizedBox(height: 8),
        if (isWide) rango else SizedBox(width: 480, child: rango),
      ],
    );
  }

  Widget _buildAvanzado(Map<String, dynamic> d) {
    return switch (_tipoAvanzado) {
      _ReporteAvanzado.transportista => _buildTransportista(d),
      _ReporteAvanzado.tercero => _buildTercero(d),
      _ReporteAvanzado.pesoRango => _buildPesoRango(d),
      _ReporteAvanzado.comparativo => _buildComparativo(d),
    };
  }

  Widget _buildTransportista(Map<String, dynamic> d) {
    final items = (d['transportistas'] as List? ?? [])
        .map((e) => e as Map<String, dynamic>)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _kpi('Transportistas', '${d['total_transportistas'] ?? 0}',
            Icons.local_shipping_outlined, SwsColors.primary),
        const SizedBox(height: 4),
        const Text('Volumen movilizado',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                color: SwsColors.primary)),
        const SizedBox(height: 4),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Sin movimientos de transportistas en el rango.'),
          ),
        for (final t in items)
          Card(
            child: ListTile(
              dense: true,
              title: Text('${t['razon_social'] ?? '—'}'),
              subtitle:
                  Text('${t['total_pesajes']} pesajes · ${NumberUtils.formatKg((t['peso_promedio'] as num? ?? 0).toDouble())}/prom'),
              trailing: Text(
                  NumberUtils.formatKg((t['peso_neto_total'] as num? ?? 0).toDouble())),
            ),
          ),
      ],
    );
  }

  Widget _buildTercero(Map<String, dynamic> d) {
    final items = (d['terceros'] as List? ?? [])
        .map((e) => e as Map<String, dynamic>)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _kpi('Terceros', '${d['total_terceros'] ?? 0}',
            Icons.group_outlined, SwsColors.primary),
        const SizedBox(height: 4),
        const Text('Volumen por cliente/proveedor',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                color: SwsColors.primary)),
        const SizedBox(height: 4),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Sin movimientos de terceros en el rango.'),
          ),
        for (final t in items)
          Card(
            child: ListTile(
              dense: true,
              title: Text('${t['razon_social'] ?? '—'}'),
              subtitle: Text('${t['tipo_tercero'] ?? '—'} · ${t['total_pesajes']} pesajes'),
              trailing: Text(
                  NumberUtils.formatKg((t['peso_neto_total'] as num? ?? 0).toDouble())),
            ),
          ),
      ],
    );
  }

  Widget _buildPesoRango(Map<String, dynamic> d) {
    final items = (d['rangos'] as List? ?? [])
        .map((e) => e as Map<String, dynamic>)
        .where((e) => (e['cantidad'] as num? ?? 0) > 0)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _kpi('Pesajes cerrados', '${d['total_pesajes'] ?? 0}',
            Icons.monitor_weight_outlined, SwsColors.primary),
        const SizedBox(height: 4),
        const Text('Distribución por rango de peso neto',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                color: SwsColors.primary)),
        const SizedBox(height: 4),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Sin pesajes cerrados en el rango.'),
          ),
        for (final t in items)
          Card(
            child: ListTile(
              dense: true,
              title: Text('${t['rango'] ?? '—'}'),
              trailing: Text(
                  '${t['cantidad']} · ${NumberUtils.formatKg((t['peso_total'] as num? ?? 0).toDouble())}'),
            ),
          ),
      ],
    );
  }

  Widget _buildComparativo(Map<String, dynamic> d) {
    final actual = d['actual'] as Map<String, dynamic>? ?? {};
    final anterior = d['anterior'] as Map<String, dynamic>? ?? {};
    final vPeso = d['variacion_peso'] as num?;
    final vPesajes = d['variacion_pesajes'] as num?;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _kpi('Mes actual', '${d['mes_actual'] ?? '—'}',
            Icons.today_outlined, SwsColors.primary),
        _kpi('Pesajes (actual/anterior)',
            '${actual['total_pesajes'] ?? 0} / ${anterior['total_pesajes'] ?? 0}',
            Icons.monitor_weight_outlined, SwsColors.info),
        _kpi('Peso neto (actual/anterior)',
            '${NumberUtils.formatKg((actual['peso_neto_total'] as num? ?? 0).toDouble())}\n'
            'vs ${NumberUtils.formatKg((anterior['peso_neto_total'] as num? ?? 0).toDouble())}',
            Icons.monitor_weight, SwsColors.info),
        _kpi('Variación pesajes', _fmtVar(vPesajes),
            _flechita(vPesajes), _colorVar(vPesajes)),
        _kpi('Variación peso', _fmtVar(vPeso), _flechita(vPeso),
            _colorVar(vPeso)),
      ],
    );
  }

  String _fmtVar(num? v) {
    if (v == null) return '—';
    return '${v > 0 ? '+' : ''}${v.toStringAsFixed(2)} %';
  }

  IconData _flechita(num? v) {
    if (v == null) return Icons.remove;
    if (v > 0) return Icons.trending_up;
    if (v < 0) return Icons.trending_down;
    return Icons.trending_flat;
  }

  Color _colorVar(num? v) {
    if (v == null) return SwsColors.gray400;
    if (v > 0) return SwsColors.success;
    if (v < 0) return SwsColors.danger;
    return SwsColors.gray400;
  }

  Widget _buildDiario(Map<String, dynamic> d) {
    final porProducto = (d['por_producto'] as List? ?? [])
        .map((e) => e as Map<String, dynamic>)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _kpi('Pesajes', '${d['total_pesajes'] ?? 0}', Icons.monitor_weight_outlined,
            SwsColors.primary),
        _kpi('Cerrados', '${d['cerrados'] ?? 0}', Icons.check_circle_outline,
            SwsColors.success),
        _kpi('Abiertos', '${d['abiertos'] ?? 0}', Icons.radio_button_checked,
            SwsColors.warning),
        _kpi('Peso Neto Total',
            NumberUtils.formatKg((d['peso_neto_total'] as num? ?? 0).toDouble()),
            Icons.monitor_weight, SwsColors.info),
        if (porProducto.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text('Por producto',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: SwsColors.primary)),
          const SizedBox(height: 4),
          for (final p in porProducto)
            Card(
              child: ListTile(
                dense: true,
                title: Text('${p['id_producto'] ?? 'SIN_PRODUCTO'}'),
                trailing: Text(
                    '${p['cantidad']} · ${NumberUtils.formatKg((p['peso_neto'] as num? ?? 0).toDouble())}'),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildMensual(Map<String, dynamic> d) {
    final porDia = (d['por_dia'] as List? ?? [])
        .map((e) => e as Map<String, dynamic>)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _kpi('Pesajes', '${d['total_pesajes'] ?? 0}', Icons.monitor_weight_outlined,
            SwsColors.primary),
        _kpi('Peso Neto Total',
            NumberUtils.formatKg((d['peso_neto_total'] as num? ?? 0).toDouble()),
            Icons.monitor_weight, SwsColors.info),
        if (porDia.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text('Por día',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: SwsColors.primary)),
          const SizedBox(height: 4),
          for (final p in porDia)
            Card(
              child: ListTile(
                dense: true,
                title: Text('${p['fecha'] ?? '—'}'),
                trailing: Text('${p['pesajes']} pesajes'),
              ),
            ),
        ],
      ],
    );
  }

  Widget _kpi(String label, String value, IconData icono, Color color) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          foregroundColor: color,
          child: Icon(icono, size: 20),
        ),
        title: Text(value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        subtitle: Text(label),
      ),
    );
  }
}