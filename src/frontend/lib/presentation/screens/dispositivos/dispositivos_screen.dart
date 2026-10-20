// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 25010 (Usabilidad/Accesibilidad)
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

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

  /// El escaneo SIEMPRE incluye básculas simuladas (BSDD local en
  /// `127.0.0.1:5555` y ptys virtuales): el usuario pidió que la báscula
  /// simulada aparezca automáticamente, sin botón manual de "agregar".
  @override
  void initState() {
    super.initState();
    // Cargar el registro y, en segundo plano, autodetectar y registrar las
    // básculas conectadas (reales o el simulador local) sin intervención.
    unawaited(_cargar().then((_) {
      if (mounted) unawaited(_escanear(silencioso: true));
    }));
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

  // ─── Escanear: descubre + auto-registra nuevas + recarga ──────────────

  /// Descubre básculas conectadas (reales o el simulador local en
  /// `127.0.0.1:5555`) y **registra automáticamente** las nuevas.
  ///
  /// [silencioso] evita los avisos de "escaneando"/"no se encontraron"
  /// cuando el escaneo se dispara solo al abrir la pantalla.
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
        ..showSnackBar(
          SnackBar(
            content: Text(_mensajeError(e)),
            backgroundColor: SwsColors.danger,
          ),
        );
      return;
    }

    if (encontradas.isEmpty) {
      if (!mounted || silencioso) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('no_scales_found'.tr())));
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
          'formato_trama': b['formato_trama'] ?? 'auto',
        });
        agregadas++;
      } catch (_) {
        // Si una falla, seguimos con las demás
      }
    }

    if (!mounted) return;
    await _cargar();
    if (!mounted) return;

    if (!silencioso) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'scales_detected_registered'
                  .tr(null, ['${encontradas.length}', '$agregadas']),
            ),
            backgroundColor: SwsColors.info,
          ),
        );
    } else if (agregadas > 0) {
      // Aviso discreto cuando la autodetección registró algo nuevo.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('scale_autodetected'.tr(null, ['$agregadas'])),
          backgroundColor: SwsColors.info,
          duration: const Duration(seconds: 3),
        ),
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

  // ─── Eliminar ──────────────────────────────────────────────────────────

  Future<void> _eliminar(Scale b) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.delete_outline, color: SwsColors.danger),
            const SizedBox(width: 10),
            Expanded(child: Text('delete_scale'.tr())),
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
        SnackBar(
          content: Text('scale_deleted'.tr()),
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
        onGuardado: () => unawaited(_escanear(silencioso: true)),
      ),
    );
  }

  Future<void> _probarRapido(Scale balanza) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text('testing_connection'.tr())),
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
      onNuevo: () => unawaited(_escanear()),
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: Text(context.tr('Dispositivos de Campo')),
            bottom: TabBar(
              tabs: [
                Tab(icon: const Icon(Icons.scale_outlined), text: context.tr('Básculas de Campo')),
                Tab(icon: const Icon(Icons.print_outlined), text: context.tr('Impresoras y Tickets')),
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
              TextButton.icon(
                key: const Key('dispositivos_escanear'),
                onPressed: _escanear,
                icon: const Icon(Icons.radar_outlined),
                label: Text(context.tr('detectar_balanzas')),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            key: const Key('dispositivos_agregar'),
            onPressed: _escanear,
            icon: const Icon(Icons.radar_outlined),
            label: Text(context.tr('detectar_balanzas')),
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
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.scale_outlined, size: 56, color: SwsColors.gray400),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            'No hay básculas registradas.\n'
            'Presione "Detectar" para buscarlas automáticamente.',
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
      child: Text(
        'simulated'.tr(),
        style: const TextStyle(
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
  late String _formatoTrama = widget.balanza.formatoTrama;
  late int _baudrate = widget.balanza.baudrate;
  late String _delimitador = widget.balanza.delimitador ?? 'lf';
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
      'formato_trama': _formatoTrama,
      'baudrate': _protocolo == 'serial' ? _baudrate : 9600,
      'delimitador': _delimitador,
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
        SnackBar(
          content: Text('connection_config_saved'.tr()),
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
              Text('connection'.tr(),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'tcp', label: Text('tcp'.tr())),
                  ButtonSegment(value: 'serial', label: Text('serial'.tr())),
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
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _formatoTrama,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'frame_format'.tr(),
                  prefixIcon: const Icon(Icons.code),
                ),
                items: [
                  DropdownMenuItem(
                      value: 'auto', child: Text('frame_auto'.tr())),
                  DropdownMenuItem(
                      value: 'json', child: Text('frame_json'.tr())),
                  DropdownMenuItem(
                      value: 'ascii', child: Text('frame_ascii'.tr())),
                ],
                onChanged: (val) =>
                    setState(() => _formatoTrama = val ?? 'auto'),
              ),
              if (_protocolo == 'serial') ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: _baudrate,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'baudrate'.tr(),
                    prefixIcon: const Icon(Icons.speed),
                  ),
                  items: const [
                    DropdownMenuItem(value: 1200, child: Text('1200')),
                    DropdownMenuItem(value: 4800, child: Text('4800')),
                    DropdownMenuItem(value: 9600, child: Text('9600')),
                    DropdownMenuItem(value: 19200, child: Text('19200')),
                    DropdownMenuItem(value: 38400, child: Text('38400')),
                    DropdownMenuItem(value: 57600, child: Text('57600')),
                    DropdownMenuItem(value: 115200, child: Text('115200')),
                  ],
                  onChanged: (val) =>
                      setState(() => _baudrate = val ?? 9600),
                ),
              ],
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _delimitador,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'frame_delimiter'.tr(),
                  prefixIcon: const Icon(Icons.format_align_left),
                ),
                items: [
                  DropdownMenuItem(
                      value: 'lf', child: Text('delimiter_lf'.tr())),
                  DropdownMenuItem(
                      value: 'cr', child: Text('delimiter_cr'.tr())),
                  DropdownMenuItem(
                      value: 'crlf', child: Text('delimiter_crlf'.tr())),
                  DropdownMenuItem(
                      value: 'stx_etx', child: Text('delimiter_stx_etx'.tr())),
                ],
                onChanged: (val) =>
                    setState(() => _delimitador = val ?? 'lf'),
              ),
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
  /// Valor centinela del desplegable cuando el escaneo no encontró ninguna
  /// impresora real. Es un valor de **lógica**: nunca se traduce ni se muestra
  /// (la etiqueta visible es `printer_none_detected`).
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

  /// Carga la impresora recordada y **detecta automáticamente** las
  /// impresoras reales instaladas en el equipo (las virtuales se descartan).
  ///
  /// El spinner se mantiene hasta terminar el primer escaneo para no
  /// mostrar la lista vacía durante unos milisegundos.
  Future<void> _arrancar() async {
    try {
      _preset = await di.sl<LocalStorage>().getPrinterPreset();
    } catch (_) {
      // Sin preset guardado se usa el valor por defecto.
    }
    if (!mounted) return;
    await _escanearImpresoras(silencioso: true);
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _guardarImpresora() async {
    setState(() => _guardando = true);
    try {
      await di.sl<LocalStorage>().savePrinterPreset(_preset);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('printer_active_saved'.tr()),
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

  /// Escanea las impresoras **reales** del sistema (Windows/CUPS) y
  /// descarta las virtuales (PDF, XPS…).
  ///
  /// Si la impresora recordada ya no está instalada, adopta automáticamente
  /// la detectada como predeterminada del sistema y la **guarda** para
  /// dejarla registrada como reconocida.
  Future<void> _escanearImpresoras({bool silencioso = false}) async {
    setState(() {
      _escaneando = true;
      _ultimoErrorScan = null;
    });

    List<DiscoveredPrinter> printers;
    try {
      printers = await PrinterDiscovery.scan();
    } catch (e) {
      if (mounted) {
        setState(() {
          _escaneando = false;
          _ultimoErrorScan = 'Error al escanear: $e';
        });
      }
      return;
    }
    if (!mounted) return;

    // ¿La impresora guardada sigue instalada en este equipo?
    final guardadaExiste = printers.any((p) => p.name == _preset.nombreImpresora);
    var autoRegistrada = false;
    if (printers.isNotEmpty && !guardadaExiste) {
      final elegida =
          printers.firstWhere((p) => p.isDefault, orElse: () => printers.first);
      _preset = _preset.copyWith(nombreImpresora: elegida.name);
      autoRegistrada = true;
      try {
        await di.sl<LocalStorage>().savePrinterPreset(_preset);
      } catch (_) {
        // El guardado no debe romper la UI; el usuario puede reintentarlo.
      }
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
        content: Text(
          printers.isEmpty
              ? 'printer_no_printers'.tr()
              : autoRegistrada
                  ? 'printer_auto_registered'.tr(null, [_preset.nombreImpresora])
                  : 'printers_found'.tr(null, ['${printers.length}']),
        ),
        backgroundColor: printers.isEmpty ? SwsColors.warning : SwsColors.info,
      ),
    );
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
                    Text(
                      'printers_connected'.tr(),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                  // La clave cambia con el resultado del escaneo: fuerza la
                  // recreación del campo para que `initialValue` refleje las
                  // impresoras recién descubiertas (si la activa guardada no
                  // está en la lista, cae a la primera real detectada).
                  key: ValueKey(
                    'impresoras_${_impresorasDescubiertas.map((p) => p.name).join('|')}_'
                    '${_preset.nombreImpresora}',
                  ),
                  initialValue: _impresorasDescubiertas
                          .any((p) => p.name == _preset.nombreImpresora)
                      ? _preset.nombreImpresora
                      : (_impresorasDescubiertas.isNotEmpty
                          ? _impresorasDescubiertas.first.name
                          : _sinImpresora),
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Impresora Activa Seleccionada',
                    prefixIcon: Icon(Icons.print_outlined),
                  ),
                  items: [
                    ..._impresorasDescubiertas.map((p) => DropdownMenuItem(
                          value: p.name,
                          child: Text(
                            '${p.name} (${PrinterDiscovery.connectionTypeLabel(p.connection)})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        )),
                    if (_impresorasDescubiertas.isEmpty)
                      DropdownMenuItem(
                        value: _sinImpresora,
                        child: Text('printer_none_detected'.tr(),
                            style: const TextStyle(
                                color: SwsColors.gray500, fontStyle: FontStyle.italic)),
                      ),
                  ],
                  onChanged: (val) {
                    if (val != null && val != _sinImpresora) {
                      setState(() => _preset = _preset.copyWith(nombreImpresora: val));
                    }
                  },
                ),
                // Aviso cuando el escaneo no encontró NINGUNA impresora real
                // (en lugar de mostrar una lista ficticia).
                if (_ultimoErrorScan != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          size: 16, color: SwsColors.danger),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _ultimoErrorScan!,
                          style: const TextStyle(
                              fontSize: 12, color: SwsColors.danger),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _preset.tipoImpresora,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'port_type_protocol'.tr(),
                    prefixIcon: const Icon(Icons.settings_ethernet),
                  ),
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