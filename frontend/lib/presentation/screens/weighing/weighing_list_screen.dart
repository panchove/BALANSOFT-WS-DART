import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../providers/bloc/auth/auth_bloc.dart';
import '../../providers/bloc/weighing/weighing_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/number_utils.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../domain/entities/catalogs.dart';
import '../../../injection.dart' as di;
import '../weighing/weighing_form_screen.dart';
import 'weighing_detail_screen.dart';

class WeighingListScreen extends StatefulWidget {
  const WeighingListScreen({super.key});

  @override
  State<WeighingListScreen> createState() => _WeighingListScreenState();
}

class _WeighingListScreenState extends State<WeighingListScreen> {
  final _placaCtrl = TextEditingController();
  DateTimeRange? _rango;
  String? _estado;
  Product? _producto;
  ThirdParty? _cliente;
  CatalogData _catalogos = CatalogData.empty;

  @override
  void initState() {
    super.initState();
    _loadCatalogs();
  }

  @override
  void dispose() {
    _placaCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCatalogs() async {
    final data = await di.sl<CatalogRepository>().getCachedCatalogs();
    if (mounted) setState(() => _catalogos = data ?? CatalogData.empty);
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now.add(const Duration(days: 1)),
      initialDateRange: _rango,
    );
    if (mounted) setState(() => _rango = picked);
  }

  String _corto(String s) {
    if (s.length > 8) {
      return '${s.substring(0, 8)}...';
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final esOperador =
        authState is AuthAuthenticated && authState.user.isOperador;

    return Scaffold(
      appBar: AppBar(title: const Text('Historial de Pesajes')),
      floatingActionButton: FloatingActionButton(
        key: const Key('new_weighing_fab'),
        tooltip: 'Nuevo pesaje',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const WeighingFormScreen()),
        ),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: _buildFilters(esOperador),
          ),
          Expanded(
            child: BlocBuilder<WeighingBloc, WeighingState>(
              builder: (context, state) {
                if (state is WeighingListLoaded) {
                  final items = state.weighings.where(_passesFilters).toList();
                  if (items.isEmpty) {
                    return const Center(child: Text('Sin resultados'));
                  }
                  return ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemBuilder: (context, i) {
                      final w = items[i];
                      return Card(
                        child: ListTile(
                          leading: Icon(
                            w.isOpen
                                ? Icons.radio_button_checked
                                : w.isAnulado
                                    ? Icons.block
                                    : Icons.check_circle,
                            color: w.isOpen
                                ? SwsColors.warning
                                : w.isAnulado
                                    ? SwsColors.danger
                                    : SwsColors.success,
                          ),
                          title: Text(
                              '${w.idVehiculo ?? 'N/A'} — ${w.numeroBoleto ?? _corto(w.boleto)}'),
                          subtitle: Text(
                            '${w.estadoBoleto} · '
                            '${w.fechaHoraEntrada.toLocal().toString().substring(0, 16)} · '
                            '${NumberUtils.formatKg(w.pesoEntradaVehiculo)}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  WeighingDetailScreen(boleto: w.boleto),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }
                return const Center(child: CircularProgressIndicator());
              },
            ),
          ),
        ],
      ),
    );
  }

  bool _passesFilters(dynamic w) {
    if (_placaCtrl.text.isNotEmpty &&
        !(w.idVehiculo ?? '').toLowerCase().contains(_placaCtrl.text.trim().toLowerCase())) {
      return false;
    }
    if (_estado != null && w.estadoBoleto != _estado) return false;
    if (_producto != null && w.idProducto != _producto!.id) return false;
    if (_cliente != null && w.idTercero != _cliente!.id) return false;
    if (_rango != null) {
      final fecha = w.fechaHoraEntrada;
      final desde = _rango!.start.subtract(const Duration(days: 1));
      final hasta = _rango!.end.add(const Duration(days: 1));
      if (!fecha.isAfter(desde) || !fecha.isBefore(hasta)) return false;
    }
    return true;
  }

  Widget _buildFilters(bool esOperador) {
    final productos = _catalogos.products;
    final terceros = _catalogos.thirdParties;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _placaCtrl,
                decoration: InputDecoration(
                  hintText: 'Buscar por placa',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Seleccionar fechas',
              icon: Icon(
                _rango != null ? Icons.date_range : Icons.calendar_today_outlined,
                color: _rango != null ? SwsColors.primary : SwsColors.gray500,
              ),
              onPressed: _pickRange,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: 150,
              child: InputDecorator(
                decoration: const InputDecoration(
                    labelText: 'Estado', isDense: true),
                child: DropdownButton<String>(
                  value: _estado,
                  isDense: true,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Todos')),
                    DropdownMenuItem(value: 'PENDIENTE', child: Text('Pendiente')),
                    DropdownMenuItem(value: 'CERRADO', child: Text('Cerrado')),
                    DropdownMenuItem(value: 'MODIFICADO', child: Text('Modificado')),
                    DropdownMenuItem(value: 'ANULADO', child: Text('Anulado')),
                  ],
                  onChanged: (v) => setState(() => _estado = v),
                ),
              ),
            ),
            if (!esOperador && productos.isNotEmpty)
              SizedBox(
                width: 200,
                child: InputDecorator(
                  decoration: const InputDecoration(
                      labelText: 'Producto', isDense: true),
                  child: DropdownButton<String>(
                    value: _producto?.id,
                    isDense: true,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Todos')),
                      ...productos.map((p) =>
                          DropdownMenuItem(value: p.id, child: Text(p.nombre))),
                    ],
                    onChanged: (v) => setState(
                        () => _producto = v == null ? null : productos.firstWhere((p) => p.id == v)),
                  ),
                ),
              ),
            if (terceros.isNotEmpty)
              SizedBox(
                width: 200,
                child: InputDecorator(
                  decoration: const InputDecoration(
                      labelText: 'Cliente', isDense: true),
                  child: DropdownButton<String>(
                    value: _cliente?.id,
                    isDense: true,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Todos')),
                      ...terceros.map((t) =>
                          DropdownMenuItem(value: t.id, child: Text(t.razonSocial))),
                    ],
                    onChanged: (v) => setState(
                        () => _cliente = v == null ? null : terceros.firstWhere((t) => t.id == v)),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}