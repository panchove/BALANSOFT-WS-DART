import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/i18n/translations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../domain/entities/catalogs.dart';
import '../../../injection.dart' as di;

class BarrerasConfigTab extends StatefulWidget {
  const BarrerasConfigTab({super.key});

  @override
  State<BarrerasConfigTab> createState() => _BarrerasConfigTabState();
}

class _BarrerasConfigTabState extends State<BarrerasConfigTab> {
  final _api = di.sl<ApiClient>();
  List<Barrera> _items = [];
  bool _cargando = true;
  String _filtro = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final resp = await _api.getList(ApiConstants.barreras);
      final data = resp.data as List? ?? [];
      _items = data.map((e) => Barrera.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      _items = [];
    }
    if (mounted) setState(() => _cargando = false);
  }

  void _abrirDetalle(Barrera b) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BarreraDetailSheet(barrera: b, onGuardado: _cargar),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _items.where((e) {
      if (_filtro.isEmpty) return true;
      final f = _filtro.toLowerCase();
      return e.descripcion.toLowerCase().contains(f) ||
          (e.codigo ?? '').toLowerCase().contains(f) ||
          (e.puertoCom ?? '').toLowerCase().contains(f) ||
          (e.ipAddress ?? '').toLowerCase().contains(f);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: context.tr('buscar'),
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onChanged: (v) => setState(() => _filtro = v),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _cargar,
                icon: const Icon(Icons.refresh),
                label: Text(context.tr('refrescar')),
              ),
            ],
          ),
        ),
        Expanded(
          child: _cargando
              ? const Center(child: CircularProgressIndicator())
              : filtrados.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.door_sliding_outlined, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(context.tr('Sin barreras configuradas'), style: TextStyle(color: Colors.grey.shade600)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: filtrados.length,
                      itemBuilder: (context, i) {
                        final item = filtrados[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: item.activo ? SwsColors.primary.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.12),
                              child: Icon(Icons.door_sliding_outlined, color: item.activo ? SwsColors.primary : Colors.grey),
                            ),
                            title: Text(item.descripcion),
                            subtitle: Text('${item.configuracionHardware} • ${item.ubicacionLegible}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _abrirDetalle(item),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _BarreraDetailSheet extends StatefulWidget {
  const _BarreraDetailSheet({required this.barrera, required this.onGuardado});
  final Barrera barrera;
  final VoidCallback onGuardado;

  @override
  State<_BarreraDetailSheet> createState() => _BarreraDetailSheetState();
}

class _BarreraDetailSheetState extends State<_BarreraDetailSheet> {
  final _api = di.sl<ApiClient>();

  late final String _protocolo = widget.barrera.protocolo;
  late String _ubicacion = widget.barrera.ubicacion ?? 'ambos';
  late final TextEditingController _ipCtrl = TextEditingController(text: widget.barrera.ipAddress ?? '');
  late final TextEditingController _puertoCtrl = TextEditingController(text: widget.barrera.puertoTcp?.toString() ?? '8082');
  late final TextEditingController _comCtrl = TextEditingController(text: widget.barrera.puertoCom ?? '');
  late final int _baudrate = widget.barrera.baudrate;
  late int _tiempo = widget.barrera.tiempoEsperaSegundos;
  late bool _auto = widget.barrera.controlAutomatico;

  bool _guardando = false;
  bool _probando = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _ipCtrl.dispose();
    _puertoCtrl.dispose();
    _comCtrl.dispose();
    super.dispose();
  }

  String _detalleError(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['detail'] != null) return '${data['detail']}';
    }
    return 'No se pudo completar la acción.';
  }

  /// Campo de SOLO LECTURA: muestra el canal de conexión (identidad del
  /// dispositivo) sin permitir edición.
  Widget _campoLectura(
    BuildContext context, {
    required String etiqueta,
    required String valor,
    required IconData icono,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: etiqueta,
        prefixIcon: Icon(icono),
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        suffixIcon: Tooltip(
          message: 'No editable: identifica al dispositivo',
          child: Icon(Icons.lock_outline, size: 16, color: scheme.outline),
        ),
      ),
      child: Text(
        valor,
        style: TextStyle(
          fontSize: 16,
          color: scheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  Future<void> _guardar() async {
    if (_protocolo == 'http') {
      if (_ipCtrl.text.trim().isEmpty || int.tryParse(_puertoCtrl.text.trim()) == null) {
        setState(() => _error = 'Indique IP y puerto válidos.');
        return;
      }
    } else {
      if (_comCtrl.text.trim().isEmpty) {
        setState(() => _error = 'Indique puerto serie/USB.');
        return;
      }
    }

    setState(() {
      _guardando = true;
      _error = null;
      _info = null;
    });

    try {
      final body = <String, dynamic>{
        'descripcion': widget.barrera.descripcion,
        'codigo': widget.barrera.codigo,
        'activo': widget.barrera.activo,
        'protocolo': _protocolo,
        'ip_address': _protocolo == 'http' ? _ipCtrl.text.trim() : null,
        'puerto_tcp': _protocolo == 'http' ? int.tryParse(_puertoCtrl.text.trim()) : null,
        'puerto_com': _protocolo == 'serial' ? _comCtrl.text.trim() : null,
        'baudrate': _protocolo == 'serial' ? _baudrate : 9600,
        'ubicacion': _ubicacion,
        'control_automatico': _auto,
        'tiempo_espera_segundos': _tiempo,
      };
      await _api.updateItem(ApiConstants.barrera(widget.barrera.id), body);
      if (!mounted) return;
      widget.onGuardado();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('connection_config_saved')), backgroundColor: SwsColors.success));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _detalleError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _comando(String action) async {
    setState(() {
      _probando = true;
      _error = null;
      _info = null;
    });
    try {
      await _api.comandoBarrera(widget.barrera.id, action);
      if (!mounted) return;
      setState(() => _info = action == 'open' ? 'Comando: ABRIR enviado' : 'Comando: CERRAR enviado');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _detalleError(e));
    } finally {
      if (mounted) setState(() => _probando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).size;
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: media.height * 0.9,
      decoration: BoxDecoration(color: colorScheme.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
            child: Row(
              children: [
                Icon(Icons.door_sliding_outlined, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(child: Text(widget.barrera.descripcion, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colorScheme.onSurface))),
                IconButton(onPressed: () => Navigator.of(context).pop(), icon: Icon(Icons.close, color: colorScheme.onSurface)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ─── Conexión: identidad del dispositivo (NO editable) ──
                  const Text('Conexión (identidad del dispositivo)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 4),
                  const Text(
                    'El canal identifica a la barrera. Si aparece con esa entrada es porque así fue detectada y no se modifica aquí. Para cambiarla, elimínela y vuelva a detectarla.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 10),
                  _campoLectura(context, etiqueta: 'Protocolo', valor: _protocolo == 'http' ? 'HTTP / Red' : 'USB / Serie', icono: _protocolo == 'http' ? Icons.wifi : Icons.usb),
                  const SizedBox(height: 10),
                  if (_protocolo == 'http') ...[
                    _campoLectura(context, etiqueta: 'Dirección IP', valor: widget.barrera.ipAddress ?? '—', icono: Icons.language),
                    const SizedBox(height: 10),
                    _campoLectura(context, etiqueta: 'Puerto', valor: '${widget.barrera.puertoTcp ?? 8080}', icono: Icons.router_outlined),
                  ] else ...[
                    _campoLectura(context, etiqueta: 'Puerto', valor: widget.barrera.puertoCom ?? '—', icono: Icons.usb),
                    const SizedBox(height: 10),
                    _campoLectura(context, etiqueta: 'Velocidad (baudrate)', valor: '$_baudrate', icono: Icons.speed),
                  ],
                  const SizedBox(height: 18),
                  const Text('Ubicación / Acceso', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'entrada', label: Text('Entrada')),
                      ButtonSegment(value: 'salida', label: Text('Salida')),
                      ButtonSegment(value: 'ambos', label: Text('Ambos')),
                    ],
                    selected: {_ubicacion},
                    onSelectionChanged: (s) => setState(() => _ubicacion = s.first),
                  ),
                  const SizedBox(height: 18),
                  Material(
                    color: Colors.transparent,
                    child: SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Control automático'), subtitle: const Text('Abrir/cerrar según flujo de pesaje'), value: _auto, onChanged: (v) => setState(() => _auto = v)),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: 'Tiempo abierta (segundos)', hintText: '$_tiempo'),
                    onChanged: (v) => setState(() => _tiempo = int.tryParse(v) ?? _tiempo),
                  ),
                  const SizedBox(height: 22),
                  const Text('Comandos manuales', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: FilledButton.icon(onPressed: _probando ? null : () => _comando('open'), icon: const Icon(Icons.lock_open), label: const Text('ABRIR'))),
                      const SizedBox(width: 12),
                      Expanded(child: FilledButton.tonalIcon(onPressed: _probando ? null : () => _comando('close'), icon: const Icon(Icons.lock), label: const Text('CERRAR'))),
                    ],
                  ),
                  if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: const TextStyle(color: Colors.red))],
                  if (_info != null) ...[const SizedBox(height: 12), Text(_info!, style: const TextStyle(color: SwsColors.success))],
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: _guardando ? null : () => Navigator.of(context).pop(), child: Text(context.tr('cancelar')))),
                const SizedBox(width: 12),
                Expanded(child: FilledButton(onPressed: _guardando ? null : _guardar, child: _guardando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(context.tr('guardar')))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
