import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/i18n/translations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../domain/entities/catalogs.dart';
import '../../../injection.dart' as di;

class CamarasConfigTab extends StatefulWidget {
  const CamarasConfigTab({super.key});

  @override
  State<CamarasConfigTab> createState() => _CamarasConfigTabState();
}

class _CamarasConfigTabState extends State<CamarasConfigTab> {
  final _api = di.sl<ApiClient>();
  List<Camara> _items = [];
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
      final resp = await _api.getList(ApiConstants.camaras);
      final data = resp.data as List? ?? [];
      _items = data.map((e) => Camara.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      _items = [];
    }
    if (mounted) setState(() => _cargando = false);
  }

  void _abrirDetalle(Camara c) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CamaraDetailSheet(camara: c, onGuardado: _cargar),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _items.where((e) {
      if (_filtro.isEmpty) return true;
      final f = _filtro.toLowerCase();
      return e.descripcion.toLowerCase().contains(f) ||
          (e.codigo ?? '').toLowerCase().contains(f) ||
          e.urlSnapshot.toLowerCase().contains(f);
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
                          Icon(Icons.videocam_outlined, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(context.tr('Sin cámaras configuradas'), style: TextStyle(color: Colors.grey.shade600)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: filtrados.length,
                      itemBuilder: (context, i) {
                        final item = filtrados[i];
                        String conn = item.esLocal ? 'USB / Local' : 'IP / HTTP';
                        if (!item.esLocal && item.urlSnapshot.isNotEmpty) conn = 'IP - ${item.urlSnapshot}';
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: item.activo ? SwsColors.primary.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.12),
                              child: Icon(Icons.videocam_outlined, color: item.activo ? SwsColors.primary : Colors.grey),
                            ),
                            title: Text(item.descripcion),
                            subtitle: Text('Conexión: $conn • Ubicación: ${item.ubicacionLegible}'),
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

class _CamaraDetailSheet extends StatefulWidget {
  const _CamaraDetailSheet({required this.camara, required this.onGuardado});
  final Camara camara;
  final VoidCallback onGuardado;

  @override
  State<_CamaraDetailSheet> createState() => _CamaraDetailSheetState();
}

class _CamaraDetailSheetState extends State<_CamaraDetailSheet> {
  final _api = di.sl<ApiClient>();

  late String _origen = widget.camara.origen; // ip | local
  late String _ubicacion = widget.camara.ubicacion; // entrada | salida | ambos
  late final TextEditingController _urlCtrl = TextEditingController(text: widget.camara.urlSnapshot);
  late final TextEditingController _dispCtrl = TextEditingController(text: widget.camara.dispositivo ?? '');
  late final TextEditingController _usuarioCtrl = TextEditingController(text: widget.camara.usuario ?? '');
  late final TextEditingController _passCtrl = TextEditingController();

  bool _guardando = false;
  bool _probando = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _dispCtrl.dispose();
    _usuarioCtrl.dispose();
    _passCtrl.dispose();
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
    if (_origen == 'ip') {
      if (_urlCtrl.text.trim().isEmpty) {
        setState(() => _error = 'Indique la URL de snapshot (IP/HTTP).');
        return;
      }
    } else {
      if (_dispCtrl.text.trim().isEmpty) {
        setState(() => _error = 'Indique el dispositivo USB/Local (/dev/video0 o similar).');
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
        'descripcion': widget.camara.descripcion,
        'codigo': widget.camara.codigo,
        'marca': widget.camara.marca,
        'modelo': widget.camara.modelo,
        'activo': widget.camara.activo,
        'is_simulada': widget.camara.isSimulada,
        'origen': _origen,
        'url_snapshot': _origen == 'ip' ? _urlCtrl.text.trim() : '',
        'dispositivo': _origen == 'local' ? _dispCtrl.text.trim() : null,
        'usuario': _usuarioCtrl.text.trim().isEmpty ? null : _usuarioCtrl.text.trim(),
        'ubicacion': _ubicacion,
      };
      if (_passCtrl.text.trim().isNotEmpty) {
        body['password'] = _passCtrl.text.trim();
      }
      await _api.updateItem(ApiConstants.camara(widget.camara.id), body);
      if (!mounted) return;
      widget.onGuardado();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('connection_config_saved')), backgroundColor: SwsColors.success),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _detalleError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _probar() async {
    setState(() {
      _probando = true;
      _error = null;
      _info = null;
    });
    try {
      await _api.probarCamara(widget.camara.id);
      if (!mounted) return;
      setState(() => _info = 'Prueba enviada. Verifique la previsualización/resultado.');
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
                Icon(Icons.videocam_outlined, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(child: Text(widget.camara.descripcion, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colorScheme.onSurface))),
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
                  const Text('Tipo de conexión', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'ip', label: Text('IP / HTTP'), icon: Icon(Icons.wifi)),
                      ButtonSegment(value: 'local', label: Text('USB / Local'), icon: Icon(Icons.usb)),
                    ],
                    selected: {_origen},
                    onSelectionChanged: (s) => setState(() => _origen = s.first),
                  ),
                  const SizedBox(height: 18),
                  if (_origen == 'ip') ...[
                    TextField(controller: _urlCtrl, decoration: const InputDecoration(labelText: 'URL Snapshot', hintText: 'http://192.168.1.50/snapshot.jpg')),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: _usuarioCtrl, decoration: const InputDecoration(labelText: 'Usuario (opcional)'))),
                        const SizedBox(width: 12),
                        Expanded(child: TextField(controller: _passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Contraseña (opcional)'))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('Soporta: IP, HTTP, Serie/PS2 según firmware del fabricante.', style: TextStyle(fontSize: 12, color: Colors.black54)),
                  ] else ...[
                    TextField(controller: _dispCtrl, decoration: const InputDecoration(labelText: 'Dispositivo', hintText: '/dev/video0, /dev/video2')),
                    const SizedBox(height: 12),
                    const Text('Captura local vía ffmpeg/v4l2 (USB/integrada).', style: TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                  const SizedBox(height: 18),
                  const Text('Momento de captura', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
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
                  OutlinedButton.icon(onPressed: _probando ? null : _probar, icon: const Icon(Icons.radar_outlined), label: const Text('Probar conexión / Snapshot')),
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
