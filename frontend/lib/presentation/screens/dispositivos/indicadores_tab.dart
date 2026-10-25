import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/i18n/translations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../domain/entities/catalogs.dart';
import '../../../injection.dart' as di;

class IndicadoresConfigTab extends StatefulWidget {
  const IndicadoresConfigTab({super.key});

  @override
  State<IndicadoresConfigTab> createState() => _IndicadoresConfigTabState();
}

class _IndicadoresConfigTabState extends State<IndicadoresConfigTab> {
  final _api = di.sl<ApiClient>();
  List<Indicador> _items = [];
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
      final resp = await _api.getList(ApiConstants.indicadores);
      final data = resp.data as List? ?? [];
      _items = data
          .map((e) => Indicador.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _items = [];
    }
    if (mounted) setState(() => _cargando = false);
  }

  void _abrirDetalle(Indicador i) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _IndicadorDetailSheet(indicador: i, onGuardado: _cargar),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _items.where((e) {
      if (_filtro.isEmpty) return true;
      final f = _filtro.toLowerCase();
      return e.descripcion.toLowerCase().contains(f) ||
          (e.marca ?? '').toLowerCase().contains(f) ||
          (e.modelo ?? '').toLowerCase().contains(f) ||
          (e.puertoCom ?? '').toLowerCase().contains(f);
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
                        borderRadius: BorderRadius.circular(10)),
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
                          Icon(Icons.speed_outlined,
                              size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(context.tr('Sin indicadores configurados'),
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
                                  ? SwsColors.primary.withValues(alpha: 0.1)
                                  : Colors.grey.withValues(alpha: 0.12),
                              child: Icon(Icons.speed_outlined,
                                  color: item.activo
                                      ? SwsColors.primary
                                      : Colors.grey),
                            ),
                            title: Text(
                                '${item.marca ?? ''} ${item.modelo ?? item.descripcion}'
                                    .trim()),
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

class _IndicadorDetailSheet extends StatefulWidget {
  const _IndicadorDetailSheet(
      {required this.indicador, required this.onGuardado});

  final Indicador indicador;
  final VoidCallback onGuardado;

  @override
  State<_IndicadorDetailSheet> createState() => _IndicadorDetailSheetState();
}

class _IndicadorDetailSheetState extends State<_IndicadorDetailSheet> {
  final _api = di.sl<ApiClient>();

  late String _protocolo = widget.indicador.protocolo;
  late String _formatoTrama = widget.indicador.formatoTrama;
  late int _baudrate = widget.indicador.baudrate;
  late String _delimitador = widget.indicador.delimitador ?? 'lf';
  late final TextEditingController _ipCtrl =
      TextEditingController(text: widget.indicador.ipAddress ?? '');
  late final TextEditingController _puertoCtrl = TextEditingController(
      text: widget.indicador.puertoTcp?.toString() ?? '5001');
  late final TextEditingController _comCtrl =
      TextEditingController(text: widget.indicador.puertoCom ?? '');

  bool _guardando = false;
  String? _error;

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
    return 'No se pudo guardar la configuración.';
  }

  Future<void> _guardar() async {
    if (_protocolo == 'tcp') {
      if (_ipCtrl.text.trim().isEmpty ||
          int.tryParse(_puertoCtrl.text.trim()) == null) {
        setState(() => _error = 'Indique IP y puerto TCP válidos.');
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
    });

    try {
      final body = <String, dynamic>{
        'descripcion': widget.indicador.descripcion,
        'codigo': widget.indicador.codigo,
        'marca': widget.indicador.marca,
        'modelo': widget.indicador.modelo,
        'activo': widget.indicador.activo,
        'is_simulado': widget.indicador.isSimulado,
        'protocolo': _protocolo,
        'ip_address': _protocolo == 'tcp' ? _ipCtrl.text.trim() : null,
        'puerto_tcp': _protocolo == 'tcp'
            ? int.tryParse(_puertoCtrl.text.trim())
            : null,
        'puerto_com': _protocolo == 'serial' ? _comCtrl.text.trim() : null,
        'formato_trama': _formatoTrama,
        'baudrate': _protocolo == 'serial' ? _baudrate : 9600,
        'delimitador': _delimitador,
      };
      await _api.updateItem(ApiConstants.indicador(widget.indicador.id), body);
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

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).size;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      height: media.height * 0.9,
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
                Icon(Icons.speed_outlined, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${widget.indicador.marca ?? ''} ${widget.indicador.modelo ?? widget.indicador.descripcion}'
                        .trim(),
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
                          value: 'tcp',
                          label: Text('TCP / Red'),
                          icon: Icon(Icons.wifi)),
                      ButtonSegment(
                          value: 'serial',
                          label: Text('Serie / USB'),
                          icon: Icon(Icons.usb)),
                    ],
                    selected: {_protocolo},
                    onSelectionChanged: (s) =>
                        setState(() => _protocolo = s.first),
                  ),
                  const SizedBox(height: 18),
                  if (_protocolo == 'tcp') ...[
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _ipCtrl,
                            decoration: const InputDecoration(
                                labelText: 'Dirección IP',
                                hintText: '192.168.1.150'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _puertoCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Puerto', hintText: '5001'),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    TextField(
                      controller: _comCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Puerto Serie/USB',
                          hintText: '/dev/ttyUSB0 o COM3'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: _baudrate,
                            decoration:
                                const InputDecoration(labelText: 'Baudrate'),
                            items: const [
                              DropdownMenuItem(value: 1200, child: Text('1200')),
                              DropdownMenuItem(value: 2400, child: Text('2400')),
                              DropdownMenuItem(value: 4800, child: Text('4800')),
                              DropdownMenuItem(value: 9600, child: Text('9600')),
                              DropdownMenuItem(
                                  value: 19200, child: Text('19200')),
                              DropdownMenuItem(
                                  value: 38400, child: Text('38400')),
                              DropdownMenuItem(
                                  value: 57600, child: Text('57600')),
                              DropdownMenuItem(
                                  value: 115200, child: Text('115200')),
                            ],
                            onChanged: (v) =>
                                setState(() => _baudrate = v ?? 9600),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _delimitador,
                            decoration:
                                const InputDecoration(labelText: 'Delimitador'),
                            items: const [
                              DropdownMenuItem(value: 'lf', child: Text('LF (\\n)')),
                              DropdownMenuItem(value: 'cr', child: Text('CR (\\r)')),
                              DropdownMenuItem(
                                  value: 'crlf', child: Text('CRLF (\\r\\n)')),
                              DropdownMenuItem(
                                  value: 'stx_etx',
                                  child: Text('STX/ETX')),
                            ],
                            onChanged: (v) =>
                                setState(() => _delimitador = v ?? 'lf'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 18),
                  const Text('Trama',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _formatoTrama,
                    decoration: const InputDecoration(labelText: 'Formato de trama'),
                    items: const [
                      DropdownMenuItem(value: 'auto', child: Text('Auto-detectar')),
                      DropdownMenuItem(value: 'ascii', child: Text('ASCII')),
                      DropdownMenuItem(value: 'json', child: Text('JSON')),
                    ],
                    onChanged: (v) => setState(() => _formatoTrama = v ?? 'auto'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Compatible con Toledo, Yaohua, Rice Lake, Torrey, Keli, MT-SICS y otros indicadores.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
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
