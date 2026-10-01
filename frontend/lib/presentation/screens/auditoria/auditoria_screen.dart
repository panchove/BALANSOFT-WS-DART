import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/i18n/translations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/number_utils.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../domain/entities/weighing.dart';
import '../../../injection.dart' as di;
import '../../providers/bloc/weighing/weighing_bloc.dart';

/// Consulta de Auditoría (REQ-NF-SEG-001).
///
/// Presenta el estado transaccional de los pesajes y el volcado completo
/// de la tabla `auditoria` —acción, entidad, entidad_id, detalle, usuario
/// (email), IP y timestamp UTC— consumido de `GET /api/v1/auditoria`.
class AuditoriaScreen extends StatefulWidget {
  const AuditoriaScreen({super.key});

  @override
  State<AuditoriaScreen> createState() => _AuditoriaScreenState();
}

class _AuditoriaScreenState extends State<AuditoriaScreen> {
  final _buscaCtrl = TextEditingController();

  int _modo = 0; // 0 = Transaccional, 1 = Registro de auditoría
  List<Map<String, dynamic>> _registros = const [];
  bool _cargandoRegistros = false;
  String? _errorRegistros;

  @override
  void initState() {
    super.initState();
    context.read<WeighingBloc>().add(const ListWeighingsEvent());
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarRegistros() async {
    setState(() {
      _cargandoRegistros = true;
      _errorRegistros = null;
    });
    try {
      final datos = await di.sl<ApiClient>().listAuditoria();
      if (!mounted) return;
      setState(() {
        _registros = datos;
        _cargandoRegistros = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorRegistros = 'auditoria_error'.tr();
        _cargandoRegistros = false;
      });
    }
  }

  void _cambiarModo(int modo) {
    setState(() => _modo = modo);
    if (modo == 1 && _registros.isEmpty && !_cargandoRegistros) {
      _cargarRegistros();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Auditoría'),
        actions: [
          IconButton(
            tooltip: 'Refrescar',
            onPressed: _modo == 1
                ? _cargarRegistros
                : () => context
                    .read<WeighingBloc>()
                    .add(const ListWeighingsEvent()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: _modo == 0 ? _encabezado() : _encabezadoRegistro(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: SegmentedButton<int>(
              segments: [
                ButtonSegment(
                  value: 0,
                  icon: const Icon(Icons.swap_horiz, size: 16),
                  label: Text('auditoria_tab_transaccional'.tr()),
                ),
                ButtonSegment(
                  value: 1,
                  icon: const Icon(Icons.receipt_long_outlined, size: 16),
                  label: Text('auditoria_tab_registro'.tr()),
                ),
              ],
              selected: {_modo},
              onSelectionChanged: (s) => _cambiarModo(s.first),
            ),
          ),
          Expanded(
            child: _modo == 0
                ? _vistaTransaccional(context)
                : _vistaRegistros(),
          ),
        ],
      ),
    );
  }

  Widget _vistaTransaccional(BuildContext context) {
    return BlocBuilder<WeighingBloc, WeighingState>(
      builder: (context, state) {
        if (state is! WeighingListLoaded) {
          return const Center(child: CircularProgressIndicator());
        }
        final pesos = [...state.weighings]
          ..sort((a, b) => b.fechaHoraEntrada.compareTo(a.fechaHoraEntrada));
        final query = _buscaCtrl.text.trim().toLowerCase();
        final filtrados = query.isEmpty
            ? pesos
            : pesos.where((w) {
                final okv = (w.idVehiculo ?? '').toLowerCase();
                final okb = (w.numeroBoleto ?? w.boleto).toLowerCase();
                return okv.contains(query) || okb.contains(query);
              }).toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _resumen(pesos),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: TextField(
                controller: _buscaCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Buscar por placa o boleto…',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            Expanded(
              child: filtrados.isEmpty
                  ? Center(
                      child: Text('no_records'.tr(),
                          style: const TextStyle(color: SwsColors.gray500)),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: filtrados.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, i) =>
                          _tarjeta(filtrados[i]),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _vistaRegistros() {
    if (_cargandoRegistros) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorRegistros != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: SwsColors.danger, size: 32),
            const SizedBox(height: 8),
            Text(_errorRegistros!),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _cargarRegistros,
              child: Text('retry'.tr()),
            ),
          ],
        ),
      );
    }
    if (_registros.isEmpty) {
      return Center(
        child: Text('no_records'.tr(),
            style: const TextStyle(color: SwsColors.gray500)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _registros.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _tarjetaRegistro(_registros[i]),
    );
  }

  Widget _tarjetaRegistro(Map<String, dynamic> r) {
    final detalle = r['detalle'];
    final acciones = <String, (Color, IconData)>{
      'CREATE': (SwsColors.success, Icons.add_circle_outline),
      'UPDATE': (SwsColors.accent, Icons.edit_outlined),
      'DELETE': (SwsColors.danger, Icons.delete_outline),
    };
    final accion = (r['accion'] ?? '').toString();
    final (color, icono) =
        acciones[accion] ?? (SwsColors.gray500, Icons.history);
    final ts = DateTime.tryParse('${r['created_at'] ?? ''}')?.toLocal();
    final cuando = ts == null ? '—' : _cortoFecha(ts);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icono, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$accion · ${r['entidad'] ?? '—'}',
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(cuando,
                    style: const TextStyle(
                        fontSize: 11.5, color: SwsColors.gray500)),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _dato('auditoria_usuario'.tr(),
                    '${r['usuario_email'] ?? r['id_usuario'] ?? '—'}'),
                _dato('auditoria_entidad_id'.tr(),
                    '${r['entidad_id'] ?? '—'}'),
                _dato('auditoria_ip'.tr(), '${r['ip'] ?? '—'}'),
              ],
            ),
            if (detalle is Map && detalle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                detalle.entries
                    .map((e) => '${e.key}: ${e.value}')
                    .join(' · '),
                style: const TextStyle(fontSize: 11.5, color: SwsColors.gray700),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _encabezadoRegistro() {
    return const Card(
      margin: EdgeInsets.zero,
      color: SwsColors.blue100,
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.receipt_long_outlined,
                color: SwsColors.primary, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Volcado completo de la tabla de auditoría: acción, entidad, '
                'identificador, detalle del cambio, usuario, IP y marca de '
                'tiempo UTC. Solo visible para los roles ADMIN y AUDITOR.',
                style: TextStyle(fontSize: 12.5, color: SwsColors.gray700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _encabezado() {
    return const Card(
      margin: EdgeInsets.zero,
      color: SwsColors.blue100,
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.verified_user_outlined,
                color: SwsColors.primary, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Todo cambio de estado en un pesaje (entrada, salida, '
                'anulación, modificación) queda inmutablemente registrado en el '
                'servidor: usuario, IP, marca de tiempo UTC y datos antes/después.',
                style: TextStyle(fontSize: 12.5, color: SwsColors.gray700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resumen(List<Weighing> pesos) {
    int contar(bool Function(Weighing) f) => pesos.where(f).length;
    final items = <(IconData, Color, String, int)>[
      (Icons.list_alt, SwsColors.primary, 'Total', pesos.length),
      (
        Icons.radio_button_checked,
        SwsColors.warning,
        'Pendientes',
        contar((w) => w.isOpen),
      ),
      (
        Icons.check_circle,
        SwsColors.success,
        'Cerrados',
        contar((w) => w.isClosed),
      ),
      (
        Icons.block,
        SwsColors.danger,
        'Anulados',
        contar((w) => w.isAnulado),
      ),
      (
        Icons.cloud_off_outlined,
        SwsColors.gray600,
        'Sin sincronizar',
        contar((w) => w.isPendingSync),
      ),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (icono, color, etiqueta, valor) in items)
          Chip(
            avatar: Icon(icono, size: 16, color: color),
            label: Text('$etiqueta: $valor'),
          ),
      ],
    );
  }

  Widget _tarjeta(Weighing w) {
    final (Color color, IconData icono, String estado) = switch (
      w.estadoBoleto) {
      'PENDIENTE' => (SwsColors.warning, Icons.radio_button_checked,
          'PENDIENTE'),
      'MODIFICADO' => (SwsColors.accent, Icons.edit_outlined, 'MODIFICADO'),
      'CERRADO' => (SwsColors.success, Icons.check_circle, 'CERRADO'),
      'ANULADO' => (SwsColors.danger, Icons.block, 'ANULADO'),
      final e => (SwsColors.gray500, Icons.help_outline, e),
    };
    final local = w.fechaHoraEntrada.toLocal();
    final fecha = '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
    final hora = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icono, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${w.idVehiculo ?? '—'} · ${w.numeroBoleto ?? 'Boleto s/n'}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    estado,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: color),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _dato('Entrada', '$fecha $hora'),
                if (w.fechaHoraSalida != null)
                  _dato(
                    'Salida',
                    _cortoFecha(w.fechaHoraSalida!.toLocal()),
                  )
                else
                  _dato('Salida', '—'),
                _dato('P. bruto',
                    NumberUtils.formatKg(w.pesoEntradaVehiculo)),
                if (w.pesoNeto != null)
                  _dato('Neto', NumberUtils.formatKg(w.pesoNeto!)),
                if (w.motivoAnulacion != null)
                  _dato('Motivo', '${w.motivoAnulacion}'),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              w.sincronizado ? 'Sincronizado' : 'Pendiente de sincronización',
              style: TextStyle(
                fontSize: 11.5,
                color: w.sincronizado ? SwsColors.success : SwsColors.warning,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dato(String etiqueta, String valor) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta, style: const TextStyle(fontSize: 10.5, color: SwsColors.gray500)),
          Text(valor,
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      );

  String _cortoFecha(DateTime d) {
    final f = '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    final h = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '$f $h';
  }
}