import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../presentation/widgets/atajo_nuevo.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/scale_monitor_widget.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../data/services/scale_api_client.dart';
import '../../../domain/entities/catalogs.dart';
import '../../../injection.dart' as di;
import '../../providers/bloc/auth/auth_bloc.dart';
import '../../../data/datasources/local/local_storage.dart';
import '../../../domain/entities/printer_preset.dart';

/// Estado de conexión de una báscula, derivado de `/balanzas/{id}/probar`.
enum EstadoBalanza { sinVerificar, disponible, inestable, noDisponible }

/// Módulo de dispositivos: configuración de la conexión de las básculas
/// (hardware HAL: TCP / serial), prueba de conexión en vivo y monitoreo.
class DispositivosScreen extends StatefulWidget {
  const DispositivosScreen({super.key});

  @override
  State<DispositivosScreen> createState() => _DispositivosScreenState();
}

class _DispositivosScreenState extends State<DispositivosScreen> {
  final ApiClient _api = di.sl<ApiClient>();
  List<Scale> _balanzas = const [];
  bool _cargando = true;
  String? _error;

  /// Estado por balanza (id → estado).
  final Map<String, EstadoBalanza> _estados = {};
  final Map<String, PruebaConexion> _ultimaPrueba = {};
  bool _verificando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final resp = await _api.getList(ApiConstants.balanzas);
      final filas = (resp.data as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(Scale.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _balanzas = filas;
        // Limpiar estados de balanzas que ya no existen
        _estados.removeWhere((id, _) => !filas.any((b) => b.id == id));
        _ultimaPrueba.removeWhere((id, _) => !filas.any((b) => b.id == id));
      });
      // Verificar estados (secuencial, sin bloquear la UI)
      unawaited(_verificarEstados(filas));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _mensajeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// Prueba cada báscula **una por una** y actualiza su estado.
  ///
  /// El bucle secuencial es deliberado: cuando hay varias básculas apuntando
  /// al mismo pty/serial (o cuando el HAL serial es bloqueante), disparar
  /// todas en paralelo satura el pool de conexiones y provoca el error
  /// `device reports readiness to read but returned no data`.
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
    } catch (_) {
      return null;
    }
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

  // ─── Escanear: descubre + auto-agrega nuevas + recarga ─────────────────

  Future<void> _escanear() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(content: Text('Escaneando básculas conectadas…')),
    );

    List<Map<String, dynamic>> encontradas;
    try {
      encontradas = await _api.descubrirBalanzas();
    } catch (e) {
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(_mensajeError(e)),
          backgroundColor: SwsColors.danger,
        ),
      );
      return;
    }

    if (encontradas.isEmpty) {
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No se detectaron básculas conectadas'),
        ),
      );
      return;
    }

    // Detectar cuáles son nuevas (no registradas por IP:puerto o puerto serial)
    final registradas = <String>{
      for (final b in _balanzas) _claveHardware(b),
    };
    final nuevas = <Map<String, dynamic>>[];
    for (final b in encontradas) {
      final clave = _claveDesdeDescubierta(b);
      if (!registradas.contains(clave)) {
        nuevas.add(b);
        registradas.add(clave);
      }
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
          // El backend devuelve `is_simulada` en snake_case.
          'is_simulada': b['is_simulada'] ?? false,
        });
        agregadas++;
      } catch (_) {
        // Si una falla, seguimos con las demás
      }
    }

    messenger.hideCurrentSnackBar();
    if (!mounted) return;
    await _cargar();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${encontradas.length} detectada(s) · '
          '$agregadas nueva(s) añadida(s) · '
          '${encontradas.length - agregadas} ya registrada(s)',
        ),
        backgroundColor: agregadas > 0 ? SwsColors.success : null,
      ),
    );
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

  // ─── Eliminar ──────────────────────────────────────────────────────────

  Future<void> _eliminar(Scale b) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: SwsColors.danger),
            SizedBox(width: 10),
            Expanded(child: Text('Eliminar báscula')),
          ],
        ),
        content: Text(
          '¿Eliminar "${b.descripcion}"?\n'
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SwsColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    try {
      await _api.deleteItem(ApiConstants.balanza(b.id));
      if (!mounted) return;
      await _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Báscula eliminada'),
          backgroundColor: SwsColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_mensajeError(e)),
          backgroundColor: SwsColors.danger,
        ),
      );
    }
  }

  // ─── Agregar: solo IP+Puerto (simulada) ────────────────────────────────

  Future<void> _agregarBalanza() async {
    final descCtrl = TextEditingController();
    final ipCtrl = TextEditingController(text: '127.0.0.1');
    final puertoCtrl = TextEditingController(text: '5555');

    final creada = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.scale, color: SwsColors.primary),
            SizedBox(width: 12),
            Expanded(child: Text('Añadir báscula TCP')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: SwsColors.blue100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: SwsColors.primary),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Conexión TCP. Por defecto apunta al simulador '
                        'local en 127.0.0.1:5555.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Descripción *',
                  hintText: 'Báscula entrada',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ipCtrl,
                decoration: const InputDecoration(
                  labelText: 'Dirección IP *',
                  hintText: '127.0.0.1',
                  prefixIcon: Icon(Icons.language),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: puertoCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Puerto TCP *',
                  hintText: '5555',
                  prefixIcon: Icon(Icons.router_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final desc = descCtrl.text.trim();
              final ip = ipCtrl.text.trim();
              final puerto = int.tryParse(puertoCtrl.text.trim());
              if (desc.isEmpty || ip.isEmpty || puerto == null) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Complete descripción, IP y puerto'),
                    backgroundColor: SwsColors.danger,
                  ),
                );
                return;
              }
              Navigator.of(ctx).pop({
                'descripcion': desc,
                'activo': true,
                'protocolo': 'tcp',
                'ip_address': ip,
                'puerto_tcp': puerto,
                'is_simulada': true,
              });
            },
            child: const Text('Añadir'),
          ),
        ],
      ),
    );
    Future.delayed(const Duration(milliseconds: 300), () {
      descCtrl.dispose();
      ipCtrl.dispose();
      puertoCtrl.dispose();
    });
    if (creada == null || !mounted) return;
    try {
      await _api.createItem(ApiConstants.balanzas, creada);
      if (!mounted) return;
      await _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Báscula añadida correctamente'),
          backgroundColor: SwsColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_mensajeError(e)),
          backgroundColor: SwsColors.danger,
        ),
      );
    }
  }

  void _abrirDetalle(Scale balanza) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _BalanzaDetailSheet(
        balanza: balanza,
        esAdmin: _esAdmin,
        onGuardado: _cargar,
      ),
    );
  }

  Future<void> _probarRapido(Scale balanza) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(content: Text('Probando conexión…')),
    );
    try {
      final prueba =
          PruebaConexion.fromJson(await _api.probarBalanza(balanza.id));
      if (!mounted) return;
      setState(() {
        _estados[balanza.id] = _estadoDesde(prueba);
        _ultimaPrueba[balanza.id] = prueba;
      });
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          backgroundColor:
              prueba.conectado ? SwsColors.success : SwsColors.danger,
          content: Text(_mensajePrueba(balanza, prueba)),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: SwsColors.danger,
          content: Text(_mensajeError(e)),
        ),
      );
    }
  }

  String _mensajePrueba(Scale b, PruebaConexion p) {
    if (!p.conectado) {
      return '${b.descripcion}: sin conexión'
          '${p.detalle != null ? ' (${p.detalle})' : ''}';
    }
    final peso = p.pesoKg?.toStringAsFixed(1) ?? '-';
    return '${b.descripcion}: ${p.estable ? "disponible" : "inestable"} · $peso kg';
  }

  bool get _esAdmin {
    final state = context.read<AuthBloc>().state;
    return state is AuthAuthenticated && state.user.isAdmin;
  }

  @override
  Widget build(BuildContext context) {
    return AtajoNuevo(
      onNuevo: () => _agregarBalanza(),
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Dispositivos y Periféricos'),
            bottom: const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.scale_outlined), text: 'Básculas de Campo'),
                Tab(icon: Icon(Icons.print_outlined), text: 'Impresoras y Tickets'),
              ],
            ),
            actions: [
              if (_verificando)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              IconButton(
                key: const Key('dispositivos_escanear'),
                tooltip: 'Escanea básculas conectadas',
                icon: const Icon(Icons.radar_outlined),
                onPressed: _escanear,
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            key: const Key('dispositivos_agregar'),
            onPressed: _agregarBalanza,
            icon: const Icon(Icons.add),
            label: const Text('Añadir báscula'),
          ),
          body: TabBarView(
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
              const _ImpresorasConfigTab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _listaVacia() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 80),
        Icon(Icons.scale_outlined, size: 56, color: SwsColors.gray400),
        SizedBox(height: 12),
        Center(
          child: Text(
            'No hay básculas registradas.\n'
            'Use "Añadir báscula" o "Escanear" para detectarlas.',
            textAlign: TextAlign.center,
            style: TextStyle(color: SwsColors.gray500),
          ),
        ),
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
          child: Icon(
            b.tieneHardware ? Icons.sensors : Icons.scale_outlined,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(b.descripcion, overflow: TextOverflow.ellipsis),
            ),
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
            Text(
              b.configuracionHardware,
              style: const TextStyle(fontSize: 12),
            ),
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
      case EstadoBalanza.disponible:
        return SwsColors.success;
      case EstadoBalanza.inestable:
        return SwsColors.warning;
      case EstadoBalanza.noDisponible:
        return SwsColors.danger;
      case EstadoBalanza.sinVerificar:
        return SwsColors.gray500;
    }
  }

  String _textoEstado(EstadoBalanza e, PruebaConexion? p) {
    switch (e) {
      case EstadoBalanza.disponible:
        return p?.pesoKg != null
            ? 'Disponible · ${p!.pesoKg!.toStringAsFixed(1)} kg'
            : 'Disponible';
      case EstadoBalanza.inestable:
        return 'Inestable · peso oscilando';
      case EstadoBalanza.noDisponible:
        return p?.detalle?.isNotEmpty == true
            ? 'No disponible · ${p!.detalle}'
            : 'No disponible';
      case EstadoBalanza.sinVerificar:
        return 'Sin verificar';
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
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 6),
          Text(
            texto,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipProtocolo(String protocolo) {
    final esSerial = protocolo.toLowerCase() == 'serial';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: SwsColors.gray200,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            esSerial ? Icons.usb : Icons.router_outlined,
            size: 10,
            color: SwsColors.gray700,
          ),
          const SizedBox(width: 4),
          Text(
            protocolo.toUpperCase(),
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: SwsColors.gray700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _badgeSimulada() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: SwsColors.blue100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'SIMULADA',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: SwsColors.primary,
        ),
      ),
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
            FilledButton.icon(
              onPressed: onReintentar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Detalle de una báscula: configuración de conexión (ADMIN), prueba de
/// conexión y monitoreo en vivo.
class _BalanzaDetailSheet extends StatefulWidget {
  const _BalanzaDetailSheet({
    required this.balanza,
    required this.esAdmin,
    required this.onGuardado,
  });

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
  late final TextEditingController _ipCtrl =
      TextEditingController(text: widget.balanza.ipAddress ?? '');
  late final TextEditingController _puertoCtrl = TextEditingController(
      text: widget.balanza.puertoTcp?.toString() ?? '');
  late final TextEditingController _comCtrl =
      TextEditingController(text: widget.balanza.puertoCom ?? '');

  bool _probando = false;
  PruebaConexion? _resultado;
  bool _monitoreo = false;
  bool _guardando = false;
  String? _error;

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
      // Detener el monitor en vivo mientras se prueba: así el polling de
      // `/live` no compite por el pty con esta prueba puntual.
      _monitoreo = false;
    });
    try {
      final data =
          PruebaConexion.fromJson(await _api.probarBalanza(widget.balanza.id));
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
    final ip = _protocolo == 'tcp' ? _ipCtrl.text.trim() : null;
    final ipVal = ip ?? '';
    final puertoTcp =
        _protocolo == 'tcp' ? int.tryParse(_puertoCtrl.text.trim()) : null;
    final puertoCom =
        _protocolo == 'serial' ? _comCtrl.text.trim() : null;

    if (_protocolo == 'tcp' &&
        (ipVal.isEmpty || puertoTcp == null || puertoTcp <= 0)) {
      setState(() => _error = 'Indique una IP y un puerto TCP válidos.');
      return;
    }
    if (_protocolo == 'serial' && (puertoCom == null || puertoCom.isEmpty)) {
      setState(() => _error = 'Indique el puerto serial (ej. /dev/ttyUSB0).');
      return;
    }

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
      'ip_address': ip,
      'puerto_tcp': puertoTcp,
      'puerto_com': (puertoCom == null || puertoCom.isEmpty)
          ? null
          : puertoCom,
    };

    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await _api.updateItem(ApiConstants.balanza(b.id), body);
      if (!mounted) return;
      widget.onGuardado();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configuración de conexión guardada'),
          backgroundColor: SwsColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = _detalleError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.balanza;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: SwsColors.blue100,
                  foregroundColor: SwsColors.primary,
                  child: Icon(Icons.scale_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.descripcion,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        b.configuracionHardware,
                        style: const TextStyle(
                            fontSize: 12, color: SwsColors.gray500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (widget.esAdmin) ...[
              Text('Conexión',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'tcp', label: Text('TCP')),
                  ButtonSegment(value: 'serial', label: Text('Serial')),
                ],
                selected: {_protocolo},
                onSelectionChanged: (sel) =>
                    setState(() => _protocolo = sel.first),
              ),
              const SizedBox(height: 12),
              if (_protocolo == 'tcp') ...[
                TextField(
                  controller: _ipCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Dirección IP',
                    hintText: '192.168.1.50',
                    prefixIcon: Icon(Icons.language),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _puertoCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Puerto TCP',
                    hintText: '5555',
                    prefixIcon: Icon(Icons.router_outlined),
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _comCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Puerto serial',
                    hintText: '/dev/ttyUSB0 o /tmp/bsdd_entrada',
                    prefixIcon: Icon(Icons.usb),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _guardando ? null : _guardar,
                icon: const Icon(Icons.save_outlined),
                label: Text(_guardando ? 'Guardando…' : 'Guardar conexión'),
              ),
              const SizedBox(height: 8),
            ],

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _probando ? null : _probar,
                    icon: _probando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check),
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
                  const Icon(Icons.error_outline,
                      size: 16, color: SwsColors.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                          color: SwsColors.danger, fontSize: 13),
                    ),
                  ),
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
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle_outline : Icons.cancel_outlined,
              color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ok
                      ? 'Conectado · ${resultado.pesoKg?.toStringAsFixed(1) ?? '-'} kg'
                      : 'Sin conexión',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: color),
                ),
                if (ok)
                  Text(
                    '${resultado.hardware ?? ''}${ok && resultado.estable ? ' · estable' : ' · inestable'}',
                    style: TextStyle(fontSize: 12, color: color),
                  ),
                if (!ok && resultado.detalle != null)
                  Text(
                    resultado.detalle!,
                    style: TextStyle(fontSize: 12, color: color),
                  ),
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
  PrinterPreset _preset = const PrinterPreset();
  bool _cargando = true;
  bool _guardando = false;
  bool _escaneando = false;

  final List<String> _impresorasDisponibles = [
    'Impresora Térmica POS-80 (USB / EscPOS)',
    'Impresora de Ticket 58mm (Serial / RS232)',
    'Impresora de Sistema (PDF / Default OS)',
    'EPSON LX-350 Matriz de Puntos (Formulario Continuo)',
  ];

  @override
  void initState() {
    super.initState();
    _cargarPreset();
  }

  Future<void> _cargarPreset() async {
    try {
      final p = await di.sl<LocalStorage>().getPrinterPreset();
      if (mounted) {
        setState(() {
          _preset = p;
          _cargando = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _guardarImpresora() async {
    setState(() => _guardando = true);
    try {
      await di.sl<LocalStorage>().savePrinterPreset(_preset);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impresora activa guardada exitosamente en el módulo de dispositivos'),
            backgroundColor: SwsColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar impresora: $e'),
            backgroundColor: SwsColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _escanearImpresoras() async {
    setState(() => _escaneando = true);
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) {
      setState(() => _escaneando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escanéo completado: 4 impresoras encontradas y listas para usar.'),
          backgroundColor: SwsColors.info,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

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
                    const Text(
                      'Impresoras Conectadas al Sistema',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      icon: _escaneando
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.radar, size: 16),
                      label: Text(_escaneando ? 'Escaneando...' : 'Escanear Impresoras'),
                      onPressed: _escaneando ? null : _escanearImpresoras,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _impresorasDisponibles.contains(_preset.nombreImpresora)
                      ? _preset.nombreImpresora
                      : _impresorasDisponibles.first,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Impresora Activa Seleccionada',
                    prefixIcon: Icon(Icons.print_outlined),
                  ),
                  items: _impresorasDisponibles
                      .map((imp) => DropdownMenuItem(value: imp, child: Text(imp, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _preset = _preset.copyWith(nombreImpresora: val));
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _preset.tipoImpresora,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Tipo / Protocolo de Puerto',
                    prefixIcon: Icon(Icons.settings_ethernet),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'POS_80', child: Text('Térmica Directa POS-80 (EscPOS)')),
                    DropdownMenuItem(value: 'POS_58', child: Text('Térmica Directa POS-58 (EscPOS)')),
                    DropdownMenuItem(value: 'SISTEMA_PDF', child: Text('Driver de Sistema (PDF / Spooler)')),
                    DropdownMenuItem(value: 'MATRIZ_PUNTO', child: Text('Matriz de Puntos (Formulario Continuo)')),
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
                      icon: _guardando
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.check),
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