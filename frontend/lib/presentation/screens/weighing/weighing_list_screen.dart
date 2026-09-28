import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/i18n/translations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/number_utils.dart';
import '../../../core/utils/save_file_utils.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../data/repositories/weighing_repository.dart' show WeighingRepository;
import '../../../domain/entities/weighing.dart';
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
  /// Formato de boleto configurado para la empresa (REQ-NF-ONB-004).
  String _formatoDefault = 'PDF';
  Product? _producto;
  ThirdParty? _cliente;
  CatalogData _catalogos = CatalogData.empty;

  bool get _soloSalidas => widget.estadoInicial == 'CERRADO';

  @override
  void initState() {
    super.initState();
    _estado = widget.estadoInicial;
    _loadCatalogs();
    _cargarFormatoTicket();
  }

  @override
  void dispose() {
    _placaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarFormatoTicket() async {
    final prefs = await di.sl<ApiClient>().getPreferenciasEmpresa();
    if (!mounted) return;
    setState(() => _formatoDefault = prefs['formato_ticket'] ?? 'PDF');
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

  Future<void> _imprimirTicket(String boleto, String nombreBoleto,
      {String? formato}) async {
    final fmt = (formato ?? _formatoDefault).toUpperCase();
    if (boleto.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ticket_not_synced'.tr()),
            backgroundColor: SwsColors.warning,
          ),
        );
      }
      return;
    }
    try {
      final Response response = fmt == 'TXT'
          ? await di.sl<WeighingRepository>().getTicketTxt(boleto)
          : await di.sl<WeighingRepository>().getTicketPdf(boleto);
      final dynamic datos = response.data;
      final bytes = (datos is List<int>) ? datos : null;
      if (bytes == null || bytes.isEmpty) {
        throw Exception('ticket_invalid'.tr());
      }
      final ruta = await SaveFileUtils.save(
          bytes, 'ticket_$nombreBoleto.${fmt == 'TXT' ? 'txt' : 'pdf'}',
          subcarpeta: 'tickets');
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
                              PopupMenuButton<String>(
                                tooltip: 'Imprimir ticket (PDF o TXT)',
                                enabled: w.boleto.isNotEmpty,
                                icon: const Icon(Icons.print_outlined,
                                    color: SwsColors.gray600),
                                onSelected: (formato) => _imprimirTicket(
                                    w.boleto,
                                    w.numeroBoleto ?? w.boleto,
                                    formato: formato),
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                      value: 'PDF',
                                      child: Text('ticket_pdf'.tr())),
                                  PopupMenuItem(
                                      value: 'TXT',
                                      child: Text('ticket_txt'.tr())),
                                ],
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