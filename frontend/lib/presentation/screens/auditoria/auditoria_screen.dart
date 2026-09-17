import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/number_utils.dart';
import '../../../domain/entities/weighing.dart';
import '../../providers/bloc/weighing/weighing_bloc.dart';

/// Consulta de Auditoría (REQ-NF-SEG-001).
///
/// Presenta el estado transaccional de los pesajes tal como quedó
/// registrado (entrada/salida/anulación) y recuerda que el registro
/// completo de auditoría —usuario, IP, timestamp UTC y cambios— se
/// persiste en la tabla `auditoria` del servidor (próxima fase: volcado
/// a esta vista).
class AuditoriaScreen extends StatefulWidget {
  const AuditoriaScreen({super.key});

  @override
  State<AuditoriaScreen> createState() => _AuditoriaScreenState();
}

class _AuditoriaScreenState extends State<AuditoriaScreen> {
  final _buscaCtrl = TextEditingController();

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Auditoría'),
        actions: [
          IconButton(
            tooltip: 'Refrescar',
            onPressed: () =>
                context.read<WeighingBloc>().add(const ListWeighingsEvent()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: _encabezado(),
          ),
          Expanded(
            child: BlocBuilder<WeighingBloc, WeighingState>(
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
                        final okb =
                            (w.numeroBoleto ?? w.boleto).toLowerCase();
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
                          ? const Center(
                              child: Text('Sin registros',
                                  style: TextStyle(color: SwsColors.gray500)),
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
            ),
          ),
        ],
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
                    '${w.idVehiculo ?? '—'} · ${w.numeroBoleto ?? _corto(w.boleto)}',
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

  String _corto(String s) => s.length > 8 ? '${s.substring(0, 8)}…' : s;
}