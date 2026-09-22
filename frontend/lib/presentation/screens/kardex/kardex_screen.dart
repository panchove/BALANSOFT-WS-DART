import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/number_utils.dart';
import '../../../core/utils/save_file_utils.dart';
import '../../../domain/entities/catalogs.dart';
import '../../../domain/entities/kardex.dart';
import '../../../domain/usecases/catalog_usecases.dart';
import '../../../domain/usecases/kardex_usecases.dart';
import '../../../injection.dart' as di;
import '../../providers/bloc/kardex/kardex_bloc.dart';

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

  List<Product> _productos = [];
  List<Warehouse> _almacenes = [];

  @override
  void initState() {
    super.initState();
    _cargarCatalogs();
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
      final ruta = await SaveFileUtils.save(
          response.data as List<int>, nombre, subcarpeta: 'kardex');
      messenger.showSnackBar(
        SnackBar(content: Text('Kardex exportado: $ruta')),
      );
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
      final ruta = await SaveFileUtils.save(
          response.data as List<int>, nombre, subcarpeta: 'kardex');
      messenger.showSnackBar(
        SnackBar(content: Text('Kardex exportado: $ruta')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('No se pudo exportar PDF: $e'),
        backgroundColor: SwsColors.danger,
      ));
    } finally {
      if (mounted) setState(() => _exportandoPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 700;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kardex - Inventario'),
        actions: [
          IconButton(
            tooltip: 'Export Excel',
            onPressed: _exportandoExcel ? null : _exportarExcel,
            icon: Icon(_exportandoExcel ? Icons.hourglass_empty : Icons.table_chart_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'Export PDF',
            icon: Icon(_exportandoPdf ? Icons.hourglass_empty : Icons.picture_as_pdf_outlined),
            onSelected: (String result) {
              if (!_exportandoPdf) _exportarPdf(orientacion: result);
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'V',
                child: Text('PDF (Vertical)'),
              ),
              const PopupMenuItem<String>(
                value: 'H',
                child: Text('PDF (Horizontal)'),
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
          Expanded(
            child: BlocBuilder<KardexBloc, KardexState>(
              bloc: _bloc,
              builder: (context, state) {
                if (state is KardexLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is KardexError) {
                  return Center(
                    child: Text('No se pudo obtener el kardex:\n${state.message}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: SwsColors.danger)),
                  );
                }
                if (state is KardexLoaded) {
                  return _contenido(state.detalle, isWide);
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
        hint: const Text('Almacén'),
        value: _idAlmacen,
        items: [
          const DropdownMenuItem<String>(value: null, child: Text('Todos')),
          for (final w in _almacenes)
            DropdownMenuItem(value: w.id, child: Text(w.nombre)),
        ],
        onChanged: (v) => setState(() => _idAlmacen = v),
      ),
      DropdownButton<String>(
        hint: const Text('Producto'),
        value: _idProducto,
        items: [
          const DropdownMenuItem<String>(value: null, child: Text('Todos')),
          for (final p in _productos)
            DropdownMenuItem(value: p.id, child: Text(p.nombre)),
        ],
        onChanged: (v) => setState(() => _idProducto = v),
      ),
      TextButton.icon(
        onPressed: () => _elegirFecha(desde: true),
        icon: const Icon(Icons.calendar_month_outlined, size: 18),
        label: Text('Desde: ${_fmt(_desde)}'),
      ),
      TextButton.icon(
        onPressed: () => _elegirFecha(desde: false),
        icon: const Icon(Icons.calendar_month_outlined, size: 18),
        label: Text('Hasta: ${_fmt(_hasta)}'),
      ),
      FilledButton.icon(
        onPressed: _buscar,
        icon: const Icon(Icons.search),
        label: const Text('Buscar'),
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

  Widget _contenido(KardexDetalle detalle, bool isWide) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: SwsColors.primary.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: isWide
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _col('Saldo inicial', NumberUtils.formatKg(detalle.saldoInicial)),
                      _col('Saldo actual', NumberUtils.formatKg(detalle.saldoActual)),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _col('Saldo inicial', NumberUtils.formatKg(detalle.saldoInicial)),
                      const SizedBox(height: 8),
                      _col('Saldo actual', NumberUtils.formatKg(detalle.saldoActual)),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 8),
        if (detalle.movimientos.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('Sin movimientos en el período.',
                textAlign: TextAlign.center,
                style: TextStyle(color: SwsColors.gray600)),
          )
        else if (isWide)
          DataTable(
            columns: const [
              DataColumn(label: Text('Fecha')),
              DataColumn(label: Text('Movimiento')),
              DataColumn(label: Text('Producto')),
              DataColumn(label: Text('Peso (kg)'), numeric: true),
              DataColumn(label: Text('Saldo'), numeric: true),
              DataColumn(label: Text('Ref')),
            ],
            rows: [
              for (final m in detalle.movimientos)
                DataRow(cells: [
                  DataCell(Text(m.fecha)),
                  DataCell(Text(
                    m.etiquetaMovimiento,
                    style: TextStyle(
                      color: m.esIngreso ? SwsColors.success : SwsColors.danger,
                      fontWeight: FontWeight.w600,
                    ),
                  )),
                  DataCell(Text(m.etiquetaProducto)),
                  DataCell(Text(
                    '${m.esIngreso ? '+' : '-'}${NumberUtils.formatKg(m.valor)}',
                  )),
                  DataCell(Text(NumberUtils.formatKg(m.stock))),
                  DataCell(Text(m.numeroBoleto ?? m.documento ?? '—')),
                ]),
            ],
          )
        else
          ...detalle.movimientos.map((m) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            m.esIngreso ? Icons.arrow_downward : Icons.arrow_upward,
                            size: 16,
                            color: m.esIngreso ? SwsColors.success : SwsColors.danger,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            m.etiquetaMovimiento,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: m.esIngreso ? SwsColors.success : SwsColors.danger,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${m.esIngreso ? '+' : '-'}${NumberUtils.formatKg(m.valor)}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('Producto: ${m.etiquetaProducto}',
                          style: const TextStyle(fontSize: 13)),
                      Text('Saldo: ${NumberUtils.formatKg(m.stock)}',
                          style: const TextStyle(fontSize: 13)),
                      Text('Fecha: ${m.fecha}',
                          style: const TextStyle(fontSize: 12, color: SwsColors.gray600)),
                      if (m.numeroBoleto != null || m.boleto != null || m.documento != null)
                        Text('Ref: ${m.numeroBoleto ?? m.documento ?? m.boleto ?? '—'}',
                            style: const TextStyle(fontSize: 12, color: SwsColors.gray600)),
                    ],
                  ),
                ),
              )),
      ],
    );
  }

  Widget _col(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: SwsColors.gray600)),
        ],
      );
}