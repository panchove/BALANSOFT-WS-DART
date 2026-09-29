import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/i18n/translations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/number_utils.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../domain/entities/weighing.dart';
import '../../../domain/entities/catalogs.dart';
import '../../../injection.dart' as di;
import '../../providers/bloc/auth/auth_bloc.dart';
import '../../providers/bloc/weighing/weighing_bloc.dart';
import 'weighing_form_screen.dart';
import 'weighing_detail_screen.dart';
import '../../widgets/ticket_preview_dialog.dart';

final RouteObserver<ModalRoute<void>> weighingListRouteObserver =
    RouteObserver<ModalRoute<void>>();

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

class _WeighingListScreenState extends State<WeighingListScreen> with RouteAware {
  final _placaCtrl = TextEditingController();
  DateTimeRange? _rango;
  String? _estado;
  bool _soloPendientes = false;

  Product? _producto;
  ThirdParty? _cliente;
  CatalogData _catalogos = CatalogData.empty;
  /// Última lista cargada: evita el "refresh infinito" cuando el estado global
  /// de WeighingBloc cambia (detalle/crear/sync) sin ser un listado.
  List<Weighing>? _items;
  /// Marca si hay una petición de lista en curso (o encolada en el bloc):
  /// evita auto-disparos repetidos cuando el listado aún no tiene datos.
  bool _solicitandoCarga = false;

  bool get _soloSalidas => widget.estadoInicial == 'CERRADO';

  @override
  void initState() {
    super.initState();
    _estado = widget.estadoInicial;
    _loadCatalogs();
    _loadCatalogs();
    _recargarLista();
  }

  void _recargarLista() {
    if (!mounted) return;
    _solicitandoCarga = true;
    context.read<WeighingBloc>().add(const ListWeighingsEvent());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      weighingListRouteObserver.subscribe(this, route as ModalRoute<void>);
    }
  }

  @override
  void didPopNext() {
    // Al volver del detalle o del formulario el Bloc queda en otro estado;
    // se recarga el listado para no quedarse en el spinner indefinido.
    _recargarLista();
  }

  @override
  void dispose() {
    weighingListRouteObserver.unsubscribe(this);
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
            child: BlocListener<WeighingBloc, WeighingState>(
              listenWhen: (_, s) =>
                  s is WeighingListLoaded ||
                  s is WeighingError ||
                  s is WeighingSyncComplete,
              listener: (context, s) {
                if (s is WeighingListLoaded) {
                  _solicitandoCarga = false;
                  if (!identical(_items, s.weighings)) {
                    setState(() => _items = s.weighings);
                  }
                } else if (s is WeighingError) {
                  _solicitandoCarga = false;
                } else if (s is WeighingSyncComplete && _items == null) {
                  // Tras un sync sin datos cargados aún, se pide el listado de
                  // nuevo para no quedarse en el spinner infinito.
                  _recargarLista();
                }
              },
              child: BlocBuilder<WeighingBloc, WeighingState>(
                builder: (context, state) {
                  final allItems = _items;
                  if (allItems == null) {
                    if (state is WeighingError) {
                      return _errorVista(context, state.message);
                    }
                    if (state is WeighingSyncing ||
                        state is WeighingLoading ||
                        _solicitandoCarga) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    // Estado terminal sin listado y sin petición en curso:
                    // se lanza una recarga para no quedarse cargando en bucle.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && !_solicitandoCarga) _recargarLista();
                    });
                    return const Center(child: CircularProgressIndicator());
                  }
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
                              '${w.idVehiculo ?? 'N/A'} — ${w.numeroBoleto ?? 'Boleto #${i + 1}'}'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  _TipoMovimientoChip(w: w),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      '${w.estadoBoleto} · '
                                      '${w.fechaHoraEntrada.toLocal().toString().substring(0, 16)} · '
                                      '${NumberUtils.formatKg(w.pesoEntradaVehiculo)}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          isThreeLine: !w.isClosed,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Imprimir / Previsualizar Boleto',
                                icon: const Icon(Icons.print_outlined, color: SwsColors.gray600),
                                onPressed: w.boleto.isEmpty ? null : () {
                                  showDialog<void>(
                                    context: context,
                                    builder: (ctx) => TicketPreviewDialog(weighing: w),
                                  );
                                },
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
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorVista(BuildContext context, String mensaje) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: SwsColors.danger),
            const SizedBox(height: 12),
            Text('Error: $mensaje', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _recargarLista,
              icon: const Icon(Icons.refresh),
              label: Text('retry'.tr()),
            ),
          ],
        ),
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
              child: Text('view_all_weighings'.tr()),
            ),
          if (_soloPendientes && pendientesCount == 0)
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const WeighingFormScreen()),
              ),
              child: Text('register_new_entry'.tr()),
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
                  items: [
                    DropdownMenuItem(value: null, child: Text('all'.tr())),
                    DropdownMenuItem(value: 'PENDIENTE', child: Text('status_pending'.tr())),
                    DropdownMenuItem(value: 'CERRADO', child: Text('status_closed'.tr())),
                    DropdownMenuItem(value: 'MODIFICADO', child: Text('status_modified'.tr())),
                    DropdownMenuItem(value: 'ANULADO', child: Text('status_annulled'.tr())),
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
                      DropdownMenuItem(value: null, child: Text('all'.tr())),
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
                      DropdownMenuItem(value: null, child: Text('all'.tr())),
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

/// Etiqueta visual que distingue ENTRADA (boleto abierto/pendiente) de SALIDA
/// (boleto cerrado). Un pesaje abierto aún no tiene peso de salida; uno cerrado
/// ya completó ambas pesadas.
class _TipoMovimientoChip extends StatelessWidget {
  final Weighing w;
  const _TipoMovimientoChip({required this.w});

  @override
  Widget build(BuildContext context) {
    final esEntrada = w.isOpen;
    final esAnulado = w.isAnulado;
    final (label, color) = esAnulado
        ? ('ANULADO', SwsColors.danger)
        : esEntrada
            ? ('ENTRADA', SwsColors.warning)
            : ('SALIDA', SwsColors.success);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}