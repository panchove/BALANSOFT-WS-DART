import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../presentation/widgets/atajo_nuevo.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/i18n/translations.dart';
import '../../../core/services/printer_discovery.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/scale_monitor_widget.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../data/services/scale_api_client.dart';
import '../../../domain/entities/catalogs.dart';
import '../../../injection.dart' as di;
import '../../providers/bloc/auth/auth_bloc.dart';
import '../../../data/datasources/local/local_storage.dart';
import '../../../domain/entities/printer_preset.dart';
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

class _DispositivosScreenState extends State<DispositivosScreen>
    with SingleTickerProviderStateMixin {
  final ApiClient _api = di.sl<ApiClient>();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  late final TabController _tabController;
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
    _tabController = TabController(
      length: 6,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 5),
    );
    unawaited(_cargar().then((_) {
      if (mounted) unawaited(_escanear(silencioso: true));
    }));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
        ..showSnackBar(SnackBar(content: Text('Buscando dispositivos...')));
    }

    try {
      final index = _tabController.index;

      if (index == 0) {
        List<Map<String, dynamic>> encontradas = await _api.descubrirBalanzas(incluirSimuladas: true);
        
        if (encontradas.isEmpty) {
          if (!mounted || silencioso) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('no_scales_found'.tr())));
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
        
        if (!silencioso) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Básculas detectadas: ${encontradas.length} · Guardadas: $agregadas'),
            backgroundColor: SwsColors.info,
          ));
        }
        return;
      }

      if (index == 3) {
        final respActuales = await _api.getList('/api/v1/camaras');
        final camarasActuales = (respActuales.data as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map((c) => c['dispositivo']?.toString() ?? '')
            .toSet();

        final resp = await _api.getList('/api/v1/camaras/descubrir');
        final camaras = (resp.data as List? ?? []).whereType<Map<String, dynamic>>().toList();

        if (camaras.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se encontraron cámaras.')));
          return;
        }

        var agregadas = 0;
        for (final cam in camaras) {
          final dispositivo = cam['dispositivo']?.toString() ?? '';
          
          if (camarasActuales.contains(dispositivo)) {
            continue;
          }

          try {
            await _api.createItem('/api/v1/camaras', {
              'descripcion': cam['descripcion'] ?? 'Cámara',
              'origen': cam['origen'] ?? 'local',
              'dispositivo': dispositivo,
              'url_snapshot': cam['url_snapshot'] ?? '',
              'marca': cam['marca'],
              'modelo': cam['modelo'],
              'fabricante': cam['fabricante'],
              'ubicacion': cam['ubicacion'] ?? 'ambos',
              'activo': true,
              'is_simulada': cam['is_simulada'] ?? false,
            });
            agregadas++;
          } catch (e) {
            if (e is DioException) {
              debugPrint('ERROR AL GUARDAR CÁMARA: ${e.response?.data}');
            }
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Cámaras detectadas: ${camaras.length} · Nuevas guardadas: $agregadas'),
            backgroundColor: SwsColors.info,
          ));
        }
        return;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Detección no implementada para esta sección.')),
      );

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al buscar: $e'), backgroundColor: SwsColors.danger),
      );
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
      child: Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: Text(context.tr('Dispositivos de Campo')),
          bottom: TabBar(
            controller: _tabController,
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
        ),
        floatingActionButton: AnimatedBuilder(
          animation: _tabController,
          builder: (context, _) {
            final cfg = _detectarPorPestana[_tabController.index];
            if (cfg == null) return const SizedBox.shrink();
            return FloatingActionButton.extended(
              key: const Key('dispositivos_agregar'),
              onPressed: () => _escanear(),
              icon: Icon(cfg.icono),
              label: Text(context.tr(cfg.texto)),
            );
          },
        ),
        body: TabBarView(
          controller: _tabController,
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
            const _ImpresorasConfigTab(),
            const BarrerasConfigTab(),
          ],
        ),
      ),
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
  late final ApiClient _api = di.sl<ApiClient>();
  late final ScaleApiClient _scaleClient = di.sl<ScaleApiClient>();

  late String _protocolo = widget.balanza.protocolo;
  late String _formatoTrama = widget.balanza.formatoTrama;
  late int _baudrate = widget.balanza.baudrate;
  late String _delimitador = widget.balanza.delimitador ?? 'lf';
  late final TextEditingController _ipCtrl = TextEditingController(text: widget.balanza.ipAddress ?? '');
  late final TextEditingController _puertoCtrl = TextEditingController(text: widget.balanza.puertoTcp?.toString() ?? '');
  late final TextEditingController _comCtrl = TextEditingController(text: widget.balanza.puertoCom ?? '');

  bool _probando = false;
  PruebaConexion? _resultado;
  bool _monitoreo = false;
  bool _guardando = false;
  String? _error;

  Map<String, String> _indicadoresNombres = {};
  late String? _indicadorSel = widget.balanza.idIndicador;

  List<Map<String, dynamic>> _vinculosBalanza = [];
  bool _cargandoVinculos = false;
  bool _activandoVinculo = false;

  @override
  void initState() {
    super.initState();
    _cargarIndicadores();
    _cargarVinculos();
  }

  Future<void> _cargarVinculos() async {
    if (!mounted) return;
    setState(() => _cargandoVinculos = true);
    try {
      final list = await _api.listarVinculos();
      
      // Imprimimos para depurar qué está llegando
      debugPrint('VINCULOS BACKEND: $list');
      debugPrint('ID BÁSCULA ACTUAL: ${widget.balanza.id}');
      
      // Buscamos el vínculo comparando contra el ID de la báscula
      // con múltiples formatos posibles para evitar fallos.
      final filtrados = list.whereType<Map<String, dynamic>>().where((v) {
        final idBascula = v['id_bascula']?.toString() ?? 
                          v['bascula']?['id_balanza']?.toString() ?? 
                          v['bascula_id']?.toString() ?? '';
        return idBascula == widget.balanza.id;
      }).toList();
      
      debugPrint('VINCULOS FILTRADOS: $filtrados');
      
      if (!mounted) return;
      setState(() => _vinculosBalanza = filtrados);
    } catch (e) {
      debugPrint('ERROR AL CARGAR VÍNCULOS: $e');
      if (!mounted) return;
      setState(() => _vinculosBalanza = []);
    } finally {
      if (mounted) setState(() => _cargandoVinculos = false);
    }
  }

  Future<void> _activarVinculo(Map<String, dynamic> vinculo) async {
    if (_activandoVinculo) return;
    setState(() => _activandoVinculo = true);
    try {
      final idVinculo = '${vinculo['id_vinculo']}';
      await _api.activarVinculo(idVinculo);
      await _cargarVinculos();
      widget.onGuardado();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vínculo activado correctamente. Reinicie el backend para aplicar los cambios.'), backgroundColor: SwsColors.success),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_detalleError(e)), backgroundColor: SwsColors.danger),
      );
    } finally {
      if (mounted) setState(() => _activandoVinculo = false);
    }
  }

  Future<void> _cargarIndicadores() async {
    try {
      final filas = await _api.listarIndicadores();
      if (!mounted) return;
      final mapa = <String, String>{};
      for (final f in filas) {
        final id = '${f['id_indicador']}';
        final marca = (f['marca'] ?? '').toString().trim();
        final modelo = (f['modelo'] ?? '').toString().trim();
        final etiqueta = '$marca $modelo'.trim();
        mapa[id] = etiqueta.isNotEmpty ? etiqueta : '${f['descripcion']}';
      }
      setState(() => _indicadoresNombres = mapa);
    } catch (_) {}
  }

  String get _indicadorVinculadoTexto {
    final id = widget.balanza.idIndicador;
    if (id == null || id.isEmpty) return 'Sin vincular';
    return _indicadoresNombres[id] ?? 'Vinculado (indicador $id)';
  }

  Widget _campoLectura(BuildContext context, {required String etiqueta, required String valor, required IconData icono}) {
    final scheme = Theme.of(context).colorScheme;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: etiqueta,
        prefixIcon: Icon(icono),
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        suffixIcon: Tooltip(message: 'No editable: identifica al dispositivo', child: Icon(Icons.lock_outline, size: 16, color: scheme.outline)),
      ),
      child: Text(valor, style: TextStyle(fontSize: 16, color: scheme.onSurface.withValues(alpha: 0.7))),
    );
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    _puertoCtrl.dispose();
    _comCtrl.dispose();
    super.dispose();
  }

  Future<void> _probar() async {
    setState(() {
      _probando = true;
      _resultado = null;
      _error = null;
      _monitoreo = false;
    });
    try {
      final data = PruebaConexion.fromJson(await _api.probarBalanza(widget.balanza.id));
      if (!mounted) return;
      setState(() => _resultado = data);
      if (data.conectado) setState(() => _monitoreo = true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _detalleError(e));
    } finally {
      if (mounted) setState(() => _probando = false);
    }
  }

  String _detalleError(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['detail'] != null) return '${data['detail']}';
    }
    return 'No se pudo probar la conexión.';
  }

  Future<void> _guardar() async {
    final b = widget.balanza;
    final body = <String, dynamic>{
      'codigo': b.codigo,
      'descripcion': b.descripcion,
      'marca': b.marca,
      'modelo': b.modelo,
      'capacidad_max': b.capacidadMax,
      'division': b.division,
      'activo': b.activo,
      'is_simulada': b.isSimulada,
      'protocolo': _protocolo,
      'ip_address': _protocolo == 'tcp' ? _ipCtrl.text.trim() : null,
      'puerto_tcp': _protocolo == 'tcp' ? int.tryParse(_puertoCtrl.text.trim()) : null,
      'puerto_com': _protocolo == 'serial' ? (_comCtrl.text.trim().isEmpty ? null : _comCtrl.text.trim()) : null,
      'formato_trama': _formatoTrama,
      'baudrate': _protocolo == 'serial' ? _baudrate : 9600,
      'delimitador': _delimitador,
    };

    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      // 1. Guardar la configuración de la báscula
      await _api.updateItem(ApiConstants.balanza(b.id), body);

      // 2. Si hay un indicador seleccionado, enlazarlo y activarlo
      final nuevoInd = (_indicadorSel != null && _indicadorSel!.isNotEmpty) ? _indicadorSel : null;
      if (nuevoInd != null) {
        // Enlazar (esto crea el vínculo)
        await _api.enlazarIndicador(nuevoInd, b.id);
        
        // 3. Recargar los vínculos para obtener el ID del vínculo recién creado
        await _cargarVinculos();
        
        // 4. Si hay un vínculo para este indicador, activarlo automáticamente
        try {
          final vinculoCreado = _vinculosBalanza.firstWhere(
            (v) => '${v['id_indicador']}' == nuevoInd,
          );
          final idVinculo = '${vinculoCreado['id_vinculo']}';
          if (vinculoCreado['activo'] != true) {
            await _api.activarVinculo(idVinculo);
            await _cargarVinculos(); // Recargar para verlo como activo
          }
        } catch (e) {
          // Si no encuentra el vínculo o falla la activación, lo ignoramos.
          debugPrint('No se pudo activar automáticamente el vínculo: $e');
        }
      } else if (b.idIndicador != null && b.idIndicador!.isNotEmpty) {
        // Si se deseleccionó el indicador, desenlazar
        await _api.enlazarIndicador(b.idIndicador!, b.id, enlazar: false);
      }

      if (!mounted) return;
      
      widget.onGuardado();
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Configuración guardada y vínculo activado. Reinicie el backend para aplicar los cambios.'),
          duration: const Duration(seconds: 4),
          backgroundColor: SwsColors.success,
        ),
      );
      
      // Opcional: Cerrar el modal después de guardar
      // Navigator.of(context).pop();
      
    } catch (e) {
      if (!mounted) return;
      setState(() { 
        _guardando = false; 
        _error = _detalleError(e); 
      });
    } finally {
      if (mounted && _guardando) {
        setState(() => _guardando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.balanza;
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 4, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const CircleAvatar(backgroundColor: SwsColors.blue100, foregroundColor: SwsColors.primary, child: Icon(Icons.scale_outlined)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b.descripcion, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      Text(b.configuracionHardware, style: const TextStyle(fontSize: 12, color: SwsColors.gray500)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Conexión (identidad del dispositivo)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'El puerto identifica físicamente al dispositivo: si aparece con esa entrada es porque así fue detectado y no se modifica aquí. Para cambiar la conexión, elimínela y vuelva a detectarla.',
              style: TextStyle(fontSize: 12, color: SwsColors.gray500),
            ),
            const SizedBox(height: 10),
            _campoLectura(context, etiqueta: 'Protocolo', valor: _protocolo == 'serial' ? 'SERIAL / USB' : 'TCP / RED', icono: _protocolo == 'serial' ? Icons.usb : Icons.router_outlined),
            const SizedBox(height: 10),
            if (_protocolo == 'tcp') ...[
              _campoLectura(context, etiqueta: 'Dirección IP', valor: b.ipAddress ?? '—', icono: Icons.language),
              const SizedBox(height: 10),
              _campoLectura(context, etiqueta: 'Puerto TCP', valor: '${b.puertoTcp ?? 5555}', icono: Icons.router_outlined),
            ] else ...[
              _campoLectura(context, etiqueta: 'Puerto serie', valor: b.puertoCom ?? '—', icono: Icons.usb),
            ],
            const SizedBox(height: 14),
            const Text('Indicador vinculado', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 4),
            const Text(
              'Asigna qué indicador (terminal de peso) muestra el peso de esta báscula. El indicador es esclavo: solo muestra lo que la app le envía.',
              style: TextStyle(fontSize: 12, color: SwsColors.gray500),
            ),
            const SizedBox(height: 8),
            if (widget.esAdmin)
              DropdownButtonFormField<String?>(
                initialValue: _indicadoresNombres.containsKey(_indicadorSel) ? _indicadorSel : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Indicador de esta báscula', prefixIcon: Icon(Icons.speed_outlined)),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Sin vincular')),
                  ..._indicadoresNombres.entries.map((e) => DropdownMenuItem<String?>(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (v) => setState(() => _indicadorSel = v),
              )
            else
              Material(
                color: Colors.transparent,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.speed_outlined),
                  title: const Text('Indicador vinculado'),
                  subtitle: Text(_indicadorVinculadoTexto),
                  trailing: (widget.balanza.idIndicador != null) ? const Icon(Icons.link, color: SwsColors.success) : const Text('—'),
                ),
              ),
            const Divider(height: 24),
            const Text('Vínculos con indicadores', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 4),
            const Text(
              'Si el vínculo aparece inactivo, actívalo aquí para que el puente empiece a enviar el peso al indicador.',
              style: TextStyle(fontSize: 12, color: SwsColors.gray500),
            ),
            const SizedBox(height: 10),
            if (_cargandoVinculos)
              const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
            else if (_vinculosBalanza.isEmpty)
              const Text('Sin vínculos registrados para esta báscula', style: TextStyle(fontSize: 12, color: SwsColors.gray500))
            else
              ..._vinculosBalanza.map((v) {
                final activo = v['activo'] == true;
                final idInd = '${v['id_indicador'] ?? ''}';
                final indLabel = _indicadoresNombres[idInd] ?? 'Indicador $idInd';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(border: Border.all(color: SwsColors.gray200), borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    children: [
                      Icon(activo ? Icons.link : Icons.link_off, color: activo ? SwsColors.success : SwsColors.gray400),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(indLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(activo ? 'Activo' : 'Inactivo', style: TextStyle(fontSize: 12, color: activo ? SwsColors.success : SwsColors.gray500)),
                          ],
                        ),
                      ),
                      if (!activo && widget.esAdmin)
                        FilledButton.tonalIcon(
                          onPressed: _activandoVinculo ? null : () => _activarVinculo(v),
                          icon: _activandoVinculo ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow),
                          label: const Text('Activar'),
                        )
                      else if (activo)
                        const Icon(Icons.check_circle, color: SwsColors.success),
                    ],
                  ),
                );
              }),
            const Divider(height: 24),
            if (widget.esAdmin) ...[
              Text('Configuración de lectura', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _formatoTrama,
                isExpanded: true,
                decoration: InputDecoration(labelText: 'frame_format'.tr(), helperText: 'Idioma del cable: cómo el indicador envía el peso. "Auto" lo detecta solo.', helperMaxLines: 3, prefixIcon: const Icon(Icons.code)),
                items: [
                  DropdownMenuItem(value: 'auto', child: Text('frame_auto'.tr())),
                  DropdownMenuItem(value: 'json', child: Text('frame_json'.tr())),
                  DropdownMenuItem(value: 'ascii', child: Text('frame_ascii'.tr())),
                ],
                onChanged: (val) => setState(() => _formatoTrama = val ?? 'auto'),
              ),
              if (_protocolo == 'serial') ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: _baudrate,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Velocidad (baudrate)', helperText: 'Velocidad del puerto serie; debe coincidir con la del indicador.', helperMaxLines: 3, prefixIcon: Icon(Icons.speed)),
                  items: const [
                    DropdownMenuItem(value: 1200, child: Text('1200')),
                    DropdownMenuItem(value: 4800, child: Text('4800')),
                    DropdownMenuItem(value: 9600, child: Text('9600')),
                    DropdownMenuItem(value: 19200, child: Text('19200')),
                    DropdownMenuItem(value: 38400, child: Text('38400')),
                    DropdownMenuItem(value: 57600, child: Text('57600')),
                    DropdownMenuItem(value: 115200, child: Text('115200')),
                  ],
                  onChanged: (val) => setState(() => _baudrate = val ?? 9600),
                ),
              ],
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _delimitador,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Delimitador de trama', helperText: 'Marca de fin de cada lectura de peso (salto de línea, retorno de carro, etc.).', helperMaxLines: 3, prefixIcon: Icon(Icons.format_align_left)),
                items: [
                  DropdownMenuItem(value: 'lf', child: Text('delimiter_lf'.tr())),
                  DropdownMenuItem(value: 'cr', child: Text('delimiter_cr'.tr())),
                  DropdownMenuItem(value: 'crlf', child: Text('delimiter_crlf'.tr())),
                  DropdownMenuItem(value: 'stx_etx', child: Text('delimiter_stx_etx'.tr())),
                ],
                onChanged: (val) => setState(() => _delimitador = val ?? 'lf'),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _guardando ? null : _guardar,
                icon: const Icon(Icons.save_outlined),
                label: Text(_guardando ? 'Guardando…' : 'Guardar configuración'),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _probando ? null : _probar,
                    icon: _probando ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.network_check),
                    label: Text(_probando ? 'Probando…' : 'Probar conexión'),
                  ),
                ),
              ],
            ),
            if (_resultado != null) ...[
              const SizedBox(height: 10),
              _ResultadoPrueba(resultado: _resultado!),
              if (_resultado!.conectado && _monitoreo) ...[
                const SizedBox(height: 12),
                ScaleMonitorWidget(
                  client: _scaleClient,
                  label: b.descripcion,
                  balanzaId: b.id,
                  balanzaDescripcion: b.descripcion,
                  mostrarBotones: false,
                  initialWeight: _resultado!.pesoKg ?? 0,
                ),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.error_outline, size: 16, color: SwsColors.danger),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: const TextStyle(color: SwsColors.danger, fontSize: 13))),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultadoPrueba extends StatelessWidget {
  const _ResultadoPrueba({required this.resultado});

  final PruebaConexion resultado;

  @override
  Widget build(BuildContext context) {
    final ok = resultado.conectado;
    final color = ok ? SwsColors.success : SwsColors.danger;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.5))),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle_outline : Icons.cancel_outlined, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ok ? 'Conectado · ${resultado.pesoKg?.toStringAsFixed(1) ?? '-'} kg' : 'Sin conexión', style: TextStyle(fontWeight: FontWeight.w700, color: color)),
                if (ok) Text('${resultado.hardware ?? ''}${ok && resultado.estable ? ' · estable' : ' · inestable'}', style: TextStyle(fontSize: 12, color: color)),
                if (!ok && resultado.detalle != null) Text(resultado.detalle!, style: TextStyle(fontSize: 12, color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ImpresorasConfigTab extends StatefulWidget {
  const _ImpresorasConfigTab();

  @override
  State<_ImpresorasConfigTab> createState() => _ImpresorasConfigTabState();
}

class _ImpresorasConfigTabState extends State<_ImpresorasConfigTab> {
  static const String _sinImpresora = '__sin_impresora__';

  PrinterPreset _preset = const PrinterPreset();
  bool _cargando = true;
  bool _guardando = false;
  bool _escaneando = false;

  List<DiscoveredPrinter> _impresorasDescubiertas = [];
  String? _ultimoErrorScan;

  @override
  void initState() {
    super.initState();
    unawaited(_arrancar());
  }

  Future<void> _arrancar() async {
    try {
      _preset = await di.sl<LocalStorage>().getPrinterPreset();
    } catch (_) {}
    if (!mounted) return;
    await _escanearImpresoras(silencioso: true);
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _guardarImpresora() async {
    setState(() => _guardando = true);
    try {
      await di.sl<LocalStorage>().savePrinterPreset(_preset);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('printer_active_saved'.tr()), backgroundColor: SwsColors.success));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al guardar impresora: $e'), backgroundColor: SwsColors.danger));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _escanearImpresoras({bool silencioso = false}) async {
    setState(() { _escaneando = true; _ultimoErrorScan = null; });

    List<DiscoveredPrinter> printers;
    try {
      printers = await PrinterDiscovery.scan();
    } catch (e) {
      if (mounted) {
        setState(() { _escaneando = false; _ultimoErrorScan = 'Error al escanear: $e'; });
      }
      return;
    }
    if (!mounted) return;

    final guardadaExiste = printers.any((p) => p.name == _preset.nombreImpresora);
    var autoRegistrada = false;
    if (printers.isNotEmpty && !guardadaExiste) {
      final elegida = printers.firstWhere((p) => p.isDefault, orElse: () => printers.first);
      _preset = _preset.copyWith(nombreImpresora: elegida.name);
      autoRegistrada = true;
      try {
        await di.sl<LocalStorage>().savePrinterPreset(_preset);
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _impresorasDescubiertas = printers;
      _escaneando = false;
      if (printers.isEmpty) _ultimoErrorScan = 'printer_no_printers'.tr();
    });

    if (silencioso) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(printers.isEmpty ? 'printer_no_printers'.tr() : autoRegistrada ? 'printer_auto_registered'.tr(null, [_preset.nombreImpresora]) : 'printers_found'.tr(null, ['${printers.length}'])),
        backgroundColor: printers.isEmpty ? SwsColors.warning : SwsColors.info,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.print, color: SwsColors.accent),
                    const SizedBox(width: 8),
                    Text('printers_connected'.tr(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    OutlinedButton.icon(
                      icon: _escaneando ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.radar, size: 16),
                      label: Text(_escaneando ? 'Escaneando...' : 'Escanear Impresoras'),
                      onPressed: _escaneando ? null : _escanearImpresoras,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: ValueKey('impresoras_${_impresorasDescubiertas.map((p) => p.name).join('|')}_${_preset.nombreImpresora}'),
                  initialValue: _impresorasDescubiertas.any((p) => p.name == _preset.nombreImpresora)
                      ? _preset.nombreImpresora
                      : (_impresorasDescubiertas.isNotEmpty ? _impresorasDescubiertas.first.name : _sinImpresora),
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Impresora Activa Seleccionada', prefixIcon: Icon(Icons.print_outlined)),
                  items: [
                    ..._impresorasDescubiertas.map((p) => DropdownMenuItem(value: p.name, child: Text('${p.name} (${PrinterDiscovery.connectionTypeLabel(p.connection)})', overflow: TextOverflow.ellipsis))),
                    if (_impresorasDescubiertas.isEmpty)
                      DropdownMenuItem(value: _sinImpresora, child: Text('printer_none_detected'.tr(), style: const TextStyle(color: SwsColors.gray500, fontStyle: FontStyle.italic))),
                  ],
                  onChanged: (val) {
                    if (val != null && val != _sinImpresora) {
                      setState(() => _preset = _preset.copyWith(nombreImpresora: val));
                    }
                  },
                ),
                if (_ultimoErrorScan != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 16, color: SwsColors.danger),
                      const SizedBox(width: 6),
                      Expanded(child: Text(_ultimoErrorScan!, style: const TextStyle(fontSize: 12, color: SwsColors.danger))),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _preset.tipoImpresora,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: 'port_type_protocol'.tr(), prefixIcon: const Icon(Icons.settings_ethernet)),
                  items: [
                    DropdownMenuItem(value: 'POS_80', child: Text('thermal_80'.tr())),
                    DropdownMenuItem(value: 'POS_58', child: Text('thermal_58'.tr())),
                    DropdownMenuItem(value: 'SISTEMA_PDF', child: Text('system_driver'.tr())),
                    DropdownMenuItem(value: 'MATRIZ_PUNTO', child: Text('dot_matrix'.tr())),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _preset = _preset.copyWith(tipoImpresora: val));
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FilledButton.icon(
                      icon: _guardando ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.check),
                      label: Text(_guardando ? 'Guardando...' : 'Recordar Impresora Activa'),
                      style: FilledButton.styleFrom(backgroundColor: SwsColors.success),
                      onPressed: _guardando ? null : _guardarImpresora,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}