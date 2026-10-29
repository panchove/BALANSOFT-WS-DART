import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../presentation/widgets/atajo_nuevo.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/i18n/translations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../injection.dart' as di;
import '../../providers/bloc/auth/auth_bloc.dart';
import '../../../domain/entities/catalogs.dart';
import 'indicadores_tab.dart';
import 'semaforos_tab.dart';
import 'camaras_tab.dart';
import 'barreras_tab.dart';

enum EstadoBalanza { sinVerificar, disponible, inestable, noDisponible }

class DispositivosScreen extends StatefulWidget {
  final int initialTab;
  const DispositivosScreen({super.key, this.initialTab = 0});

  @override
  State<DispositivosScreen> createState() => _DispositivosScreenState();
}

class _DetectarConfig {
  final String texto;
  final IconData icono;
  const _DetectarConfig(this.texto, this.icono);
}

class _DispositivosScreenState extends State<DispositivosScreen> {
  final ApiClient _api = di.sl<ApiClient>();
  List<Scale> _balanzas = const [];
  bool _cargando = true;
  String? _error;
  final Map<String, EstadoBalanza> _estados = {};
  final Map<String, PruebaConexion> _ultimaPrueba = {};
  bool _verificando = false;

  static const Map<int, _DetectarConfig> _detectarPorPestana = {
    0: _DetectarConfig('detectar_balanzas', Icons.radar_outlined),
    1: _DetectarConfig('detectar_indicadores', Icons.speed_outlined),
    2: _DetectarConfig('detectar_semaforos', Icons.traffic_outlined),
    3: _DetectarConfig('detectar_camaras', Icons.videocam_outlined),
    4: _DetectarConfig('detectar_impresoras', Icons.print_outlined),
    5: _DetectarConfig('detectar_barreras', Icons.door_sliding_outlined),
  };

  @override
  void initState() {
    super.initState();
    unawaited(_cargar().then((_) {
      if (mounted) unawaited(_escanear(silencioso: true));
    }));
  }

  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = null; });
    try {
      final resp = await _api.getList(ApiConstants.balanzas);
      final filas = (resp.data as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(Scale.fromJson).toList();
      if (!mounted) return;
      setState(() {
        _balanzas = filas;
        _estados.removeWhere((id, _) => !filas.any((b) => b.id == id));
        _ultimaPrueba.removeWhere((id, _) => !filas.any((b) => b.id == id));
      });
      unawaited(_verificarEstados(filas));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _mensajeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _verificarEstados(List<Scale> balanzas) async {
    if (balanzas.isEmpty) return;
    if (mounted) setState(() => _verificando = true);
    for (final b in balanzas) {
      final prueba = await _probarSilencioso(b.id);
      if (!mounted) return;
      setState(() {
        _estados[b.id] = _estadoDesde(prueba);
        if (prueba != null) _ultimaPrueba[b.id] = prueba;
      });
    }
    if (mounted) setState(() => _verificando = false);
  }

  Future<PruebaConexion?> _probarSilencioso(String id) async {
    try {
      final data = await _api.probarBalanza(id);
      return PruebaConexion.fromJson(data);
    } catch (_) { return null; }
  }

  EstadoBalanza _estadoDesde(PruebaConexion? p) {
    if (p == null) return EstadoBalanza.noDisponible;
    if (!p.conectado) return EstadoBalanza.noDisponible;
    if (p.estable) return EstadoBalanza.disponible;
    return EstadoBalanza.inestable;
  }

  String _mensajeError(Object e) {
    if (e is DioException && e.response?.statusCode != null) {
      final detail = e.response?.data;
      if (detail is Map && detail['detail'] != null) {
        return '${detail['detail']}';
      }
    }
    return 'No se pudo cargar los dispositivos. Revise la conexión con la API.';
  }

  Future<void> _escanear({bool silencioso = false}) async {
    if (!silencioso && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('scanning_scales'.tr())));
    }
    List<Map<String, dynamic>> encontradas;
    try {
      encontradas = await _api.descubrirBalanzas(incluirSimuladas: true);
    } catch (e) {
      if (!mounted || silencioso) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(_mensajeError(e)), backgroundColor: SwsColors.danger));
      return;
    }
    if (encontradas.isEmpty) {
      if (!mounted || silencioso) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('no_scales_found'.tr())));
      return;
    }
    final registradas = <String>{ for (final b in _balanzas) _claveHardware(b) };
    final nuevas = <Map<String, dynamic>>[];
    for (final b in encontradas) {
      final clave = _claveDesdeDescubierta(b);
      if (!registradas.contains(clave)) { nuevas.add(b); registradas.add(clave); }
    }
    var agregadas = 0;
    for (final b in nuevas) {
      try {
        await _api.createItem(ApiConstants.balanzas, {
          'descripcion': (b['descripcion'] ?? 'Báscula').toString(),
          'activo': true,
          'protocolo': b['protocolo'] ?? 'tcp',
          'ip_address': b['ip_address'],
          'puerto_tcp': b['puerto_tcp'],
          'puerto_com': b['puerto_com'],
          'is_simulada': b['is_simulada'] ?? false,
          'formato_trama': b['formato_trama'] ?? 'auto',
        });
        agregadas++;
      } catch (_) {}
    }
    if (!mounted) return;
    await _cargar();
    if (!mounted) return;
    if (!silencioso) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('scales_detected_registered'.tr(null, ['${encontradas.length}', '$agregadas'])), backgroundColor: SwsColors.info));
    } else if (agregadas > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('scale_autodetected'.tr(null, ['$agregadas'])), backgroundColor: SwsColors.info, duration: const Duration(seconds: 3)));
    }
  }

  String _claveHardware(Scale b) {
    if (b.protocolo == 'serial') return 'serial:${b.puertoCom ?? ''}';
    return 'tcp:${b.ipAddress ?? ''}:${b.puertoTcp ?? ''}';
  }

  String _claveDesdeDescubierta(Map<String, dynamic> b) {
    final protocolo = (b['protocolo'] ?? 'tcp').toString();
    if (protocolo == 'serial') return 'serial:${b['puerto_com'] ?? ''}';
    return 'tcp:${b['ip_address'] ?? ''}:${b['puerto_tcp'] ?? ''}';
  }

  Future<void> _eliminar(Scale b) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [const Icon(Icons.delete_outline, color: SwsColors.danger), const SizedBox(width: 10), Expanded(child: Text('delete_scale'.tr()))]),
        content: Text('¿Eliminar "${b.descripcion}"?\nEsta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: SwsColors.danger), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    try {
      await _api.deleteItem(ApiConstants.balanza(b.id));
      if (!mounted) return;
      await _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('scale_deleted'.tr()), backgroundColor: SwsColors.success));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_mensajeError(e)), backgroundColor: SwsColors.danger));
    }
  }

  void _abrirDetalle(Scale balanza) {
    showModalBottomSheet<void>(
      context: context, isScrollControlled: true, useSafeArea: true, showDragHandle: true,
      builder: (_) => _BalanzaDetailSheet(balanza: balanza, esAdmin: _esAdmin, onGuardado: () { unawaited(_cargar()); unawaited(_escanear(silencioso: true)); }),
    ).then((_) { if (mounted) { unawaited(_cargar()); unawaited(_escanear(silencioso: true)); } });
  }

  Future<void> _probarRapido(Scale balanza) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text('testing_connection'.tr())));
    try {
      final prueba = PruebaConexion.fromJson(await _api.probarBalanza(balanza.id));
      if (!mounted) return;
      setState(() { _estados[balanza.id] = _estadoDesde(prueba); _ultimaPrueba[balanza.id] = prueba; });
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(backgroundColor: prueba.conectado ? SwsColors.success : SwsColors.danger, content: Text(_mensajePrueba(balanza, prueba)), duration: const Duration(seconds: 3)));
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(backgroundColor: SwsColors.danger, content: Text(_mensajeError(e))));
    }
  }

  String _mensajePrueba(Scale b, PruebaConexion p) {
    if (!p.conectado) return '${b.descripcion}: sin conexión${p.detalle != null ? ' (${p.detalle})' : ''}';
    final peso = p.pesoKg?.toStringAsFixed(1) ?? '-';
    return '${b.descripcion}: ${p.estable ? "disponible" : "inestable"} · $peso kg';
  }

  bool get _esAdmin { final state = context.read<AuthBloc>().state; return state is AuthAuthenticated && state.user.isAdmin; }

  @override
  Widget build(BuildContext context) {
    return AtajoNuevo(
      onNuevo: () => unawaited(_escanear()),
      child: DefaultTabController(
        length: 6,
        initialIndex: widget.initialTab.clamp(0, 5),
        child: Builder(
          builder: (context) {
            final tabController = DefaultTabController.of(context);
            return Scaffold(
              appBar: AppBar(
                title: Text(context.tr('Dispositivos de Campo')),
                bottom: TabBar(
                  controller: tabController,
                  isScrollable: true,
                  tabs: [
                    Tab(icon: const Icon(Icons.scale_outlined), text: context.tr('Básculas')),
                    Tab(icon: const Icon(Icons.speed_outlined), text: context.tr('Indicadores')),
                    Tab(icon: const Icon(Icons.traffic_outlined), text: context.tr('Semáforos')),
                    Tab(icon: const Icon(Icons.videocam_outlined), text: context.tr('Cámaras')),
                    Tab(icon: const Icon(Icons.print_outlined), text: context.tr('Impresoras')),
                    Tab(icon: const Icon(Icons.door_sliding_outlined), text: context.tr('Barreras de Tránsito')),
                  ],
                ),
                // Solo el FAB inferior maneja la detección; no hay botón en la barra superior.
              ),
              floatingActionButton: AnimatedBuilder(
                animation: tabController,
                builder: (context, _) {
                  final cfg = _detectarPorPestana[tabController.index];
                  if (cfg == null) return const SizedBox.shrink();
                  return FloatingActionButton.extended(
                    key: const Key('dispositivos_agregar'),
                    onPressed: () => _detectarSegunPestana(tabController.index),
                    icon: Icon(cfg.icono),
                    label: Text(context.tr(cfg.texto)),
                  );
                },
              ),
              body: TabBarView(
                controller: tabController,
                children: [
                  _cargando
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? _CentroError(mensaje: _error!, onReintentar: _cargar)
                          : RefreshIndicator(
                              onRefresh: _cargar,
                              child: _balanzas.isEmpty
                                  ? _listaVacia()
                                  : ListView.builder(
                                      padding: const EdgeInsets.all(16),
                                      physics: const AlwaysScrollableScrollPhysics(),
                                      itemCount: _balanzas.length,
                                      itemBuilder: (context, i) => _tarjeta(_balanzas[i]),
                                    ),
                                ),
                  const IndicadoresConfigTab(),
                  const SemaforosConfigTab(),
                  const CamarasConfigTab(),
                  const Center(child: Text('Impresoras - Próximamente')),
                  const BarrerasConfigTab(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _detectarSegunPestana(int index) async {
    final cfg = _detectarPorPestana[index];
    if (cfg == null) return;

    setState(() => _verificando = true);

    try {
      List<Map<String, dynamic>> data;
      switch (index) {
        case 0: data = await _api.descubrirBalanzas(); break;
        case 1: data = await _api.descubrirSemaforos(); break;
        case 2: data = await _api.descubrirCamaras(); break;
        case 3: data = await _api.descubrirBarras(); break;
        default: return;
      }
      if (!mounted) return;

      final encontrados = data as List? ?? [];
      _mostrarSnackBar(
        '${cfg.texto.split(' ')[1]}: ${encontrados.length} dispositivo(s) encontrado(s)',
      );
      unawaited(_cargar());
    } catch (e) {
      if (!mounted) return;
      _mostrarSnackBar('Error de conexión: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _verificando = false);
    }
  }


  void _mostrarSnackBar(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: SwsColors.info),
    );
  }

  Widget _listaVacia() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.scale_outlined, size: 56, color: SwsColors.gray400),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            'No hay básculas registradas.\nPresione "Detectar" para buscarlas automáticamente.',
            textAlign: TextAlign.center,
            style: TextStyle(color: SwsColors.gray500),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: FilledButton.tonalIcon(
            key: const Key('dispositivos_escanear_vacio'),
            onPressed: _escanear,
            icon: const Icon(Icons.radar_outlined),
            label: Text(context.tr('detectar_balanzas')),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _tarjeta(Scale b) {
    final estado = _estados[b.id] ?? EstadoBalanza.sinVerificar;
    final prueba = _ultimaPrueba[b.id];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _colorEstado(estado).withValues(alpha: 0.12),
          foregroundColor: _colorEstado(estado),
          child: Icon(b.tieneHardware ? Icons.sensors : Icons.scale_outlined, size: 20),
        ),
        title: Row(
          children: [
            Flexible(child: Text(b.descripcion, overflow: TextOverflow.ellipsis)),
            if (b.isSimulada) ...[
              const SizedBox(width: 8),
              _badgeSimulada(),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(b.configuracionHardware, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Row(
              children: [
                _chipEstado(estado),
                const SizedBox(width: 6),
                _chipProtocolo(b.protocolo),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _textoEstado(estado, prueba),
                    style: const TextStyle(fontSize: 11, color: SwsColors.gray600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Probar conexión',
              icon: const Icon(Icons.play_arrow),
              color: SwsColors.primary,
              onPressed: () => _probarRapido(b),
            ),
            IconButton(
              tooltip: 'Eliminar',
              icon: const Icon(Icons.delete_outline),
              color: SwsColors.danger,
              onPressed: () => _eliminar(b),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => _abrirDetalle(b),
      ),
    );
  }

  Color _colorEstado(EstadoBalanza e) {
    switch (e) {
      case EstadoBalanza.disponible: return SwsColors.success;
      case EstadoBalanza.inestable: return SwsColors.warning;
      case EstadoBalanza.noDisponible: return SwsColors.danger;
      case EstadoBalanza.sinVerificar: return SwsColors.gray500;
    }
  }

  String _textoEstado(EstadoBalanza e, PruebaConexion? p) {
    switch (e) {
      case EstadoBalanza.disponible:
        return p?.pesoKg != null ? 'Disponible · ${p!.pesoKg!.toStringAsFixed(1)} kg' : 'Disponible';
      case EstadoBalanza.inestable: return 'Inestable · peso oscilando';
      case EstadoBalanza.noDisponible:
        return p?.detalle?.isNotEmpty == true ? 'No disponible · ${p!.detalle}' : 'No disponible';
      case EstadoBalanza.sinVerificar: return 'Sin verificar';
    }
  }

  Widget _chipEstado(EstadoBalanza e) {
    final color = _colorEstado(e);
    final texto = switch (e) {
      EstadoBalanza.disponible => 'Disponible',
      EstadoBalanza.inestable => 'Inestable',
      EstadoBalanza.noDisponible => 'No disponible',
      EstadoBalanza.sinVerificar => 'Sin verificar',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: 6),
        Text(texto, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }

  Widget _chipProtocolo(String protocolo) {
    final esSerial = protocolo.toLowerCase() == 'serial';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: SwsColors.gray200, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(esSerial ? Icons.usb : Icons.router_outlined, size: 10, color: SwsColors.gray700),
          const SizedBox(width: 4),
          Text(protocolo.toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: SwsColors.gray700)),
        ],
      ),
    );
  }

  Widget _badgeSimulada() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: SwsColors.blue100, borderRadius: BorderRadius.circular(6)),
      child: Text('simulated'.tr(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: SwsColors.primary)),
    );
  }
}

class _CentroError extends StatelessWidget {
  const _CentroError({required this.mensaje, required this.onReintentar});

  final String mensaje;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: SwsColors.danger),
            const SizedBox(height: 12),
            Text(mensaje, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onReintentar, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}

class _BalanzaDetailSheet extends StatefulWidget {
  const _BalanzaDetailSheet({required this.balanza, required this.esAdmin, required this.onGuardado});

  final Scale balanza;
  final bool esAdmin;
  final VoidCallback onGuardado;

  @override
  State<_BalanzaDetailSheet> createState() => _BalanzaDetailSheetState();
}

class _BalanzaDetailSheetState extends State<_BalanzaDetailSheet> {
  @override
  Widget build(BuildContext context) {
    return const SizedBox();
  }
}


