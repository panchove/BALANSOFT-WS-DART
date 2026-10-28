import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/i18n/translations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../domain/entities/catalogs.dart';
import '../../../injection.dart' as di;
import '../../widgets/camara_preview.dart';

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
      _items =
          data.map((e) => Camara.fromJson(e as Map<String, dynamic>)).toList();
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
      builder: (_) => _CamaraDetailSheet(
        camara: c,
        todasLasCamaras: _items,
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
                          Icon(Icons.videocam_outlined,
                              size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(context.tr('Sin cámaras configuradas'),
                              style: TextStyle(color: Colors.grey.shade600)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: filtrados.length,
                      itemBuilder: (context, i) {
                        final item = filtrados[i];
                        String conn = item.esLocal ? 'USB / Local' : 'IP / HTTP';
                        if (!item.esLocal && item.urlSnapshot.isNotEmpty) {
                          conn = 'IP - ${item.urlSnapshot}';
                        }
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: item.activo
                                  ? SwsColors.primary.withValues(alpha: 0.1)
                                  : Colors.grey.withValues(alpha: 0.12),
                              child: Icon(Icons.videocam_outlined,
                                  color: item.activo
                                      ? SwsColors.primary
                                      : Colors.grey),
                            ),
                            title: Text(item.descripcion),
                            subtitle: Text(
                                'Conexión: $conn • Ubicación: ${item.ubicacionLegible}'),
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
  const _CamaraDetailSheet({
    required this.camara,
    required this.todasLasCamaras,
    required this.onGuardado,
  });

  final Camara camara;
  final List<Camara> todasLasCamaras;
  final VoidCallback onGuardado;

  @override
  State<_CamaraDetailSheet> createState() => _CamaraDetailSheetState();
}

class _CamaraDetailSheetState extends State<_CamaraDetailSheet> {
  final _api = di.sl<ApiClient>();

  late String _ubicacion = widget.camara.ubicacion; // entrada | salida | ambos
  late bool _activo = widget.camara.activo;
  bool _guardando = false;
  String? _error;

  /// Otra cámara ACTIVA (distinta de esta) con la misma ubicación exclusiva
  /// (`entrada` o `salida`). `ambos` no conflicúa: puede servir a los dos.
  Camara? get _conflicto {
    if (_ubicacion == 'ambos') return null;
    for (final c in widget.todasLasCamaras) {
      if (c.id == widget.camara.id || !c.activo) continue;
      if (c.ubicacion == _ubicacion) return c;
    }
    return null;
  }

  String _detalleError(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['detail'] != null) return '${data['detail']}';
    }
    return 'No se pudo completar la acción.';
  }

  /// Guarda la configuración de uso (ubicación/activo). La conexión
  /// (origen/URL/dispositivo) es la identidad de la cámara y se reenvía con
  /// sus valores originales: no se modifica aquí.
  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final c = widget.camara;
      final body = <String, dynamic>{
        'descripcion': c.descripcion,
        'codigo': c.codigo,
        'marca': c.marca,
        'modelo': c.modelo,
        'activo': _activo,
        'is_simulada': c.isSimulada,
        'origen': c.origen,
        'url_snapshot': c.urlSnapshot,
        'dispositivo': c.dispositivo,
        'usuario': c.usuario,
        'ubicacion': _ubicacion,
      };
      await _api.updateItem(ApiConstants.camara(c.id), body);
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
    final c = widget.camara;
    final conflicto = _conflicto;

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
                Icon(Icons.videocam_outlined, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(c.descripcion,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface)),
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
                  // ─── Conexión: identidad del dispositivo (NO editable) ──
                  const Text('Conexión (identidad del dispositivo)',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 4),
                  const Text(
                    'La cámara se identifica por su origen/URL/dispositivo. '
                    'Si aparece con esa entrada es porque así fue detectada; '
                    'no se modifica aquí. Para cambiarla, elimínela y vuelva a '
                    'detectarla.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 10),
                  _campoLectura(
                    context,
                    etiqueta: 'Origen',
                    valor: c.esLocal ? 'USB / Local' : 'IP / HTTP',
                    icono: c.esLocal ? Icons.usb : Icons.wifi,
                  ),
                  const SizedBox(height: 10),
                  if (c.esLocal)
                    _campoLectura(
                      context,
                      etiqueta: 'Dispositivo',
                      valor: c.dispositivo ?? '—',
                      icono: Icons.videocam,
                    )
                  else
                    _campoLectura(
                      context,
                      etiqueta: 'URL snapshot',
                      valor: c.urlSnapshot.isNotEmpty ? c.urlSnapshot : '—',
                      icono: Icons.link,
                    ),
                  const SizedBox(height: 18),
                  // ─── Vista previa EN VIVO (video) ────────────────────────
                  const Text('Vista previa en vivo',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 4),
                  const Text(
                    'Si la cámara recibe señal verás la imagen moverse aquí. '
                    'El video se detiene al cerrar este panel.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 10),
                  CamaraPreview(
                    key: ValueKey('preview_${c.id}'),
                    camaraId: c.id,
                    height: 220,
                    activo: true,
                    fps: 5,
                  ),
                  const Divider(height: 28),
                  // ─── Momento de captura (editable) ──────────────────────
                  const Text('Momento de captura',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 4),
                  const Text(
                    'Cuándo se toma la foto de la placa. Puede usar una cámara '
                    'para ambas, o una por acceso.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'entrada',
                          label: Text('Entrada'),
                          icon: Icon(Icons.login)),
                      ButtonSegment(
                          value: 'salida',
                          label: Text('Salida'),
                          icon: Icon(Icons.logout)),
                      ButtonSegment(
                          value: 'ambos',
                          label: Text('Ambos'),
                          icon: Icon(Icons.swap_horiz)),
                    ],
                    selected: {_ubicacion},
                    onSelectionChanged: (s) =>
                        setState(() => _ubicacion = s.first),
                  ),
                  if (conflicto != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: SwsColors.warning.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: SwsColors.warning.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: SwsColors.warning, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Atención: "${conflicto.descripcion}" ya está '
                              'asignada a $_ubicacion. Revisa que no se solapen '
                              'las capturas.',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.black87),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Material(
                    color: Colors.transparent,
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Cámara activa'),
                      subtitle:
                          const Text('Desactívala para que no se use en pesajes.'),
                      value: _activo,
                      onChanged: (v) => setState(() => _activo = v),
                    ),
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
}
