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
                        final vinculado = item.balanzasEnlazadas > 0;
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
                            subtitle: Text(
                              '${item.configuracionHardware} · '
                              '${vinculado ? "Vinculado a ${item.balanzasEnlazadas} báscula(s)" : "Sin vincular"}',
                            ),
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
  const _IndicadorDetailSheet({required this.indicador, required this.onGuardado});

  final Indicador indicador;
  final VoidCallback onGuardado;

  @override
  State<_IndicadorDetailSheet> createState() => _IndicadorDetailSheetState();
}

class _IndicadorDetailSheetState extends State<_IndicadorDetailSheet> {
  final _api = di.sl<ApiClient>();

  late bool _activo = widget.indicador.activo;
  bool _guardando = false;
  String? _error;

  bool get _vinculado => widget.indicador.balanzasEnlazadas > 0;

  String _detalleError(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['detail'] != null) return '${data['detail']}';
    }
    return 'No se pudo guardar la configuración.';
  }

  /// Guarda solo lo permisivo (activo). La conexión (puerto/config de trama)
  /// se reenvía con sus valores originales para no perderla: el puerto del
  /// indicador es identidad/heredado y no se edita aquí.
  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final i = widget.indicador;
      final body = <String, dynamic>{
        'descripcion': i.descripcion,
        'codigo': i.codigo,
        'marca': i.marca,
        'modelo': i.modelo,
        'activo': _activo,
        'is_simulado': i.isSimulado,
        'protocolo': i.protocolo,
        'ip_address': i.ipAddress,
        'puerto_tcp': i.puertoTcp,
        'puerto_com': i.puertoCom,
        'formato_trama': i.formatoTrama,
        'baudrate': i.baudrate,
        'delimitador': i.delimitador,
      };
      await _api.actualizarIndicador(i.id, body);
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
    final i = widget.indicador;
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
                    '${i.marca ?? ''} ${i.modelo ?? i.descripcion}'.trim(),
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
                  // ─── Estado de vinculación con báscula ──────────────────
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _vinculado
                          ? SwsColors.success.withValues(alpha: 0.1)
                          : SwsColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _vinculado
                            ? SwsColors.success.withValues(alpha: 0.5)
                            : SwsColors.warning.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _vinculado ? Icons.link : Icons.link_off,
                          color: _vinculado
                              ? SwsColors.success
                              : SwsColors.warning,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _vinculado
                                    ? 'Vinculado a ${i.balanzasEnlazadas} báscula(s)'
                                    : 'Sin vincular a ninguna báscula',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: _vinculado
                                        ? SwsColors.success
                                        : SwsColors.warning),
                              ),
                              Text(
                                _vinculado
                                    ? 'Recibe el peso de la báscula asignada.'
                                    : 'Enlácela desde la báscula para que muestre peso.',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  // ─── Conexión (heredada, NO editable) ───────────────────
                  const Text('Conexión (heredada de la báscula)',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 4),
                  const Text(
                    'El indicador es un dispositivo de salida: muestra el peso '
                    'que la app le envía. Su puerto y configuración provienen de '
                    'la báscula vinculada y no se modifican aquí.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 10),
                  _campoLectura(
                    context,
                    etiqueta: 'Protocolo',
                    valor:
                        i.protocolo == 'serial' ? 'SERIAL / USB' : 'TCP / RED',
                    icono:
                        i.protocolo == 'serial' ? Icons.usb : Icons.router_outlined,
                  ),
                  const SizedBox(height: 10),
                  if (i.protocolo == 'tcp') ...[
                    _campoLectura(
                      context,
                      etiqueta: 'Dirección IP',
                      valor: i.ipAddress ?? '—',
                      icono: Icons.language,
                    ),
                    const SizedBox(height: 10),
                    _campoLectura(
                      context,
                      etiqueta: 'Puerto TCP',
                      valor: '${i.puertoTcp ?? 5555}',
                      icono: Icons.router_outlined,
                    ),
                  ] else ...[
                    _campoLectura(
                      context,
                      etiqueta: 'Puerto serie',
                      valor: i.puertoCom ?? '—',
                      icono: Icons.usb,
                    ),
                    const SizedBox(height: 10),
                    _campoLectura(
                      context,
                      etiqueta: 'Velocidad (baudrate)',
                      valor: '${i.baudrate}',
                      icono: Icons.speed,
                    ),
                  ],
                  const SizedBox(height: 10),
                  _campoLectura(
                    context,
                    etiqueta: 'Formato de trama',
                    valor: i.formatoTrama.toUpperCase(),
                    icono: Icons.code,
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Compatible con Toledo, Yaohua, Rice Lake, Torrey, Keli, MT-SICS y otros indicadores.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const Divider(height: 28),
                  // ─── Único campo editable: activo ───────────────────────
                  Material(
                    color: Colors.transparent,
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Indicador activo'),
                      subtitle: const Text(
                          'Desactívalo para que la app no le envíe peso.'),
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
          message: 'No editable: se hereda de la báscula vinculada',
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
