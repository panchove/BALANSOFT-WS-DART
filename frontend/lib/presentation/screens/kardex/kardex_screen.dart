import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/i18n/translations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/number_utils.dart';
import '../../../core/utils/save_file_utils.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../domain/entities/catalogs.dart';
import '../../../domain/entities/kardex.dart';
import '../../../domain/usecases/catalog_usecases.dart';
import '../../../domain/usecases/kardex_usecases.dart';
import '../../../injection.dart' as di;
import '../../providers/bloc/kardex/kardex_bloc.dart';

/// Filtro por signo del movimiento.
enum _FiltroSigno { todos, positivos, negativos }

class KardexScreen extends StatefulWidget {
  const KardexScreen({super.key});

  @override
  State<KardexScreen> createState() => _KardexScreenState();
}

class _KardexScreenState extends State<KardexScreen> {
  final KardexBloc _bloc = di.sl<KardexBloc>();

  DateTime _desde = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _hasta = DateTime.now();
  String? _idProducto;
  String? _idAlmacen;
  bool _exportandoExcel = false;
  bool _exportandoPdf = false;

  // Filtros nuevos del Bloque 3
  _FiltroSigno _filtroSigno = _FiltroSigno.todos;
  int? _filtroConceptoId;
  List<Map<String, dynamic>> _conceptosKardex = [];

  List<Product> _productos = [];
  List<Warehouse> _almacenes = [];

  @override
  void initState() {
    super.initState();
    _cargarCatalogs();
    _cargarConceptosKardex();
    _buscar();
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  Future<void> _cargarCatalogs() async {
    final data = await di.sl<GetCachedCatalogsUseCase>().execute();
    if (!mounted) return;
    setState(() {
      _productos = data?.products.where((p) => p.esKardex).toList() ?? [];
      _almacenes = data?.warehouses.toList() ?? [];
    });
  }

  Future<void> _cargarConceptosKardex() async {
    try {
      final conceptos = await di
          .sl<ApiClient>()
          .getList(ApiConstants.conceptosKardex, query: {'activo': true});
      if (!mounted) return;
      setState(() {
        _conceptosKardex = conceptos
            .where((c) => c['activo'] != false)
            .map((c) => Map<String, dynamic>.from(c))
            .toList()
          ..sort((a, b) {
            final ia = _toInt(a['id_concepto']) ?? 0;
            final ib = _toInt(b['id_concepto']) ?? 0;
            return ia.compareTo(ib);
          });
      });
    } catch (_) {
      // Sin conceptos el filtro simplemente no se muestra; el resto sigue.
    }
  }

  static int? _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _buscar() {
    _bloc.add(LoadKardexEvent(
      desde: _desde,
      hasta: _hasta,
      idProducto: _idProducto,
      idAlmacen: _idAlmacen,
    ));
  }

  Future<void> _elegirFecha({required bool desde}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: desde ? _desde : _hasta,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      if (desde) {
        _desde = picked;
      } else {
        _hasta = picked;
      }
    });
  }

  Future<void> _exportarExcel() async {
    setState(() => _exportandoExcel = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final response = await di.sl<ExportKardexExcelUseCase>().execute(
            desde: _desde,
            hasta: _hasta,
            idProducto: _idProducto,
            idAlmacen: _idAlmacen,
          );
      final nombre =
          'kardex_${_fmt(_desde)}_${_fmt(_hasta)}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final ruta = await SaveFileUtils.save(response.data as List<int>, nombre,
          subcarpeta: 'kardex');
      messenger.showSnackBar(SnackBar(content: Text('Kardex exportado: $ruta')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('No se pudo exportar Excel: $e'),
        backgroundColor: SwsColors.danger,
      ));
    } finally {
      if (mounted) setState(() => _exportandoExcel = false);
    }
  }

  Future<void> _exportarPdf({String orientacion = 'V'}) async {
    setState(() => _exportandoPdf = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final response = await di.sl<ExportKardexPdfUseCase>().execute(
            desde: _desde,
            hasta: _hasta,
            idProducto: _idProducto,
            idAlmacen: _idAlmacen,
            orientacion: orientacion,
          );
      final nombre =
          'kardex_${_fmt(_desde)}_${_fmt(_hasta)}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final ruta = await SaveFileUtils.save(response.data as List<int>, nombre,
          subcarpeta: 'kardex');
      messenger.showSnackBar(SnackBar(content: Text('Kardex exportado: $ruta')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('No se pudo exportar PDF: $e'),
        backgroundColor: SwsColors.danger,
      ));
    } finally {
      if (mounted) setState(() => _exportandoPdf = false);
    }
  }

  // ── Helpers de presentación ─────────────────────────────────────────

  String _conceptoDisplay(KardexMovimiento m) {
    final nombre = m.conceptoNombre;
    if (nombre == null || nombre.isEmpty) {
      return 'ID ${m.idMovimiento} (sin definir)';
    }
    return nombre;
  }

  Widget _conceptoCell(KardexMovimiento m) {
    final esSistema = m.conceptoEsSistema == true;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (esSistema) ...[
          const Icon(Icons.lock_outline, size: 14, color: SwsColors.gray600),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            _conceptoDisplay(m),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: esSistema ? SwsColors.gray600 : null,
              fontWeight: esSistema ? FontWeight.w500 : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _origenChip(KardexMovimiento m) {
    final origen = m.origen;
    final (Color bg, Color fg) = switch (origen) {
      'Báscula' => (
          SwsColors.info.withValues(alpha: 0.15),
          SwsColors.info,
        ),
      'Manual' => (
          SwsColors.warning.withValues(alpha: 0.18),
          SwsColors.warning,
        ),
      _ => (
          SwsColors.gray200.withValues(alpha: 0.6),
          SwsColors.gray600,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        origen,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }

  // ── KPIs ────────────────────────────────────────────────────────────

  /// Suma de `valor` donde `id_movimiento` ∈ 1..49.
  double _sumaPositivos(List<KardexMovimiento> movs) {
    return movs
        .where((m) => m.idMovimiento >= 1 && m.idMovimiento <= 49)
        .fold<double>(0, (acc, m) => acc + m.valor.abs());
  }

  /// Suma de `valor` donde `id_movimiento` ∈ 50..99 (siempre positiva).
  double _sumaNegativos(List<KardexMovimiento> movs) {
    return movs
        .where((m) => m.idMovimiento >= 50 && m.idMovimiento <= 99)
        .fold<double>(0, (acc, m) => acc + m.valor.abs());
  }

  // ── Filtro en cliente ──────────────────────────────────────────────

  List<KardexMovimiento> _aplicarFiltros(List<KardexMovimiento> movs) {
    Iterable<KardexMovimiento> it = movs;

    // Filtro por signo
    switch (_filtroSigno) {
      case _FiltroSigno.positivos:
        it = it.where((m) => m.idMovimiento >= 1 && m.idMovimiento <= 49);
      case _FiltroSigno.negativos:
        it = it.where((m) => m.idMovimiento >= 50 && m.idMovimiento <= 99);
      case _FiltroSigno.todos:
        break;
    }

    // Filtro por concepto
    if (_filtroConceptoId != null) {
      it = it.where((m) => m.idMovimiento == _filtroConceptoId);
    }

    return it.toList();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 700;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Kardex - Inventario')),
        actions: [
          IconButton(
            tooltip: context.tr('Exportar a Excel'),
            onPressed: _exportandoExcel ? null : _exportarExcel,
            icon: Icon(_exportandoExcel
                ? Icons.hourglass_empty
                : Icons.table_chart_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: context.tr('Exportar a PDF'),
            icon: Icon(_exportandoPdf
                ? Icons.hourglass_empty
                : Icons.picture_as_pdf_outlined),
            onSelected: (String result) {
              if (!_exportandoPdf) _exportarPdf(orientacion: result);
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'V',
                child: Text(context.tr('PDF (Vertical)')),
              ),
              PopupMenuItem<String>(
                value: 'H',
                child: Text(context.tr('PDF (Horizontal)')),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: _filtros(isWide),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: _filtrosSignoYConcepto(isWide),
          ),
          Expanded(
            child: BlocBuilder<KardexBloc, KardexState>(
              bloc: _bloc,
              builder: (context, state) {
                if (state is KardexLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is KardexError) {
                  return Center(
                    child: Text(
                      'No se pudo obtener el kardex:\n${state.message}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: SwsColors.danger),
                    ),
                  );
                }
                if (state is KardexLoaded) {
                  final movsFiltrados = _aplicarFiltros(state.detalle.movimientos);
                  return _contenido(state.detalle, movsFiltrados, isWide);
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filtros(bool isWide) {
    final filtroWidgets = [
      DropdownButton<String>(
        hint: Text(context.tr('Almacén')),
        value: _idAlmacen,
        items: [
          DropdownMenuItem<String>(
              value: null, child: Text(context.tr('Todos'))),
          for (final w in _almacenes)
            DropdownMenuItem(value: w.id, child: Text(w.nombre)),
        ],
        onChanged: (v) => setState(() => _idAlmacen = v),
      ),
      DropdownButton<String>(
        hint: Text(context.tr('Producto')),
        value: _idProducto,
        items: [
          DropdownMenuItem<String>(
              value: null, child: Text(context.tr('Todos'))),
          for (final p in _productos)
            DropdownMenuItem(value: p.id, child: Text(p.nombre)),
        ],
        onChanged: (v) => setState(() => _idProducto = v),
      ),
      TextButton.icon(
        onPressed: () => _elegirFecha(desde: true),
        icon: const Icon(Icons.calendar_month_outlined, size: 18),
        label: Text('${context.tr("Desde")}: ${_fmt(_desde)}'),
      ),
      TextButton.icon(
        onPressed: () => _elegirFecha(desde: false),
        icon: const Icon(Icons.calendar_month_outlined, size: 18),
        label: Text('${context.tr("Hasta")}: ${_fmt(_hasta)}'),
      ),
      FilledButton.icon(
        onPressed: _buscar,
        icon: const Icon(Icons.search),
        label: Text(context.tr('Buscar')),
      ),
    ];

    if (isWide) {
      return Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: filtroWidgets,
      );
    }
    return Column(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: filtroWidgets.take(2).toList(),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: filtroWidgets.skip(2).toList(),
        ),
      ],
    );
  }

  Widget _filtrosSignoYConcepto(bool isWide) {
    final signoWidget = SegmentedButton<_FiltroSigno>(
      segments: [
        ButtonSegment(
          value: _FiltroSigno.todos,
          label: Text(context.tr('Todos')),
          icon: const Icon(Icons.list, size: 16),
        ),
        ButtonSegment(
          value: _FiltroSigno.positivos,
          label: Text(context.tr('Positivos')),
          icon: const Icon(Icons.arrow_downward, size: 16),
        ),
        ButtonSegment(
          value: _FiltroSigno.negativos,
          label: Text(context.tr('Negativos')),
          icon: const Icon(Icons.arrow_upward, size: 16),
        ),
      ],
      selected: {_filtroSigno},
      onSelectionChanged: (s) => setState(() => _filtroSigno = s.first),
    );

    final conceptoWidget = DropdownButton<int?>(
      hint: Text(context.tr('Concepto')),
      value: _filtroConceptoId,
      items: [
        DropdownMenuItem<int?>(
            value: null, child: Text(context.tr('Todos los conceptos'))),
        for (final c in _conceptosKardex)
          DropdownMenuItem<int?>(
            value: _toInt(c['id_concepto']),
            child: Text(
              '${c['id_concepto']} — ${c['nombre'] ?? ''}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (v) => setState(() => _filtroConceptoId = v),
    );

    if (isWide) {
      return Row(
        children: [
          signoWidget,
          const SizedBox(width: 16),
          Expanded(child: conceptoWidget),
        ],
      );
    }
    return Column(
      children: [
        signoWidget,
        const SizedBox(height: 8),
        conceptoWidget,
      ],
    );
  }

  Widget _contenido(
    KardexDetalle detalle,
    List<KardexMovimiento> movsFiltrados,
    bool isWide,
  ) {
    final sumaPos = _sumaPositivos(movsFiltrados);
    final sumaNeg = _sumaNegativos(movsFiltrados);
    // Saldo final de los movimientos FILTRADOS: saldo inicial + positivos - negativos.
    final saldoFinal = detalle.saldoInicial + sumaPos - sumaNeg;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── KPIs ──────────────────────────────────────────────────────
        if (isWide)
          Row(
            children: [
              Expanded(
                child: _kpiCard(
                  label: 'Σ Positivos (01–49)',
                  valor: NumberUtils.formatKg(sumaPos),
                  color: SwsColors.success,
                  icono: Icons.arrow_downward,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _kpiCard(
                  label: 'Σ Negativos (50–99)',
                  valor: NumberUtils.formatKg(sumaNeg),
                  color: SwsColors.danger,
                  icono: Icons.arrow_upward,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _kpiCard(
                  label: 'Saldo final (filtro)',
                  valor: NumberUtils.formatKg(saldoFinal),
                  color: SwsColors.primary,
                  icono: Icons.account_balance_wallet_outlined,
                ),
              ),
            ],
          )
        else
          Column(
            children: [
              _kpiCard(
                label: 'Σ Positivos (01–49)',
                valor: NumberUtils.formatKg(sumaPos),
                color: SwsColors.success,
                icono: Icons.arrow_downward,
              ),
              const SizedBox(height: 8),
              _kpiCard(
                label: 'Σ Negativos (50–99)',
                valor: NumberUtils.formatKg(sumaNeg),
                color: SwsColors.danger,
                icono: Icons.arrow_upward,
              ),
              const SizedBox(height: 8),
              _kpiCard(
                label: 'Saldo final (filtro)',
                valor: NumberUtils.formatKg(saldoFinal),
                color: SwsColors.primary,
                icono: Icons.account_balance_wallet_outlined,
              ),
            ],
          ),
        const SizedBox(height: 12),

        // ── Saldo inicial / actual del período ────────────────────────
        Card(
          color: SwsColors.primary.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: isWide
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _col('Saldo inicial',
                          NumberUtils.formatKg(detalle.saldoInicial)),
                      _col('Saldo actual',
                          NumberUtils.formatKg(detalle.saldoActual)),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _col('Saldo inicial',
                          NumberUtils.formatKg(detalle.saldoInicial)),
                      const SizedBox(height: 8),
                      _col('Saldo actual',
                          NumberUtils.formatKg(detalle.saldoActual)),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 8),

        // ── Tabla / tarjetas ──────────────────────────────────────────
        if (movsFiltrados.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('no_movements_period'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: SwsColors.gray600)),
          )
        else if (isWide)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                DataColumn(label: Text('date'.tr())),
                DataColumn(label: Text('Concepto')),
                DataColumn(label: Text('Origen')),
                DataColumn(label: Text('product'.tr())),
                DataColumn(label: Text('weight_kg'.tr()), numeric: true),
                DataColumn(label: Text('balance'.tr()), numeric: true),
                DataColumn(label: Text('ref'.tr())),
              ],
              rows: [
                for (final m in movsFiltrados)
                  DataRow(
                    color: WidgetStateProperty.resolveWith((states) {
                      if (m.idMovimiento == 0) {
                        return SwsColors.gray200.withValues(alpha: 0.3);
                      }
                      return null;
                    }),
                    cells: [
                      DataCell(Text(m.fecha)),
                      DataCell(_conceptoCell(m)),
                      DataCell(_origenChip(m)),
                      DataCell(Text(m.etiquetaProducto)),
                      DataCell(Text(
                        '${m.esIngreso ? '+' : '-'}${NumberUtils.formatKg(m.valor)}',
                        style: TextStyle(
                          color: m.esIngreso
                              ? SwsColors.success
                              : SwsColors.danger,
                          fontWeight: FontWeight.w600,
                        ),
                      )),
                      DataCell(Text(NumberUtils.formatKg(m.stock))),
                      DataCell(
                          Text(m.numeroBoleto ?? m.documento ?? '—')),
                    ],
                  ),
              ],
            ),
          )
        else
          ...movsFiltrados.map((m) => Card(
                color: m.idMovimiento == 0
                    ? SwsColors.gray200.withValues(alpha: 0.3)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            m.esIngreso
                                ? Icons.arrow_downward
                                : Icons.arrow_upward,
                            size: 16,
                            color: m.esIngreso
                                ? SwsColors.success
                                : SwsColors.danger,
                          ),
                          const SizedBox(width: 6),
                          Expanded(child: _conceptoCell(m)),
                          const SizedBox(width: 6),
                          _origenChip(m),
                          const Spacer(),
                          Text(
                            '${m.esIngreso ? '+' : '-'}${NumberUtils.formatKg(m.valor)}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('Producto: ${m.etiquetaProducto}',
                          style: const TextStyle(fontSize: 13)),
                      Text('Saldo: ${NumberUtils.formatKg(m.stock)}',
                          style: const TextStyle(fontSize: 13)),
                      Text('Fecha: ${m.fecha}',
                          style: const TextStyle(
                              fontSize: 12, color: SwsColors.gray600)),
                      if (m.numeroBoleto != null ||
                          m.boleto != null ||
                          m.documento != null)
                        Text(
                            'Ref: ${m.numeroBoleto ?? m.documento ?? m.boleto ?? '—'}',
                            style: const TextStyle(
                                fontSize: 12, color: SwsColors.gray600)),
                    ],
                  ),
                ),
              )),
      ],
    );
  }

  Widget _kpiCard({
    required String label,
    required String valor,
    required Color color,
    required IconData icono,
  }) {
    return Card(
      elevation: 0,
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icono, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(valor,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: color)),
                  const SizedBox(height: 2),
                  Text(label,
                      style: const TextStyle(
                          fontSize: 11.5, color: SwsColors.gray600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _col(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: SwsColors.gray600)),
        ],
      );
}