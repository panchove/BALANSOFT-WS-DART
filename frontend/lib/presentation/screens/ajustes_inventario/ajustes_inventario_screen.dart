import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/number_utils.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../domain/entities/catalogs.dart';
import '../../../domain/usecases/catalog_usecases.dart';
import '../../../injection.dart' as di;
import '../../screens/kardex/kardex_screen.dart';

/// Gestión: Ajustes de Inventario.
///
/// Estado actual de existencias por almacén (desde el catálogo) y formulario
/// de registro de movimientos de ajuste manual (mermas, conteos físicos,
/// correcciones) contra el kardex de inventario (REQ-FN-INV-010).
class AjustesInventarioScreen extends StatefulWidget {
  const AjustesInventarioScreen({super.key});

  @override
  State<AjustesInventarioScreen> createState() =>
      _AjustesInventarioScreenState();
}

class _AjustesInventarioScreenState extends State<AjustesInventarioScreen> {
  List<Warehouse> _almacenes = [];
  List<Product> _productos = [];
  // Nota: _cargando es mutable — cambia al refrescar stocks tras un ajuste.
  // ignore: prefer_final_fields
  bool _cargando = false;

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
      _productos = data?.products.where((p) => p.esKardex).toList() ?? [];
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
            tooltip: 'Ver kardex completo',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const KardexScreen()),
            ),
            icon: const Icon(Icons.table_chart_outlined),
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Tarjetas resumen ──────────────────────────────────────
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
                      valor: '${_productos.length}',
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

                // ── Tabla existencias por almacén ─────────────────────────
                if (_almacenes.isNotEmpty) ...[
                  const Card(
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
                  const SizedBox(height: 10),
                  if (isWide)
                    DataTable(
                      columns: const [
                        DataColumn(label: Text('Almacén')),
                        DataColumn(label: Text('Código')),
                        DataColumn(label: Text('Ubicación')),
                        DataColumn(label: Text('Cap. (ton)'), numeric: true),
                        DataColumn(label: Text('Stock (ton)'), numeric: true),
                      ],
                      rows: [
                        for (final w in _almacenes)
                          DataRow(cells: [
                            DataCell(Text(w.nombre)),
                            DataCell(Text(w.codigo ?? '—')),
                            DataCell(Text(w.ubicacion ?? '—')),
                            DataCell(Text(
                                w.capacidadMaxTon?.toStringAsFixed(2) ?? '—')),
                            DataCell(Text(
                                w.stockActualTon.toStringAsFixed(2))),
                          ]),
                      ],
                    )
                  else
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
                  const SizedBox(height: 20),
                ],

                // ── Formulario de ajuste manual ───────────────────────────
                _FormularioAjuste(
                  productos: _productos,
                  almacenes: _almacenes,
                  onAjusteRegistrado: _cargar,
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
                  style: const TextStyle(
                      color: SwsColors.gray600, fontSize: 12.5)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Formulario de registro de ajuste
// ---------------------------------------------------------------------------

/// Formulario para registrar movimientos manuales de kardex por ajuste.
///
/// Permite al administrador registrar entradas (mermas recuperadas, compras,
/// devoluciones) o salidas (mermas, pérdidas, correcciones) con justificación
/// obligatoria auditada. Llama a POST /api/v1/inventario/ajustes.
class _FormularioAjuste extends StatefulWidget {
  final List<Product> productos;
  final List<Warehouse> almacenes;
  final VoidCallback onAjusteRegistrado;

  const _FormularioAjuste({
    required this.productos,
    required this.almacenes,
    required this.onAjusteRegistrado,
  });

  @override
  State<_FormularioAjuste> createState() => _FormularioAjusteState();
}

class _FormularioAjusteState extends State<_FormularioAjuste> {
  final _formKey = GlobalKey<FormState>();
  final _pesoCtrl = TextEditingController();
  final _justCtrl = TextEditingController();

  Product? _producto;
  Warehouse? _almacen;
  int _tipoMovimiento = 10; // 10 = INGRESO, 60 = DESPACHO
  bool _guardando = false;

  @override
  void dispose() {
    _pesoCtrl.dispose();
    _justCtrl.dispose();
    super.dispose();
  }

  Future<void> _registrar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_producto == null || _almacen == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona producto y almacén'),
          backgroundColor: SwsColors.danger,
        ),
      );
      return;
    }

    setState(() => _guardando = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await di.sl<ApiClient>().crearAjusteInventario(
            idMovimiento: _tipoMovimiento,
            idProducto: _producto!.id,
            idAlmacen: _almacen!.id,
            valorKg: double.parse(_pesoCtrl.text.replaceAll(',', '.')),
            documento: _justCtrl.text.trim(),
          );

      final tipo = _tipoMovimiento == 10 ? 'INGRESO' : 'DESPACHO';
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Ajuste $tipo de ${_pesoCtrl.text} kg registrado en kardex',
          ),
          backgroundColor: SwsColors.success,
        ),
      );
      // Limpiar formulario y refrescar stocks
      _formKey.currentState!.reset();
      _pesoCtrl.clear();
      _justCtrl.clear();
      setState(() {
        _producto = null;
        _almacen = null;
        _tipoMovimiento = 10;
      });
      widget.onAjusteRegistrado();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Error al registrar ajuste: $e'),
          backgroundColor: SwsColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final esWide = MediaQuery.sizeOf(context).width >= 700;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Encabezado
              Row(
                children: [
                  const Icon(Icons.tune, color: SwsColors.primary),
                  const SizedBox(width: 8),
                  const Text(
                    'Registrar ajuste de inventario',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  Chip(
                    label: const Text(
                      'Solo administrador',
                      style: TextStyle(fontSize: 11),
                    ),
                    backgroundColor: SwsColors.accent.withValues(alpha: 0.12),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Registra entradas/salidas manuales por mermas, conteos físicos '
                'o correcciones. Requiere justificación obligatoria.',
                style: TextStyle(fontSize: 12.5, color: SwsColors.gray600),
              ),
              const Divider(height: 24),

              // Tipo de movimiento
              Row(
                children: [
                  const Text('Tipo de movimiento:',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 12),
                  ChoiceChip(
                    label: const Text('✚ INGRESO'),
                    selected: _tipoMovimiento == 10,
                    selectedColor: SwsColors.success.withValues(alpha: 0.18),
                    onSelected: (_) => setState(() => _tipoMovimiento = 10),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('✖ DESPACHO'),
                    selected: _tipoMovimiento == 60,
                    selectedColor: SwsColors.danger.withValues(alpha: 0.18),
                    onSelected: (_) => setState(() => _tipoMovimiento = 60),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Producto + Almacén
              if (esWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _dropdownProducto()),
                    const SizedBox(width: 12),
                    Expanded(child: _dropdownAlmacen()),
                  ],
                )
              else ...[
                _dropdownProducto(),
                const SizedBox(height: 12),
                _dropdownAlmacen(),
              ],
              const SizedBox(height: 12),

              // Peso
              TextFormField(
                controller: _pesoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Peso a ajustar (kg) *',
                  hintText: 'Ej.: 1500.00',
                  prefixIcon: Icon(Icons.scale_outlined),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Campo requerido';
                  final val =
                      double.tryParse(v.replaceAll(',', '.'));
                  if (val == null || val <= 0) return 'Debe ser > 0';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Justificación
              TextFormField(
                controller: _justCtrl,
                decoration: const InputDecoration(
                  labelText: 'Justificación / Documento *',
                  hintText:
                      'Ej.: Merma por evaporación mes 09, Conteo físico 2026-09',
                  prefixIcon: Icon(Icons.description_outlined),
                ),
                maxLength: 100,
                maxLines: 2,
                validator: (v) {
                  if (v == null || v.trim().length < 3) {
                    return 'Mínimo 3 caracteres';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Botón
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _guardando ? null : _registrar,
                  icon: _guardando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(_tipoMovimiento == 10
                          ? Icons.add_circle_outline
                          : Icons.remove_circle_outline),
                  label: Text(
                    _guardando
                        ? 'Registrando…'
                        : _tipoMovimiento == 10
                            ? 'Registrar ingreso al kardex'
                            : 'Registrar despacho del kardex',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _tipoMovimiento == 10
                        ? SwsColors.success
                        : SwsColors.danger,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dropdownProducto() {
    return DropdownButtonFormField<Product>(
      // ignore: deprecated_member_use
      value: _producto,
      decoration: const InputDecoration(
        labelText: 'Producto *',
        prefixIcon: Icon(Icons.inventory_2_outlined),
      ),
      hint: const Text('Seleccionar producto'),
      items: widget.productos
          .map((p) => DropdownMenuItem(value: p, child: Text(p.nombre)))
          .toList(),
      onChanged: (v) => setState(() => _producto = v),
      validator: (v) => v == null ? 'Selecciona un producto' : null,
    );
  }

  Widget _dropdownAlmacen() {
    return DropdownButtonFormField<Warehouse>(
      // ignore: deprecated_member_use
      value: _almacen,
      decoration: const InputDecoration(
        labelText: 'Almacén *',
        prefixIcon: Icon(Icons.warehouse_outlined),
      ),
      hint: const Text('Seleccionar almacén'),
      items: widget.almacenes
          .map((w) => DropdownMenuItem(value: w, child: Text(w.nombre)))
          .toList(),
      onChanged: (v) => setState(() => _almacen = v),
      validator: (v) => v == null ? 'Selecciona un almacén' : null,
    );
  }
}
