import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/number_utils.dart';
import '../../../core/widgets/proxima_fase.dart';
import '../../../domain/entities/catalogs.dart';
import '../../../domain/usecases/catalog_usecases.dart';
import '../../../injection.dart' as di;
import '../../screens/kardex/kardex_screen.dart';

/// Gestión: Ajustes de Inventario.
///
/// Estado actual de existencias por almacén (desde el catálogo) y acceso
/// al kardex de movimientos. El CRUD de ajustes (entradas/salidas por
/// mermas, conteos o correcciones) se expone en la próxima fase.
class AjustesInventarioScreen extends StatefulWidget {
  const AjustesInventarioScreen({super.key});

  @override
  State<AjustesInventarioScreen> createState() =>
      _AjustesInventarioScreenState();
}

class _AjustesInventarioScreenState extends State<AjustesInventarioScreen> {
  List<Warehouse> _almacenes = [];
  List<Product> _productos = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final data = await di.sl<GetCachedCatalogsUseCase>().execute();
    if (!mounted) return;
    setState(() {
      _almacenes = data?.warehouses.toList() ?? [];
      _productos = data?.products.toList() ?? [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 700;
    final totalTon = _almacenes.fold<double>(
        0, (acc, w) => acc + w.stockActualTon);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes de Inventario'),
        actions: [
          IconButton(
            tooltip: 'Ver kardex',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const KardexScreen()),
            ),
            icon: const Icon(Icons.table_chart_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _tarjetaResumen(
                icono: Icons.warehouse_outlined,
                etiqueta: 'Almacenes',
                valor: '${_almacenes.length}',
                color: SwsColors.primary,
              ),
              _tarjetaResumen(
                icono: Icons.inventory_2_outlined,
                etiqueta: 'Productos kardex',
                valor: '${_productos.where((p) => p.esKardex).length}',
                color: SwsColors.accent,
              ),
              _tarjetaResumen(
                icono: Icons.scale_outlined,
                etiqueta: 'Existencias (ton)',
                valor: NumberUtils.formatTons(totalTon),
                color: SwsColors.success,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_almacenes.isNotEmpty)
            const Center(
              child: Card(
                margin: EdgeInsets.zero,
                color: SwsColors.blue100,
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Existencias por almacén (1 t = 1000 kg)',
                    style: TextStyle(fontSize: 12.5, color: SwsColors.gray700),
                  ),
                ),
              ),
            ),
          if (_almacenes.isNotEmpty) const SizedBox(height: 10),
          if (isWide) ...[
            DataTable(
              columns: const [
                DataColumn(label: Text('Almacén')),
                DataColumn(label: Text('Código')),
                DataColumn(label: Text('Ubicación')),
                DataColumn(label: Text('Capacidad (ton)'), numeric: true),
                DataColumn(label: Text('Stock actual (ton)'), numeric: true),
              ],
              rows: [
                for (final w in _almacenes)
                  DataRow(cells: [
                    DataCell(Text(w.nombre)),
                    DataCell(Text(w.codigo ?? '—')),
                    DataCell(Text(w.ubicacion ?? '—')),
                    DataCell(Text(w.capacidadMaxTon?.toStringAsFixed(2) ?? '—')),
                    DataCell(Text(w.stockActualTon.toStringAsFixed(2))),
                  ]),
              ],
            ),
          ] else
            ..._almacenes.map(
              (w) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.warehouse_outlined,
                      color: SwsColors.primary),
                  title: Text(w.nombre),
                  subtitle: Text([
                    if (w.codigo != null) w.codigo!,
                    if (w.ubicacion != null) w.ubicacion!,
                  ].join(' · ')),
                  trailing: Text(
                    '${w.stockActualTon.toStringAsFixed(2)} t',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 14),
          const ProximaFase(
            titulo: 'Registro de ajustes',
            icono: Icons.tune,
            descripcion:
                'Los movimientos de ajuste (mermas, discrepancias, conteos '
                'físicos) se registrarán contra el kardex con los tipos de '
                'movimiento configurados. Requieren autorización de '
                'administrador y quedarán auditados.',
            alcance: [
              'Entrada/salida manual de kardex por ajuste',
              'Soporte de conteo físico vs saldo del sistema',
              'Justificación obligatoria y auditoría del movimiento',
            ],
          ),
        ],
      ),
    );
  }

  Widget _tarjetaResumen({
    required IconData icono,
    required String etiqueta,
    required String valor,
    required Color color,
  }) {
    return SizedBox(
      width: 190,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icono, color: color, size: 24),
              const SizedBox(height: 8),
              Text(valor,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800)),
              Text(etiqueta,
                  style: const TextStyle(color: SwsColors.gray600, fontSize: 12.5)),
            ],
          ),
        ),
      ),
    );
  }
}