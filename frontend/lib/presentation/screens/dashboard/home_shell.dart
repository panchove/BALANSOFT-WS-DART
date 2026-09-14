import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/catalog_resources.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/brand_text.dart';
import '../../providers/bloc/auth/auth_bloc.dart';
import '../../providers/bloc/weighing/weighing_bloc.dart';
import '../catalog/catalog_section_screen.dart';
import '../dispositivos/dispositivos_screen.dart';
import 'dashboard_screen.dart';
import '../settings/settings_screen.dart';
import '../weighing/weighing_list_screen.dart';
import '../reports/reports_screen.dart';
import '../kardex/kardex_screen.dart';

class HomeShell extends StatefulWidget {
  final ThemeController themeController;
  const HomeShell({super.key, required this.themeController});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    context.read<WeighingBloc>().add(const ListWeighingsEvent());
  }

  int _clampIndex(int index, int max) {
    if (index < 0) return 0;
    if (index >= max) return (max - 1).clamp(0, max);
    return index;
  }

  void _abrirConfiguracion() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(themeController: widget.themeController),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final usarSidebar = MediaQuery.sizeOf(context).shortestSide >= 600;
    final authState = context.watch<AuthBloc>().state;
    final esOperador =
        authState is AuthAuthenticated && authState.user.isOperador;
    final paginas = <Widget>[
      const DashboardScreen(),
      const WeighingListScreen(),
      if (!esOperador) ...[
        CatalogSectionScreen(seccion: AppCatalogos.flota),
        CatalogSectionScreen(seccion: AppCatalogos.inventario),
        const DispositivosScreen(),
        CatalogSectionScreen(seccion: AppCatalogos.directorio),
      ],
      const ReportsScreen(),
      if (!esOperador) const KardexScreen(),
    ];

    final idx = _clampIndex(_index, paginas.length);

    return Scaffold(
      body: (() {
        final contenido = Navigator(
          key: ValueKey('nav-$idx'),
          pages: [MaterialPage(child: paginas[idx])],
          onDidRemovePage: (_) {},
        );
        return usarSidebar
            ? Row(
                children: [
                  _SidebarModulos(
                    index: idx,
                    alSeleccionar: (i) => setState(() => _index = i),
                    abrirConfiguracion: _abrirConfiguracion,
                    esOperador: esOperador,
                  ),
                  const VerticalDivider(width: 1, thickness: 1),
                  Expanded(child: contenido),
                ],
              )
            : contenido;
      })(),
      bottomNavigationBar: usarSidebar
          ? null
          : NavigationBar(
              selectedIndex: idx,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Inicio',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.monitor_weight_outlined),
                  selectedIcon: Icon(Icons.monitor_weight),
                  label: 'Pesajes',
                ),
                if (!esOperador) ...[
                  const NavigationDestination(
                    icon: Icon(Icons.directions_car_outlined),
                    selectedIcon: Icon(Icons.directions_car),
                    label: 'Flota',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.inventory_2_outlined),
                    selectedIcon: Icon(Icons.inventory_2),
                    label: 'Inventario',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.sensors_outlined),
                    selectedIcon: Icon(Icons.sensors),
                    label: 'Dispositivos',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.people_outline),
                    selectedIcon: Icon(Icons.people),
                    label: 'Directorio',
                  ),
                ],
                const NavigationDestination(
                  icon: Icon(Icons.description_outlined),
                  selectedIcon: Icon(Icons.description),
                  label: 'Reportes',
                ),
                if (!esOperador) const NavigationDestination(
                  icon: Icon(Icons.table_chart_outlined),
                  selectedIcon: Icon(Icons.table_chart),
                  label: 'Kardex',
                ),
              ],
            ),
    );
  }
}

/// Sidebar de módulos para pantallas anchas (tablet/desktop).
class _SidebarModulos extends StatelessWidget {
  const _SidebarModulos({
    required this.index,
    required this.alSeleccionar,
    required this.abrirConfiguracion,
    required this.esOperador,
  });

  final int index;
  final ValueChanged<int> alSeleccionar;
  final VoidCallback abrirConfiguracion;
  final bool esOperador;

  @override
  Widget build(BuildContext context) {
    final entradas = <String, List<({IconData icono, IconData activo, String etiqueta, int indice})>>{
      'GENERAL': [
        (icono: Icons.home_outlined, activo: Icons.home, etiqueta: 'Inicio', indice: 0),
      ],
      'OPERACIONES': [
        (icono: Icons.monitor_weight_outlined, activo: Icons.monitor_weight, etiqueta: 'Pesajes', indice: 1),
        (icono: Icons.description_outlined, activo: Icons.description, etiqueta: 'Reportes', indice: esOperador ? 2 : 6),
      ],
      if (!esOperador) 'FLOTA': [
        (icono: Icons.directions_car_outlined, activo: Icons.directions_car, etiqueta: 'Camiones / Remolques', indice: 2),
      ],
      if (!esOperador) 'INVENTARIO': [
        (icono: Icons.inventory_2_outlined, activo: Icons.inventory_2, etiqueta: 'Productos / Almacenes / Balanzas', indice: 3),
      ],
      if (!esOperador) 'DISPOSITIVOS': [
        (icono: Icons.sensors_outlined, activo: Icons.sensors, etiqueta: 'Básculas / Conexión', indice: 4),
      ],
      if (!esOperador) 'DIRECTORIO': [
        (icono: Icons.people_outline, activo: Icons.people, etiqueta: 'Transportes / Conductores / Terceros', indice: 5),
      ],
      if (!esOperador) 'CONSULTAS': [
        (icono: Icons.table_chart_outlined, activo: Icons.table_chart, etiqueta: 'Kardex', indice: 7),
      ],
    };

    return Material(
      color: SwsColors.primary,
      child: SafeArea(
        right: false,
        child: SizedBox(
          width: 264,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    const Expanded(child: Align(alignment: Alignment.centerLeft, child: BrandText(size: 22))),
                    IconButton(
                      tooltip: 'Sincronizar',
                      icon: const Icon(Icons.sync, color: Colors.white70, size: 20),
                      onPressed: () {
                        context.read<WeighingBloc>().add(SyncWeighingsEvent());
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: _chipEstado(
                  icono: Icons.cloud_done_outlined,
                  etiqueta: 'Conectado',
                  colorIcono: SwsColors.accentLight,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    for (final entry in entradas.entries) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
                        child: Text(
                          entry.key,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      for (final e in entry.value)
                        _entrada(
                          icono: e.icono,
                          iconoActivo: e.activo,
                          etiqueta: e.etiqueta,
                          seleccionada: index == e.indice,
                          onTap: () => alSeleccionar(e.indice),
                        ),
                    ],
                  ],
                ),
              ),
              const Divider(color: Colors.white24, height: 1, indent: 12, endIndent: 12),
              _perfil(context),
              _entrada(
                icono: Icons.settings_outlined,
                iconoActivo: Icons.settings,
                etiqueta: 'Configuración',
                seleccionada: false,
                onTap: abrirConfiguracion,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chipEstado({required IconData icono, required String etiqueta, required Color colorIcono}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      constraints: const BoxConstraints(maxWidth: double.infinity),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 15, color: colorIcono),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              etiqueta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _perfil(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    String? nombre;
    String? email;
    if (authState is AuthAuthenticated) {
      nombre = authState.user.nombre;
      email = authState.user.email;
    }
    if (nombre == null && email == null) return const SizedBox.shrink();
    final iniciales = _iniciales(nombre ?? email ?? '');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: abrirConfiguracion,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: Colors.white.withValues(alpha: 0.16),
                child: Text(
                  iniciales,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      email ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _iniciales(String texto) {
    final partes = texto.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return '?';
    if (partes.length == 1) return partes.first.characters.take(2).toString().toUpperCase();
    return '${partes.first.characters.first}${partes.last.characters.first}'.toUpperCase();
  }

  Widget _entrada({
    required IconData icono,
    required IconData iconoActivo,
    required String etiqueta,
    required bool seleccionada,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: seleccionada ? Colors.white.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Icon(
                  seleccionada ? iconoActivo : icono,
                  size: 22,
                  color: seleccionada ? Colors.white : Colors.white70,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    etiqueta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: seleccionada ? FontWeight.w700 : FontWeight.w500,
                      color: seleccionada ? Colors.white : Colors.white70,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
