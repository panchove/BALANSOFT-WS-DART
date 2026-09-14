import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../providers/bloc/weighing/weighing_bloc.dart';
import '../../providers/bloc/sync/sync_bloc.dart' hide SyncWeighingsEvent;
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/number_utils.dart';
import '../../../core/widgets/brand_text.dart';
import '../../../core/widgets/section_header.dart';
import '../../../data/repositories/weighing_repository.dart' show WeighingRepository;
import '../../../domain/entities/weighing.dart';
import '../../../domain/usecases/weighing_usecases.dart';
import '../../../injection.dart' as di;
import '../weighing/weighing_detail_screen.dart';
import '../weighing/weighing_form_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _HealthStatusBadge extends StatelessWidget {
  const _HealthStatusBadge();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SyncBloc, SyncState>(
      builder: (context, state) {
        final online = state is HealthOnline;
        final color = online ? SwsColors.success : SwsColors.danger;
        return Tooltip(
          message:
              online ? 'Backend en línea' : 'Backend sin conexión (toca para reintentar)',
          child: InkWell(
            onTap: () => context.read<SyncBloc>().add(HealthCheckEvent()),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 12, color: color),
                  const SizedBox(width: 6),
                  Text(
                    online ? 'Online' : 'Offline',
                    style: TextStyle(fontSize: 12, color: color),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    context.read<WeighingBloc>().add(const ListWeighingsEvent());
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: AppBar(
        title: const BrandText(size: 22),
        actions: [
          const _HealthStatusBadge(),
          IconButton(
            tooltip: 'Sincronizar',
            icon: const Icon(Icons.sync_outlined),
            onPressed: () => context.read<WeighingBloc>().add(SyncWeighingsEvent()),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          context.read<WeighingBloc>().add(SyncWeighingsEvent());
        },
        child: BlocListener<WeighingBloc, WeighingState>(
          listener: (context, state) {
            if (state is WeighingSyncComplete && state.failedCount > 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Sincronizados: ${state.syncedCount} · Fallidos: ${state.failedCount}',
                  ),
                  backgroundColor: SwsColors.danger,
                ),
              );
            }
          },
          child: BlocBuilder<WeighingBloc, WeighingState>(
          builder: (context, state) {
            if (state is WeighingListLoaded) {
              final weighings = state.weighings;
              final abiertos = weighings.where((w) => w.isOpen).length;
              final cerrados = weighings.where((w) => w.isClosed).length;
              final pesoTotal = weighings
                  .where((w) => w.pesoNeto != null)
                  .fold(0.0, (sum, w) => sum + w.pesoNeto!);

              return ListView(
                padding: EdgeInsets.all(isWide ? 32 : 16),
                children: [
                  Text('Resumen',
                      style: TextStyle(
                        fontSize: isWide ? 20 : 16,
                        fontWeight: FontWeight.w700,
                      )),
                  const SizedBox(height: 16),
                  _buildKpiGrid(
                    abiertos: abiertos,
                    cerrados: cerrados,
                    pesoTotal: pesoTotal,
                    isWide: isWide,
                  ),
                  const SizedBox(height: 12),
                  const _PesajesFallidosSection(),
                  const SizedBox(height: 24),
                  const SectionHeader(title: 'Vehículos en Planta'),
                  const SizedBox(height: 8),
                  const _VehEnPlantaSection(),
                  const SizedBox(height: 24),
                  const SectionHeader(title: 'Últimos Pesajes'),
                  const SizedBox(height: 8),
                  ...weighings.take(5).map((w) => Card(
                        child: ListTile(
                          leading: Icon(
                            w.isOpen ? Icons.radio_button_checked : Icons.check_circle,
                            color: w.isOpen ? SwsColors.warning : SwsColors.success,
                          ),
                          title: Text(w.idVehiculo ?? 'Sin vehículo'),
                          subtitle: Text(
                            '${w.numeroBoleto ?? _corto(w.boleto)} | ${w.pesoEntradaVehiculo.toStringAsFixed(1)} kg',
                          ),
                          trailing: Text(w.estadoBoleto),
                        ),
                      )),
                ],
              );
            }
            return const Center(child: CircularProgressIndicator());
          },
        ),
      ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const WeighingFormScreen()),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }

  String _corto(String s) {
    if (s.length > 8) {
      return '${s.substring(0, 8)}...';
    }
    return s;
  }

  Widget _buildKpiGrid({
    required int abiertos,
    required int cerrados,
    required double pesoTotal,
    required bool isWide,
  }) {
    final columns = isWide ? 4 : 2;
    final aspect = isWide ? 2.2 : 1.8;
    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: aspect,
      children: [
        FutureBuilder<int>(
          future: di.sl<WeighingRepository>().countWeighingsToday(),
          builder: (context, snap) => _kpiCard(
            value: '${snap.data ?? 0}',
            label: 'Pesajes Hoy',
            icon: Icons.today,
            color: SwsColors.info,
          ),
        ),
        _kpiCard(
          value: '$abiertos',
          label: 'Vehículos en Planta',
          icon: Icons.local_shipping,
          color: SwsColors.warning,
        ),
        _kpiCard(
          value: '$cerrados',
          label: 'Cerrados',
          icon: Icons.check_circle_outline,
          color: SwsColors.success,
        ),
        _kpiCard(
          value: pesoTotal >= 1000
              ? '${(pesoTotal / 1000).toStringAsFixed(1)}t'
              : pesoTotal.toStringAsFixed(1),
          label: 'Toneladas Movilizadas',
          icon: Icons.monitor_weight_outlined,
          color: SwsColors.primary,
        ),
      ],
    );
  }

  Widget _kpiCard({
    required String value,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 22, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(label,
                      style: const TextStyle(fontSize: 12, color: SwsColors.gray600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PesajesFallidosSection extends StatefulWidget {
  const _PesajesFallidosSection();

  @override
  State<_PesajesFallidosSection> createState() => _PesajesFallidosSectionState();
}

class _PesajesFallidosSectionState extends State<_PesajesFallidosSection> {
  late Future<List<Weighing>> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = _cargar();
  }

  Future<List<Weighing>> _cargar() => di.sl<GetFailedWeighingsUseCase>().execute();

  void _refresh() {
    setState(() {
      _futuro = _cargar();
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<WeighingBloc, WeighingState>(
      listener: (context, state) {
        if (state is WeighingSyncComplete) _refresh();
      },
      child: FutureBuilder<List<Weighing>>(
        future: _futuro,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox.shrink();
          }
          final fallidos = snap.data ?? const <Weighing>[];
          if (fallidos.isEmpty) return const SizedBox.shrink();
          return Card(
            color: SwsColors.danger.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.error_outline, size: 18, color: SwsColors.danger),
                      SizedBox(width: 8),
                      Text(
                        'Pesajes no sincronizados',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: SwsColors.danger,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final w in fallidos)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${w.numeroBoleto ?? w.boleto} | ${w.idVehiculo}',
                        style:
                            const TextStyle(fontSize: 13, color: SwsColors.gray700),
                      ),
                    ),
                  const SizedBox(height: 4),
                  const Text(
                    'Se agotaron los reintentos. Corrija y elimine el pesaje local.',
                    style: TextStyle(fontSize: 11, color: SwsColors.gray600),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _VehEnPlantaSection extends StatefulWidget {
  const _VehEnPlantaSection();

  @override
  State<_VehEnPlantaSection> createState() => _VehEnPlantaSectionState();
}

class _VehEnPlantaSectionState extends State<_VehEnPlantaSection> {
  late Future<List<Weighing>> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = _cargar();
  }

  Future<List<Weighing>> _cargar() async {
    try {
      return await di.sl<WeighingRepository>().listPendientes();
    } catch (_) {
      return <Weighing>[];
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Weighing>>(
      future: _futuro,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          );
        }
        final lista = snap.data ?? [];
        if (lista.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No hay vehículos en planta.',
              style: TextStyle(fontSize: 13, color: SwsColors.gray600),
            ),
          );
        }
        return Column(
          children: lista.map((w) {
            return Card(
              child: ListTile(
                leading: const Icon(Icons.local_shipping, color: SwsColors.warning),
                title: Text(w.idVehiculo ?? 'Sin vehículo'),
                subtitle: Text(
                  '${w.numeroBoleto ?? w.boleto} | Entrada: '
                  '${NumberUtils.formatKg(w.pesoEntradaVehiculo)}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => WeighingDetailScreen(boleto: w.boleto),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}