import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/scale_monitor_widget.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../data/services/scale_api_client.dart';
import '../../../domain/entities/catalogs.dart';
import '../../../injection.dart' as di;
import '../../providers/bloc/auth/auth_bloc.dart';

/// Módulo de dispositivos: configuración de la conexión de las básculas
/// (hardware HAL: TCP / serial) y prueba de conexión en vivo.
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
      setState(() => _balanzas = filas);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _mensajeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
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
      final data =
          PruebaConexion.fromJson(await _api.probarBalanza(balanza.id));
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: data.conectado ? SwsColors.success : SwsColors.danger,
          content: Text(
            data.conectado
                ? '${balanza.descripcion}: conectado · ${data.pesoKg?.toStringAsFixed(1) ?? '-'} kg'
                : '${balanza.descripcion}: sin lectura (${data.detalle ?? 'revisar configuración'})',
          ),
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

  bool get _esAdmin {
    final state = context.read<AuthBloc>().state;
    return state is AuthAuthenticated && state.user.isAdmin;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dispositivos')),
      body: _cargando
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
            'No hay básculas registradas.\nCree una en Inventario → Balanzas.',
            textAlign: TextAlign.center,
            style: TextStyle(color: SwsColors.gray500),
          ),
        ),
      ],
    );
  }

  Widget _tarjeta(Scale b) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: SwsColors.blue100,
          foregroundColor: SwsColors.primary,
          child: Icon(
            b.tieneHardware ? Icons.sensors : Icons.scale_outlined,
            size: 20,
          ),
        ),
        title: Text(b.descripcion),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              b.configuracionHardware,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(
                  b.activo ? 'Activa' : 'Inactiva',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: b.activo ? SwsColors.success : SwsColors.danger,
                  ),
                ),
                if (b.codigo != null) ...[
                  const Text(' · ', style: TextStyle(fontSize: 11)),
                  Text(
                    'Código ${b.codigo}',
                    style: const TextStyle(fontSize: 11, color: SwsColors.gray500),
                  ),
                ],
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
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => _abrirDetalle(b),
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
                    hintText: '/dev/ttyUSB0',
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