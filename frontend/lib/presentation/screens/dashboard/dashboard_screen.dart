import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../providers/bloc/weighing/weighing_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/number_utils.dart';
import '../../../core/widgets/section_header.dart';
import '../../../data/repositories/weighing_repository.dart' show WeighingRepository;
import '../../../domain/entities/weighing.dart';
import '../../../domain/usecases/weighing_usecases.dart';
import '../../../injection.dart' as di;
import '../../../core/constants/catalog_resources.dart';
import '../../../presentation/providers/bloc/auth/auth_bloc.dart';
import '../catalog/catalog_section_screen.dart';
import '../dispositivos/dispositivos_screen.dart';
import '../reports/reports_screen.dart';
import '../weighing/weighing_detail_screen.dart';
import '../weighing/weighing_form_screen.dart';
import '../weighing/weighing_list_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
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
                    Text(
                      'Resumen',
                      style: TextStyle(
                        fontSize: isWide ? 20 : 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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
                    const SectionHeader(title: 'Atajos de Teclado y Comandos Rápidos'),
                    const SizedBox(height: 8),
                    _buildKeyboardShortcutsGrid(context, isWide),
                    const SizedBox(height: 24),
                    const SectionHeader(title: 'Accesos Rápidos'),
                    const SizedBox(height: 8),
                    _buildAccesosRapidos(context, isWide),
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
                              w.isOpen
                                  ? Icons.radio_button_checked
                                  : Icons.check_circle,
                              color: w.isOpen
                                  ? SwsColors.warning
                                  : SwsColors.success,
                            ),
                            title: Text(w.idVehiculo ?? 'Sin vehículo'),
                            subtitle: Text(
                              '${w.numeroBoleto ?? 'Boleto s/n'} | ${w.pesoEntradaVehiculo.toStringAsFixed(1)} kg',
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

  Widget _buildKeyboardShortcutsGrid(BuildContext context, bool isWide) {
    final authState = context.read<AuthBloc>().state;
    final esAdmin = authState is AuthAuthenticated && authState.user.isAdmin;

    final comandos = <_AtajoTeclado>[
      // ── Control global ─────────────────────────────────────────────
      const _AtajoTeclado(
        tecla: 'Ctrl + K',
        comando: '',
        etiqueta: 'Paleta de Comandos',
        icono: Icons.search_outlined,
        categoria: 'Global',
      ),
      const _AtajoTeclado(
        tecla: 'Ctrl + B',
        comando: '',
        etiqueta: 'Mostrar / Ocultar Sidebar',
        icono: Icons.menu,
        categoria: 'Global',
      ),
      const _AtajoTeclado(
        tecla: 'Ctrl + H',
        comando: '',
        etiqueta: 'Ir a Inicio / Dashboard',
        icono: Icons.home_outlined,
        categoria: 'Global',
      ),
      const _AtajoTeclado(
        tecla: 'Ctrl + ,',
        comando: 'go:configuracion',
        etiqueta: 'Abrir Configuración',
        icono: Icons.settings_outlined,
        categoria: 'Global',
        soloAdmin: true,
      ),
      const _AtajoTeclado(
        tecla: 'Ctrl + Q',
        comando: 'cfg:exit',
        etiqueta: 'Salir del Sistema',
        icono: Icons.logout,
        categoria: 'Global',
      ),
      const _AtajoTeclado(
        tecla: 'Ctrl + L',
        comando: '',
        etiqueta: 'Cerrar Sesión / Bloquear',
        icono: Icons.lock_outline,
        categoria: 'Global',
      ),
      const _AtajoTeclado(
        tecla: 'F9',
        comando: '',
        etiqueta: 'Maximizar / Restaurar',
        icono: Icons.crop_square_outlined,
        categoria: 'Global',
      ),
      const _AtajoTeclado(
        tecla: 'F11',
        comando: '',
        etiqueta: 'Pantalla Completa',
        icono: Icons.fullscreen,
        categoria: 'Global',
      ),
      // ── Crear (nuevos registros) ───────────────────────────────────
      _AtajoTeclado(
        tecla: 'Ctrl + N',
        comando: 'new:ticket',
        etiqueta: 'Nuevo Pesaje (Entrada)',
        icono: Icons.add_card,
        categoria: 'Crear',
        destino: (_) => const WeighingFormScreen(),
      ),
      _AtajoTeclado(
        tecla: 'Ctrl + Shift + N',
        comando: 'go:wm',
        etiqueta: 'Nuevo Pesaje Manual',
        icono: Icons.balance,
        categoria: 'Crear',
        destino: (_) => const WeighingFormScreen(),
      ),
      // ── Navegación rápida ──────────────────────────────────────────
      const _AtajoTeclado(
        tecla: 'Ctrl + 1',
        comando: '',
        etiqueta: 'Inicio',
        icono: Icons.home_outlined,
        categoria: 'Módulos',
      ),
      _AtajoTeclado(
        tecla: 'Ctrl + 2',
        comando: 'go:in',
        etiqueta: 'Entradas',
        icono: Icons.login,
        categoria: 'Módulos',
        destino: (_) => const WeighingListScreen(titulo: 'Entradas'),
      ),
      _AtajoTeclado(
        tecla: 'Ctrl + 3',
        comando: 'go:out',
        etiqueta: 'Salidas',
        icono: Icons.logout,
        categoria: 'Módulos',
        destino: (_) => const WeighingListScreen(titulo: 'Salidas'),
      ),
      _AtajoTeclado(
        tecla: 'Ctrl + 4',
        comando: 'reportes',
        etiqueta: 'Reportes',
        icono: Icons.assessment_outlined,
        categoria: 'Módulos',
        destino: (_) => const ReportsScreen(),
      ),
      const _AtajoTeclado(
        tecla: 'Ctrl + 5 / Alt + K',
        comando: 'go:kardex',
        etiqueta: 'Kardex',
        icono: Icons.table_rows_outlined,
        categoria: 'Módulos',
      ),
      // ── Catálogos (Alt mnemónico) ──────────────────────────────────
      _AtajoTeclado(
        tecla: 'Alt + C',
        comando: 'clientes',
        etiqueta: 'Clientes / Proveedores',
        icono: Icons.people_outline,
        categoria: 'Catálogos',
        soloAdmin: true,
        destino: (_) => CatalogSectionScreen(
          seccion: AppCatalogos.clientesYProveedores,
        ),
      ),
      _AtajoTeclado(
        tecla: 'Alt + F',
        comando: 'go:fleet',
        etiqueta: 'Flota y Transporte',
        icono: Icons.local_shipping_outlined,
        categoria: 'Catálogos',
        destino: (_) => CatalogSectionScreen(
          seccion: AppCatalogos.vehiculosYChutos,
        ),
      ),
      const _AtajoTeclado(
        tecla: 'Alt + P',
        comando: 'productos',
        etiqueta: 'Productos',
        icono: Icons.inventory_outlined,
        categoria: 'Catálogos',
      ),
      const _AtajoTeclado(
        tecla: 'Alt + A',
        comando: 'almacenes',
        etiqueta: 'Almacenes',
        icono: Icons.warehouse_outlined,
        categoria: 'Catálogos',
      ),
      const _AtajoTeclado(
        tecla: 'Alt + U',
        comando: 'usuarios',
        etiqueta: 'Usuarios',
        icono: Icons.admin_panel_settings_outlined,
        categoria: 'Sistema',
        soloAdmin: true,
      ),
      const _AtajoTeclado(
        tecla: 'Alt + D',
        comando: 'cfg:dev',
        etiqueta: 'Dispositivos',
        icono: Icons.sensors_outlined,
        categoria: 'Sistema',
        soloAdmin: true,
      ),
      const _AtajoTeclado(
        tecla: 'Alt + S',
        comando: 'seguridad',
        etiqueta: 'Seguridad',
        icono: Icons.lock_outline,
        categoria: 'Sistema',
        soloAdmin: true,
      ),
      // ── Acciones operativas ────────────────────────────────────────
      const _AtajoTeclado(
        tecla: 'F2',
        comando: '',
        etiqueta: 'Nuevo Pesaje Rápido',
        icono: Icons.bolt,
        categoria: 'Acciones',
      ),
      const _AtajoTeclado(
        tecla: 'Ctrl + A',
        comando: 'go:ajustes',
        etiqueta: 'Ajustes de Inventario',
        icono: Icons.tune,
        categoria: 'Acciones',
      ),
      const _AtajoTeclado(
        tecla: 'Ctrl + R',
        comando: '',
        etiqueta: 'Sincronizar Ahora',
        icono: Icons.sync,
        categoria: 'Acciones',
      ),
    ];

    final visibles = comandos.where((a) => !a.soloAdmin || esAdmin).toList();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: visibles.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isWide ? 3 : 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: isWide ? 3.6 : 2.6,
      ),
      itemBuilder: (context, index) {
        final atajo = visibles[index];
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              if (atajo.destino != null) {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: atajo.destino!),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Comando ${atajo.tecla}: Use el teclado o presione Ctrl+K para abrir la consola.',
                    ),
                  ),
                );
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(atajo.icono, size: 20, color: SwsColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          atajo.etiqueta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (atajo.comando.isNotEmpty)
                          Text(
                            'cmd: ${atajo.comando}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: SwsColors.gray600,
                              fontFamily: 'monospace',
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  _KbdBadge(label: atajo.tecla),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAccesosRapidos(BuildContext context, bool isWide) {
    final authState = context.read<AuthBloc>().state;
    final esAdmin =
        authState is AuthAuthenticated && authState.user.isAdmin;
    final atajos = <_AtajoModulo>[
      _AtajoModulo(
        etiqueta: 'Pesaje',
        icono: Icons.monitor_weight_outlined,
        color: SwsColors.accent,
        destino: (_) => const WeighingFormScreen(),
      ),
      _AtajoModulo(
        etiqueta: 'Catálogos / Clientes',
        icono: Icons.people_outline,
        color: SwsColors.secondary,
        soloAdmin: true,
        destino: (_) =>
            CatalogSectionScreen(seccion: AppCatalogos.clientesYProveedores),
      ),
      _AtajoModulo(
        etiqueta: 'Consultas',
        icono: Icons.search_outlined,
        color: SwsColors.info,
        destino: (_) => const WeighingListScreen(titulo: 'Pesajes'),
      ),
      _AtajoModulo(
        etiqueta: 'Reportes',
        icono: Icons.description_outlined,
        color: SwsColors.success,
        destino: (_) => const ReportsScreen(),
      ),
      _AtajoModulo(
        etiqueta: 'Mantenimiento',
        icono: Icons.sensors_outlined,
        color: SwsColors.warning,
        soloAdmin: true,
        destino: (_) => const DispositivosScreen(),
      ),
      const _AtajoModulo(
        etiqueta: 'Configuración',
        icono: Icons.settings_outlined,
        color: SwsColors.primary,
        soloAdmin: true,
      ),
    ];
    final visibles =
        atajos.where((a) => !a.soloAdmin || esAdmin).toList();
    return GridView.count(
      crossAxisCount: isWide ? 3 : 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: isWide ? 3.2 : 2.4,
      children: [for (final atajo in visibles) _tarjetaAtajo(context, atajo)],
    );
  }

  Widget _tarjetaAtajo(BuildContext context, _AtajoModulo atajo) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          final destino = atajo.destino;
          if (destino != null) {
            Navigator.of(context).push(MaterialPageRoute(builder: destino));
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Configuración: disponible en el menú lateral (Ctrl+,)',
                ),
              ),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: atajo.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(atajo.icono, size: 22, color: atajo.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  atajo.etiqueta,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    );
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 20),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        label,
                        style: const TextStyle(
                            fontSize: 12, color: SwsColors.gray600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KbdBadge extends StatelessWidget {
  final String label;

  const _KbdBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Colors.grey.shade400, width: 0.8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          fontFamily: 'monospace',
          color: Colors.black87,
        ),
      ),
    );
  }
}

class _AtajoTeclado {
  final String tecla;
  final String comando;
  final String etiqueta;
  final IconData icono;
  final String categoria;
  final bool soloAdmin;
  final WidgetBuilder? destino;

  const _AtajoTeclado({
    required this.tecla,
    required this.comando,
    required this.etiqueta,
    required this.icono,
    required this.categoria,
    this.soloAdmin = false,
    this.destino,
  });
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

class _AtajoModulo {
  final String etiqueta;
  final IconData icono;
  final Color color;
  final bool soloAdmin;
  final WidgetBuilder? destino;

  const _AtajoModulo({
    required this.etiqueta,
    required this.icono,
    required this.color,
    this.soloAdmin = false,
    this.destino,
  });
}