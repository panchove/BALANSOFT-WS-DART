import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/i18n/translations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/conceptos_kardex_rules.dart';
import '../../../core/utils/number_utils.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../domain/entities/catalogs.dart';
import '../../../domain/usecases/catalog_usecases.dart';
import '../../../injection.dart' as di;
import '../../screens/kardex/kardex_screen.dart';

/// Gestión: Ajustes de Inventario.
///
/// Muestra el estado actual de existencias por almacén y permite abrir un
/// diálogo modal para registrar movimientos de ajuste manual (mermas,
/// conteos físicos, correcciones) contra el kardex de inventario.
class AjustesInventarioScreen extends StatefulWidget {
  const AjustesInventarioScreen({super.key});

  @override
  State<AjustesInventarioScreen> createState() =>
      _AjustesInventarioScreenState();
}

class _AjustesInventarioScreenState extends State<AjustesInventarioScreen> {
  List<Warehouse> _almacenes = [];
  List<Product> _productos = [];
  bool _cargando = true;

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
      _cargando = false;
    });
  }

  Future<void> _abrirModalAjuste() async {
    final registrado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogoAjuste(
        productos: _productos,
        almacenes: _almacenes,
      ),
    );
    if (registrado == true && mounted) {
      await _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 700;
    final totalTon = _almacenes.fold<double>(
        0, (acc, w) => acc + w.stockActualTon);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Ajustes de Inventario')),
        actions: [
          IconButton(
            tooltip: context.tr('Ver kardex completo'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const KardexScreen()),
            ),
            icon: const Icon(Icons.table_chart_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirModalAjuste,
        backgroundColor: SwsColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.tune),
        label: Text('Nuevo ajuste'),
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
                  Card(
                    margin: EdgeInsets.zero,
                    color: SwsColors.blue100,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'stocks_by_warehouse'.tr(),
                        style: const TextStyle(
                            fontSize: 12.5, color: SwsColors.gray700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (isWide)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: [
                          DataColumn(label: Text('warehouse'.tr())),
                          DataColumn(label: Text('code'.tr())),
                          DataColumn(label: Text('location'.tr())),
                          DataColumn(
                              label: Text('cap_ton'.tr()), numeric: true),
                          DataColumn(
                              label: Text('stock_ton'.tr()), numeric: true),
                        ],
                        rows: [
                          for (final w in _almacenes)
                            DataRow(cells: [
                              DataCell(Text(w.nombre)),
                              DataCell(Text(w.codigo ?? '—')),
                              DataCell(Text(w.ubicacion ?? '—')),
                              DataCell(Text(
                                  w.capacidadMaxTon?.toStringAsFixed(2) ??
                                      '—')),
                              DataCell(
                                  Text(w.stockActualTon.toStringAsFixed(2))),
                            ]),
                        ],
                      ),
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

                // ── Nota informativa ──────────────────────────────────────
                Card(
                  color: SwsColors.accent.withValues(alpha: 0.08),
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline,
                            color: SwsColors.accent, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Los ajustes manuales se registran contra el '
                            'kardex de inventario y requieren justificación. '
                            'Usa el botón inferior para abrir el formulario.',
                            style: TextStyle(
                                fontSize: 12.5,
                                color: SwsColors.gray700,
                                height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 80), // espacio para el FAB
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
// Diálogo modal de registro de ajuste
// ---------------------------------------------------------------------------

/// Diálogo modal para registrar movimientos manuales de kardex por ajuste.
///
/// Permite al administrador registrar entradas (mermas recuperadas, compras,
/// devoluciones) o salidas (mermas, pérdidas, correcciones) con justificación
/// obligatoria auditada. Llama a POST /api/v1/inventario/ajustes.
///
/// Devuelve `true` vía `Navigator.pop` cuando el ajuste se registró con éxito.
class _DialogoAjuste extends StatefulWidget {
  final List<Product> productos;
  final List<Warehouse> almacenes;

  const _DialogoAjuste({
    required this.productos,
    required this.almacenes,
  });

  @override
  State<_DialogoAjuste> createState() => _DialogoAjusteState();
}

class _DialogoAjusteState extends State<_DialogoAjuste> {
  final _formKey = GlobalKey<FormState>();
  final _pesoCtrl = TextEditingController();

  Product? _producto;
  Warehouse? _almacen;
  int _tipoMovimiento = 10; // 10 = INGRESO, 60 = DESPACHO
  bool _guardando = false;

  // Conceptos de Kardex (catálogo conceptos_kardex, migración 031).
  // Los conceptos del sistema (0/10/60) NO se ofrecen: los genera el sistema.
  List<Map<String, dynamic>> _conceptos = [];
  int? _conceptoId;
  String? _conceptoSigno;

  @override
  void initState() {
    super.initState();
    _cargarConceptos();
  }

  Future<void> _cargarConceptos() async {
    try {
      final response =
          await di.sl<ApiClient>().getList(ApiConstants.conceptosKardex);
      final conceptos = (response.data as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      if (!mounted) return;
      setState(() {
        _conceptos = conceptos
            .where((c) => c['es_sistema'] != true && c['activo'] != false)
            .toList();
      });
    } catch (_) {
      // Sin conceptos el formulario sigue exigiendo elegir uno; el backend
      // rechaza el ajuste sin concepto ni documento.
    }
  }

  /// Conceptos cuyo signo acompaña al tipo de movimiento seleccionado.
  List<Map<String, dynamic>> get _conceptosDelTipo {
    final esperado = _tipoMovimiento == 10 ? 'positivo' : 'negativo';
    return conceptosKardexParaAjuste(_conceptos, esperado);
  }

  @override
  void dispose() {
    _pesoCtrl.dispose();
    super.dispose();
  }

  Future<void> _registrar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_producto == null || _almacen == null) {
      _snack('select_product_warehouse'.tr(), SwsColors.danger);
      return;
    }
    if (_conceptoId == null) {
      _snack('Selecciona un concepto de kardex', SwsColors.danger);
      return;
    }
    final valor = double.parse(_pesoCtrl.text.replaceAll(',', '.'));
    // El signo de la cantidad debe acompañar al signo del concepto: el backend
    // lo rechaza con 422, pero se avisa antes de gastar la llamada.
    if (_conceptoSigno == 'positivo' && valor <= 0) {
      _snack(
        'El concepto es positivo; la cantidad debe ser mayor que cero',
        SwsColors.danger,
      );
      return;
    }
    if (_conceptoSigno == 'negativo' && valor >= 0) {
      _snack(
        'El concepto es negativo; la cantidad debe ser menor que cero',
        SwsColors.danger,
      );
      return;
    }

    setState(() => _guardando = true);
    try {
      final cantidad = _conceptoSigno == 'negativo' ? -valor : valor;
      await di.sl<ApiClient>().crearAjusteInventario(
            idConcepto: _conceptoId!,
            idProducto: _producto!.id,
            idAlmacen: _almacen!.id,
            cantidad: cantidad,
            motivo: 'Ajuste manual de inventario',
          );

      final tipo = _tipoMovimiento == 10 ? 'INGRESO' : 'DESPACHO';
      _snack(
        'Ajuste $tipo de ${_pesoCtrl.text} kg registrado en kardex',
        SwsColors.success,
      );

      // Cerrar modal devolviendo true para que la pantalla refresque stocks.
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _snack('Error al registrar ajuste: $e', SwsColors.danger);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _snack(String mensaje, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final esWide = MediaQuery.sizeOf(context).width >= 700;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.tune, color: SwsColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'register_inventory_adjust'.tr(),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          Chip(
            label: Text(
              'admin_only'.tr(),
              style: const TextStyle(fontSize: 11),
            ),
            backgroundColor: SwsColors.accent.withValues(alpha: 0.12),
          ),
        ],
      ),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Registra entradas/salidas manuales por mermas, conteos '
                  'físicos o correcciones. Requiere justificación obligatoria.',
                  style:
                      TextStyle(fontSize: 12.5, color: SwsColors.gray600),
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),

                // Tipo de movimiento: al cambiar se descarta el concepto
                // elegido, porque el signo del concepto debe acompañar al tipo.
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text('movement_type'.tr(),
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    ChoiceChip(
                      label: Text('ingreso'.tr()),
                      selected: _tipoMovimiento == 10,
                      selectedColor:
                          SwsColors.success.withValues(alpha: 0.18),
                      onSelected: _guardando
                          ? null
                          : (_) => setState(() {
                                _tipoMovimiento = 10;
                                _conceptoId = null;
                                _conceptoSigno = null;
                              }),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text('despacho'.tr()),
                      selected: _tipoMovimiento == 60,
                      selectedColor:
                          SwsColors.danger.withValues(alpha: 0.18),
                      onSelected: _guardando
                          ? null
                          : (_) => setState(() {
                                _tipoMovimiento = 60;
                                _conceptoId = null;
                                _conceptoSigno = null;
                              }),
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

                // Concepto del movimiento.
                DropdownButtonFormField<int>(
                  // ignore: deprecated_member_use
                  value: _conceptoId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Concepto de kardex *',
                    prefixIcon: Icon(Icons.rule_folder_outlined),
                  ),
                  hint: const Text('Selecciona el motivo del movimiento'),
                  items: _conceptosDelTipo
                      .map(
                        (c) => DropdownMenuItem<int>(
                          value: c['id_concepto'] is int
                              ? c['id_concepto'] as int
                              : int.tryParse('${c['id_concepto']}'),
                          child: Text(
                              '${c['id_concepto']} - ${c['nombre'] ?? ''}'),
                        ),
                      )
                      .toList(),
                  onChanged: _guardando
                      ? null
                      : (v) {
                          setState(() {
                            _conceptoId = v;
                            _conceptoSigno = v == null
                                ? null
                                : _conceptos
                                    .firstWhere(
                                      (c) => c['id_concepto'] == v,
                                      orElse: () => <String, dynamic>{},
                                    )['signo']
                                    ?.toString();
                          });
                        },
                  validator: (v) =>
                      v == null ? 'Selecciona un concepto' : null,
                ),
                const SizedBox(height: 12),

                // Cantidad: el prefijo muestra el signo que impone el concepto.
                TextFormField(
                  controller: _pesoCtrl,
                  enabled: !_guardando,
                  decoration: InputDecoration(
                    labelText: 'Cantidad a ajustar *',
                    hintText: 'Ej.: 1500.00',
                    prefixIcon: const Icon(Icons.scale_outlined),
                    prefixText: _conceptoSigno == 'negativo'
                        ? '- '
                        : (_conceptoSigno == 'positivo' ? '+ ' : null),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Campo requerido';
                    final val = double.tryParse(v.replaceAll(',', '.'));
                    if (val == null || val <= 0) {
                      return 'Debe ser mayor que cero';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.of(context).pop(false),
          child: Text('Cancelar'),
        ),
        FilledButton.icon(
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
                : (_tipoMovimiento == 10
                    ? 'Registrar ingreso'
                    : 'Registrar despacho'),
          ),
          style: FilledButton.styleFrom(
            backgroundColor:
                _tipoMovimiento == 10 ? SwsColors.success : SwsColors.danger,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _dropdownProducto() {
    return DropdownButtonFormField<Product>(
      // ignore: deprecated_member_use
      value: _producto,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Producto *',
        prefixIcon: Icon(Icons.inventory_2_outlined),
      ),
      hint: Text('select_product'.tr()),
      items: widget.productos
          .map((p) => DropdownMenuItem(value: p, child: Text(p.nombre)))
          .toList(),
      onChanged: _guardando ? null : (v) => setState(() => _producto = v),
      validator: (v) => v == null ? 'Selecciona un producto' : null,
    );
  }

  Widget _dropdownAlmacen() {
    return DropdownButtonFormField<Warehouse>(
      // ignore: deprecated_member_use
      value: _almacen,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Almacén *',
        prefixIcon: Icon(Icons.warehouse_outlined),
      ),
      hint: Text('select_warehouse'.tr()),
      items: widget.almacenes
          .map((w) => DropdownMenuItem(value: w, child: Text(w.nombre)))
          .toList(),
      onChanged: _guardando ? null : (v) => setState(() => _almacen = v),
      validator: (v) => v == null ? 'Selecciona un almacén' : null,
    );
  }
}