import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/i18n/translations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../domain/entities/catalogs.dart';
import '../../../injection.dart' as di;

class SemaforosConfigTab extends StatefulWidget {
  const SemaforosConfigTab({super.key});

  @override
  State<SemaforosConfigTab> createState() => _SemaforosConfigTabState();
}

class _SemaforosConfigTabState extends State<SemaforosConfigTab> {
  final _api = di.sl<ApiClient>();
  List<Semaforo> _items = [];
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
      final resp = await _api.getList(ApiConstants.semaforos);
      final data = resp.data as List? ?? [];
      _items = data
          .map((e) => Semaforo.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _items = [];
    }
    if (mounted) setState(() => _cargando = false);
  }

  void _abrirDetalle(Semaforo s) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SemaforoDetailSheet(
        semaforo: s,
        onGuardado: _cargar,
      ),
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
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
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
                          Icon(Icons.traffic_outlined,
                              size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(context.tr('Sin semáforos configurados'),
                              style: TextStyle(color: Colors.grey.shade600)),
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
                              backgroundColor: item.activo
                                  ? SwsColors.success.withValues(alpha: 0.12)
                                  : Colors.grey.withValues(alpha: 0.12),
                              child: Icon(
                                Icons.traffic_outlined,
                                color: item.activo
                                    ? SwsColors.success
                                    : Colors.grey,
                              ),
                            ),
                            title: Text(item.descripcion),
                            subtitle: Text(item.configuracionHardware),
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

class _SemaforoDetailSheet extends StatefulWidget {
  const _SemaforoDetailSheet({
    required this.semaforo,
    required this.onGuardado,
  });

  final Semaforo semaforo;
  final VoidCallback onGuardado;

  @override
  State<_SemaforoDetailSheet> createState() => _SemaforoDetailSheetState();
}

class _SemaforoDetailSheetState extends State<_SemaforoDetailSheet> {
  final _api = di.sl<ApiClient>();

  late String _protocolo = widget.semaforo.protocolo; // http | serial
  late final TextEditingController _ipCtrl =
      TextEditingController(text: widget.semaforo.ipAddress ?? '');
  late final TextEditingController _puertoCtrl = TextEditingController(
      text: widget.semaforo.puertoTcp?.toString() ?? '8080');
  late final TextEditingController _comCtrl =
      TextEditingController(text: widget.semaforo.puertoCom ?? '');
  late int _baudrate = widget.semaforo.baudrate;
  late bool _controlAutomatico = widget.semaforo.controlAutomatico;
  late final TextEditingController _umbralCtrl = TextEditingController(
      text: widget.semaforo.umbralCeroKg?.toString() ?? '5.0');

  bool _guardando = false;
  bool _probando = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _ipCtrl.dispose();
    _puertoCtrl.dispose();
    _comCtrl.dispose();
    _umbralCtrl.dispose();
    super.dispose();
  }

  String _detalleError(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['detail'] != null) return '${data['detail']}';
    }
    return 'No se pudo completar la acción.';
  }

  Future<void> _guardar() async {
    if (_protocolo == 'http') {
      if (_ipCtrl.text.trim().isEmpty ||
          int.tryParse(_puertoCtrl.text.trim()) == null) {
        setState(() => _error = 'Indique IP y puerto válidos para HTTP.');
        return;
      }
    } else {
      if (_comCtrl.text.trim().isEmpty) {
        setState(() => _error = 'Indique el puerto serie/Bluetooth (ej. /dev/ttyUSB0).');
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
        'descripcion': widget.semaforo.descripcion,
        'codigo': widget.semaforo.codigo,
        'activo': widget.semaforo.activo,
        'is_simulado': widget.semaforo.isSimulado,
        'protocolo': _protocolo,
        'ip_address': _protocolo == 'http' ? _ipCtrl.text.trim() : null,
        'puerto_tcp': _protocolo == 'http'
            ? int.tryParse(_puertoCtrl.text.trim())
            : null,
        'puerto_com': _protocolo == 'serial' ? _comCtrl.text.trim() : null,
        'baudrate': _protocolo == 'serial' ? _baudrate : 9600,
        'id_balanza': widget.semaforo.idBalanza,
        'control_automatico': _controlAutomatico,
        'umbral_cero_kg': double.tryParse(_umbralCtrl.text.trim()),
      };
      await _api.updateItem(ApiConstants.semaforo(widget.semaforo.id), body);
      if (!mounted) return;
      widget.onGuardado();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('connection_config_saved')),
          backgroundColor: SwsColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _detalleError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Map<String, dynamic> _parseComando(String comando) {
    final s = comando.trim();
    try {
      if (s.startsWith('{')) {
        final json = Map<String, dynamic>.from(Uri.splitQueryString(''));
        // simple parse
        final cleaned = s.substring(1, s.length - 1);
        final pairs = cleaned.split(',');
        final map = <String, dynamic>{};
        for (final p in pairs) {
          final kv = p.split(':');
          if (kv.length < 2) continue;
          final k = kv[0].trim().replaceAll('"', '');
          var v = kv.sublist(1).join(':').trim();
          v = v.replaceAll('"', '');
          if (v == 'true') {
            map[k] = true;
          } else if (v == 'false') {
            map[k] = false;
          } else if (v == 'on') {
            map[k] = 'on';
          } else if (v == 'off') {
            map[k] = 'off';
          } else if (v == 'flash') {
            map[k] = 'flash';
          } else {
            map[k] = v;
          }
        }
        return map;
      }
    } catch (_) {}
    return {};
  }

  Future<void> _comando(String comando) async {
    setState(() {
      _probando = true;
      _error = null;
      _info = null;
    });
    try {
      await _api.comandoSemaforo(widget.semaforo.id, _parseComando(comando));
      if (!mounted) return;
      setState(() => _info = 'Comando enviado: $comando');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _detalleError(e));
    } finally {
      if (mounted) setState(() => _probando = false);
    }
  }

  Future<void> _probarConexion() async {
    setState(() {
      _probando = true;
      _error = null;
      _info = null;
    });
    try {
      await _api.probarSemaforo(widget.semaforo.id);
      if (!mounted) return;
      setState(() => _info = 'Prueba enviada. Revise el estado del semáforo.');
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      height: media.height * 0.92,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
            child: Row(
              children: [
                Icon(Icons.traffic_outlined, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.semaforo.descripcion,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface),
                  ),
                ),
                IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: colorScheme.onSurface)),
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
                  const Text('Tipo de conexión',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'http',
                          label: Text('HTTP / Red'),
                          icon: Icon(Icons.wifi)),
                      ButtonSegment(
                          value: 'serial',
                          label: Text('Serie / USB / Bluetooth'),
                          icon: Icon(Icons.usb)),
                    ],
                    selected: {_protocolo},
                    onSelectionChanged: (s) =>
                        setState(() => _protocolo = s.first),
                  ),
                  const SizedBox(height: 18),
                  if (_protocolo == 'http') ...[
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _ipCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Dirección IP',
                              hintText: '192.168.1.100',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _puertoCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Puerto',
                              hintText: '8080',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Formato de comandos: JSON (BSDD) por defecto. El backend acepta {"color":"rojo","action":"on/off/flash"}, {"zumbador":"on/off"}, {"all":"off"}.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ] else ...[
                    TextField(
                      controller: _comCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Puerto',
                        hintText: '/dev/ttyUSB0, /dev/rfcomm0 o COM3',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: _baudrate,
                      decoration: const InputDecoration(labelText: 'Baudrate'),
                      items: const [
                        DropdownMenuItem(value: 9600, child: Text('9600')),
                        DropdownMenuItem(value: 19200, child: Text('19200')),
                        DropdownMenuItem(value: 38400, child: Text('38400')),
                        DropdownMenuItem(value: 57600, child: Text('57600')),
                        DropdownMenuItem(value: 115200, child: Text('115200')),
                      ],
                      onChanged: (v) => setState(() => _baudrate = v ?? 9600),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Para Bluetooth SPP se recomienda emparejar el dispositivo y usar /dev/rfcommX.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                  const SizedBox(height: 18),
                  const Text('Control automático',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Activar control automático por báscula'),
                    subtitle: const Text(
                        'El semáforo decidirá los LEDs según peso/vivo y estado del boleto'),
                    value: _controlAutomatico,
                    onChanged: (v) => setState(() => _controlAutomatico = v),
                  ),
                  TextField(
                    controller: _umbralCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Umbral cero (kg)',
                      hintText: '5.0',
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text('Pruebas de LEDs',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _probando
                            ? null
                            : () => _comando(
                                '{"color":"rojo","action":"on"}'),
                        icon: const Icon(Icons.circle, color: Colors.red),
                        label: const Text('Rojo ON'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _probando
                            ? null
                            : () => _comando(
                                '{"color":"amarillo","action":"on"}'),
                        icon: const Icon(Icons.circle, color: Colors.amber),
                        label: const Text('Amarillo ON'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _probando
                            ? null
                            : () => _comando(
                                '{"color":"verde","action":"on"}'),
                        icon: const Icon(Icons.circle, color: Colors.green),
                        label: const Text('Verde ON'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _probando
                            ? null
                            : () => _comando(
                                '{"color":"rojo","action":"flash"}'),
                        icon: const Icon(Icons.bolt),
                        label: const Text('Rojo Parpadeo'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _probando
                            ? null
                            : () => _comando('{"zumbador":"on"}'),
                        icon: const Icon(Icons.volume_up),
                        label: const Text('Zumbador ON'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _probando
                            ? null
                            : () => _comando('{"zumbador":"off"}'),
                        icon: const Icon(Icons.volume_off),
                        label: const Text('Zumbador OFF'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _probando ? null : () => _comando('{"all":"off"}'),
                        icon: const Icon(Icons.power_settings_new),
                        label: const Text('Apagar todo'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _probando ? null : _probarConexion,
                    icon: const Icon(Icons.radar_outlined),
                    label: const Text('Probar conexión'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  if (_info != null) ...[
                    const SizedBox(height: 12),
                    Text(_info!, style: const TextStyle(color: SwsColors.success)),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _guardando ? null : () => Navigator.of(context).pop(),
                    child: Text(context.tr('cancelar')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _guardando ? null : _guardar,
                    child: _guardando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(context.tr('guardar')),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
