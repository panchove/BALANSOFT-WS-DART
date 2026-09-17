import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/number_utils.dart';
import '../../../core/utils/save_file_utils.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../data/repositories/weighing_repository.dart' show WeighingRepository;
import '../../../domain/entities/catalogs.dart';
import '../../../injection.dart' as di;
import '../../providers/bloc/auth/auth_bloc.dart';
import '../../providers/bloc/weighing/weighing_bloc.dart';
import 'weighing_form_screen.dart';
import 'weighing_detail_screen.dart';

class WeighingListScreen extends StatefulWidget {
  /// Estado inicial del filtro (Consultas Entradas/Salidas).
  /// `null` muestra todos; `CERRADO` inicia en despachos terminados.
  final String? estadoInicial;
  final String? titulo;

  const WeighingListScreen({
    super.key,
    this.estadoInicial,
    this.titulo,
  });

  @override
  State<WeighingListScreen> createState() => _WeighingListScreenState();
}

class _WeighingListScreenState extends State<WeighingListScreen> {
  final _placaCtrl = TextEditingController();
  DateTimeRange? _rango;
  String? _estado;
  bool _soloPendientes = false;
  Product? _producto;
  ThirdParty? _cliente;
  CatalogData _catalogos = CatalogData.empty;

  bool get _soloSalidas => widget.estadoInicial == 'CERRADO';

  @override
  void initState() {
    super.initState();
    _estado = widget.estadoInicial;
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

  Future<void> _imprimirTicket(String boleto, String nombreBoleto) async {
    try {
      final response = await di.sl<WeighingRepository>().getTicketPdf(boleto);
      final bytes = response.data;
      if (bytes is! List<int> || bytes.isEmpty) {
        throw Exception('El servidor no devolvió un PDF válido.');
      }
      final ruta = await SaveFileUtils.save(
          bytes, 'ticket_$nombreBoleto.pdf', subcarpeta: 'tickets');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ticket guardado en: $ruta'),
            backgroundColor: SwsColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al generar ticket: $e'),
            backgroundColor: SwsColors.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final esOperador =
        authState is AuthAuthenticated && authState.user.isOperador;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titulo ?? 'Historial de Pesajes'),
        actions: [
          if (!_soloSalidas)
            IconButton(
              key: const Key('listar_pendientes_btn'),
              tooltip: 'Solo pendientes de salida',
              onPressed: () => setState(() => _soloPendientes = !_soloPendientes),
              icon: Icon(
                _soloPendientes
                    ? Icons.filter_alt
                    : Icons.filter_alt_outlined,
                color: _soloPendientes
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          IconButton(
            tooltip: 'Nuevo pesaje',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WeighingFormScreen()),
            ),
            icon: const Icon(Icons.add),
          ),
        ],
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
                  final allItems = state.weighings;
                  var items = allItems.where(_passesFilters).toList();
                  if (_soloPendientes) {
                    items = items.where((w) => w.isOpen).toList();
                  }
                  final pendientesCount = allItems.where((w) => w.isOpen).length;
                  if (items.isEmpty) {
                    return _pendientesBanner(context, pendientesCount);
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
                            size: 26,
                          ),
                          title: Text(
                              '${w.idVehiculo ?? 'N/A'} — ${w.numeroBoleto ?? _corto(w.boleto)}'),
                          subtitle: Text(
                            '${w.estadoBoleto} · '
                            '${w.fechaHoraEntrada.toLocal().toString().substring(0, 16)} · '
                            '${NumberUtils.formatKg(w.pesoEntradaVehiculo)}',
                          ),
                          isThreeLine: !w.isClosed,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Imprimir ticket',
                                icon: const Icon(Icons.print_outlined),
                                color: SwsColors.gray600,
                                onPressed: () => _imprimirTicket(
                                    w.boleto, w.numeroBoleto ?? w.boleto),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
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

  Widget _pendientesBanner(BuildContext context, int pendientesCount) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_soloPendientes && pendientesCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ActionChip(
                avatar: const Icon(
                  Icons.radio_button_checked,
                  size: 16,
                  color: SwsColors.warning,
                ),
                label: Text('$pendientesCount pendiente(s)'),
                onPressed: () => setState(() => _soloPendientes = false),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _soloPendientes ? 'Sin camiones pendientes de salida' : 'Sin resultados',
                style: const TextStyle(color: SwsColors.gray500),
              ),
            ),
          if (pendientesCount > 0 && _soloPendientes)
            TextButton(
              onPressed: () => setState(() => _soloPendientes = false),
              child: const Text('Ver todos los pesajes'),
            ),
          if (_soloPendientes && pendientesCount == 0)
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const WeighingFormScreen()),
              ),
              child: const Text('Registrar nueva entrada'),
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