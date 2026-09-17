import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/number_utils.dart';
import '../../../core/utils/save_file_utils.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/scale_monitor_widget.dart';
import '../../../data/datasources/local/local_storage.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../data/repositories/weighing_repository.dart' show WeighingRepository;
import '../../../data/services/scale_api_client.dart';
import '../../../domain/entities/weighing.dart';
import '../../../injection.dart' as di;
import '../../providers/bloc/auth/auth_bloc.dart';
import '../../providers/bloc/weighing/weighing_bloc.dart';

class WeighingDetailScreen extends StatelessWidget {
  final String boleto;
  const WeighingDetailScreen({super.key, required this.boleto});

  @override
  Widget build(BuildContext context) {
    if (boleto.trim().isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detalle del Pesaje')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No se puede cargar el pesaje: identificador vacío.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    context.read<WeighingBloc>().add(GetWeighingEvent(boleto));
    final authState = context.watch<AuthBloc>().state;
    final puedeAnular = authState is AuthAuthenticated &&
        (authState.user.isAdmin || authState.user.isSupervisor);

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle del Pesaje')),
      body: BlocBuilder<WeighingBloc, WeighingState>(
        builder: (context, state) {
          if (state is WeighingDetail) {
            final w = state.weighing;
            return Column(
              children: [
                _AccionBar(
                  boleto: w.boleto,
                  peso: w,
                  puedeAnular: puedeAnular,
                  onImprimir: () => _reimprimirTicket(context, w),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _buildDetalle(context, w),
                  ),
                ),
              ],
            );
          }
          if (state is WeighingError) {
            return Center(child: Text('Error: ${state.message}'));
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }

  Widget _buildDetalle(BuildContext context, Weighing w) {
    final isWide = MediaQuery.sizeOf(context).width > 900;
    final principal = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionCard(
          title: 'DATOS',
          icon: Icons.assignment,
          children: [
            _InfoRow(label: 'Serie - Boleto', value: w.numeroBoleto ?? w.boleto),
            _InfoRow(
                label: 'Fecha/Hora',
                value: _fmt(w.fechaHoraEntrada.toLocal())),
            _InfoRow(label: 'Camión', value: w.idVehiculo ?? 'N/A'),
            _InfoRow(label: 'Remolque', value: w.remolque ? (w.idRemolque ?? 'Sí') : 'No'),
            _InfoRow(label: 'Transporte', value: w.idTransporte ?? 'N/A'),
            _InfoRow(label: 'Conductor', value: w.idConductor ?? 'N/A'),
            _InfoRow(label: 'Producto', value: w.idProducto ?? 'N/A'),
            _InfoRow(label: 'Almacén', value: w.idAlmacen ?? 'N/A'),
            _InfoRow(label: 'Balanza', value: w.idBalanza ?? 'N/A'),
            if (w.tipoTercero != null || w.idTercero != null)
              _InfoRow(
                  label: 'Selección',
                  value: '${w.tipoTercero ?? ''} ${w.idTercero ?? ''}'.trim()),
          ],
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'LECTURA',
          icon: Icons.monitor_weight,
          children: _buildLectura(w),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'DATOS ADICIONALES',
          icon: Icons.description,
          children: [
            _InfoRow(label: 'Documento', value: w.documento ?? 'N/A'),
            if (w.flete != null && w.flete!.isNotEmpty)
              _InfoRow(label: 'Flete', value: w.flete!),
            if (w.costoFlete != null)
              _InfoRow(label: 'Costo Flete', value: NumberUtils.formatCurrency(w.costoFlete)),
            if (w.densidad != null)
              _InfoRow(label: 'Densidad', value: w.densidad.toString()),
            if (w.unidades != null)
              _InfoRow(label: 'Unidades', value: NumberUtils.formatWeight(w.unidades)),
            if (w.litros != null)
              _InfoRow(label: 'Litros', value: NumberUtils.formatWeight(w.litros)),
          ],
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'OBSERVACIONES',
          icon: Icons.notes,
          children: [
            if (w.observaciones != null && w.observaciones!.isNotEmpty)
              Text(w.observaciones!, style: const TextStyle(fontSize: 13))
            else
              const Text('Sin observaciones',
                  style: TextStyle(color: SwsColors.gray500, fontSize: 13)),
          ],
        ),
        if (w.motivoAnulacion != null) ...[
          const SizedBox(height: 12),
          _SectionCard(
            title: 'ANULACIÓN',
            icon: Icons.block,
            children: [
              _InfoRow(label: 'Motivo', value: w.motivoAnulacion!),
            ],
          ),
        ],
      ],
    );

    return isWide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: principal),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: _FotosBoleto(boleto: w.boleto)),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              principal,
              const SizedBox(height: 12),
              _SectionCard(
                title: 'FOTOS',
                icon: Icons.photo_library_outlined,
                children: [_FotosBoleto(boleto: w.boleto)],
              ),
            ],
          );
  }

  List<Widget> _buildLectura(Weighing w) {
    final entrada = w.pesoTotalEntrada;
    return [
      _WeightTable(
        pesoEntradaVehiculo: w.pesoEntradaVehiculo,
        pesoEntradaRemolque: w.pesoEntradaRemolque,
        pesoSalidaVehiculo: w.pesoSalidaVehiculo,
        pesoSalidaRemolque: w.pesoSalidaRemolque,
        pesoNetoDeclarado: w.pesoNetoDeclarado,
        pesoNeto: w.pesoNeto,
        pesoDiferencia: w.pesoDiferencia,
        porcentajeDesviacion: w.porcentajeDesviacion,
      ),
      const SizedBox(height: 10),
      _InfoRow(label: 'Peso Entrada Vehículo', value: NumberUtils.formatKg(w.pesoEntradaVehiculo)),
      if (w.pesoEntradaRemolque != null)
        _InfoRow(label: 'Peso Entrada Remolque', value: NumberUtils.formatKg(w.pesoEntradaRemolque)),
      _InfoRow(label: 'F. Entrada', value: _fmt(w.fechaHoraEntrada.toLocal())),
      if (w.pesoSalidaVehiculo != null) ...[
        const Divider(height: 16),
        _InfoRow(label: 'Peso Salida Vehículo', value: NumberUtils.formatKg(w.pesoSalidaVehiculo)),
        if (w.pesoSalidaRemolque != null)
          _InfoRow(label: 'Peso Salida Remolque', value: NumberUtils.formatKg(w.pesoSalidaRemolque)),
        if (w.fechaHoraSalida != null)
          _InfoRow(label: 'F. Salida', value: _fmt(w.fechaHoraSalida!.toLocal())),
        _InfoRow(label: 'Total Entrada', value: NumberUtils.formatKg(entrada)),
        if (w.pesoNeto != null)
          _InfoRow(label: 'Peso Neto', value: NumberUtils.formatKg(w.pesoNeto), isBold: true),
        if (w.pesoDiferencia != null)
          _InfoRow(label: 'Diferencia', value: NumberUtils.formatKg(w.pesoDiferencia)),
        if (w.porcentajeDesviacion != null)
          _InfoRow(label: '% Desviación', value: NumberUtils.formatPercent(w.porcentajeDesviacion)),
      ],
    ];
  }

  Future<void> _reimprimirTicket(BuildContext context, Weighing w) async {
    try {
      final response =
          await di.sl<WeighingRepository>().getTicketPdf(w.boleto);
      final bytes = response.data;
      if (bytes is! List<int> || bytes.isEmpty) {
        throw Exception('El servidor no devolvió un PDF válido.');
      }
      final ruta = await SaveFileUtils.save(
          bytes, 'ticket_${w.numeroBoleto ?? w.boleto}.pdf',
          subcarpeta: 'tickets');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ticket guardado en: $ruta'),
            backgroundColor: SwsColors.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al generar ticket: $e'),
            backgroundColor: SwsColors.danger,
          ),
        );
      }
    }
  }

  String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }
}

class _AccionBar extends StatelessWidget {
  final String boleto;
  final Weighing peso;
  final bool puedeAnular;
  final VoidCallback onImprimir;

  const _AccionBar({
    required this.boleto,
    required this.peso,
    required this.puedeAnular,
    required this.onImprimir,
  });

  @override
  Widget build(BuildContext context) {
    final esPendiente = peso.isOpen;

    return Container(
      color: SwsColors.primary,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          _ToolbarButton(
            icon: Icons.local_shipping_outlined,
            label: 'Salida',
            onTap: esPendiente
                ? () => _showCloseDialog(context, boleto, peso.idBalanza)
                : null,
            color: SwsColors.success,
          ),
          const SizedBox(width: 6),
          _ToolbarButton(
            icon: Icons.print,
            label: 'Imprimir',
            onTap: onImprimir,
          ),
          if (puedeAnular && !peso.isAnulado) ...[
            const SizedBox(width: 6),
            _ToolbarButton(
              icon: Icons.block,
              label: 'Anular',
              onTap: () => _confirmarAnulacion(context, boleto),
              color: SwsColors.danger,
            ),
          ],
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _colorEstado(peso.estadoBoleto).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              peso.estadoBoleto,
              style: TextStyle(
                color: _colorEstado(peso.estadoBoleto),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _colorEstado(String estado) {
    switch (estado) {
      case 'CERRADO':
        return SwsColors.success;
      case 'ANULADO':
        return SwsColors.danger;
      case 'MODIFICADO':
        return SwsColors.warning;
      default:
        return SwsColors.accentLight;
    }
  }

  void _confirmarAnulacion(BuildContext context, String boleto) {
    final motivoCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Anular Boleto'),
        content: TextField(
          controller: motivoCtrl,
          maxLines: 3,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Motivo de anulación *',
            hintText: 'Indique el motivo (mínimo 10 caracteres)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final motivo = motivoCtrl.text.trim();
              final error = Validators.required(motivo, 'Motivo de anulación') ??
                  Validators.minLength(motivo, 10, 'Motivo de anulación');
              if (error != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(error), backgroundColor: Colors.red),
                );
                return;
              }
              Navigator.pop(ctx);
              context.read<WeighingBloc>().add(AnularWeighingEvent(boleto, motivo));
            },
            child: const Text('Anular'),
          ),
        ],
      ),
    );
  }

  void _showCloseDialog(BuildContext context, String boleto, String? idBalanza) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) =>
          _CloseWeighingSheet(boleto: boleto, idBalanza: idBalanza),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  const _ToolbarButton({required this.icon, required this.label, this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final btnColor = color ?? Colors.white70;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: !enabled
              ? Colors.white.withValues(alpha: 0.04)
              : color?.withValues(alpha: 0.15) ?? Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: enabled ? btnColor : Colors.white24),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: enabled ? btnColor : Colors.white24,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: SwsColors.accent),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: SwsColors.primary)),
              ],
            ),
            const Divider(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _WeightTable extends StatelessWidget {
  final double pesoEntradaVehiculo;
  final double? pesoEntradaRemolque;
  final double? pesoSalidaVehiculo;
  final double? pesoSalidaRemolque;
  final double? pesoNetoDeclarado;
  final double? pesoNeto;
  final double? pesoDiferencia;
  final double? porcentajeDesviacion;

  const _WeightTable({
    required this.pesoEntradaVehiculo,
    this.pesoEntradaRemolque,
    this.pesoSalidaVehiculo,
    this.pesoSalidaRemolque,
    this.pesoNetoDeclarado,
    this.pesoNeto,
    this.pesoDiferencia,
    this.porcentajeDesviacion,
  });

  @override
  Widget build(BuildContext context) {
    final pte = pesoEntradaVehiculo + (pesoEntradaRemolque ?? 0);
    final pts = pesoSalidaVehiculo != null
        ? pesoSalidaVehiculo! + (pesoSalidaRemolque ?? 0)
        : null;
    final pnt = pesoNeto ?? (pts != null ? pte - pts : null);

    return Card(
      color: SwsColors.blue100,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _row('', 'Camión', 'Remolque', 'Total', header: true),
            _row('Entrada',
                NumberUtils.formatWeight(pesoEntradaVehiculo),
                NumberUtils.formatWeight(pesoEntradaRemolque),
                NumberUtils.formatWeight(pte)),
            if (pts != null) ...[
              _row('Salida',
                  NumberUtils.formatWeight(pesoSalidaVehiculo),
                  NumberUtils.formatWeight(pesoSalidaRemolque),
                  NumberUtils.formatWeight(pts)),
              const Divider(height: 14),
              _row('Peso Neto', '', '', NumberUtils.formatWeight(pnt), bold: true),
              _row('Peso Declarado', '', '',
                  NumberUtils.formatWeight(pesoNetoDeclarado)),
              _row('Diferencia', '', '',
                  NumberUtils.formatWeight(pesoDiferencia),
                  bold: pesoDiferencia != null && pesoDiferencia != 0),
              _row('% Desviación', '', '',
                  NumberUtils.formatPercent(porcentajeDesviacion)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String camion, String remolque, String total,
      {bool header = false, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(label,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: header
                        ? FontWeight.w700
                        : bold
                            ? FontWeight.bold
                            : FontWeight.w500)),
          ),
          Expanded(
            flex: 3,
            child: Text(camion,
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: header ? 11 : 11.5,
                    fontWeight: header ? FontWeight.w700 : FontWeight.w600)),
          ),
          Expanded(
            flex: 3,
            child: Text(remolque,
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: header ? 11 : 11.5,
                    fontWeight: header ? FontWeight.w700 : FontWeight.w600)),
          ),
          Expanded(
            flex: 3,
            child: Text(total,
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: header ? 11 : 12,
                    fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                    color: bold ? SwsColors.accent : SwsColors.dark)),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;

  const _InfoRow({required this.label, required this.value, this.isBold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: SwsColors.gray500)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                color: isBold ? SwsColors.accent : SwsColors.dark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CloseWeighingSheet extends StatefulWidget {
  final String boleto;
  final String? idBalanza;
  const _CloseWeighingSheet({required this.boleto, this.idBalanza});

  @override
  State<_CloseWeighingSheet> createState() => _CloseWeighingSheetState();
}

class _CloseWeighingSheetState extends State<_CloseWeighingSheet> {
  final _formKey = GlobalKey<FormState>();
  final _pesoSalidaCtrl = TextEditingController();
  final _pesoRemolqueSalidaCtrl = TextEditingController();
  final _pesoNetoDeclaradoCtrl = TextEditingController();
  final _densidadCtrl = TextEditingController();
  final _unidadesCtrl = TextEditingController();
  final _costoFleteCtrl = TextEditingController();
  final _observacionesCtrl = TextEditingController();
  final _scaleClient = di.sl<ScaleApiClient>();

  bool _esPesoManual = false;
  bool _puedePesoManual = false;

  @override
  void initState() {
    super.initState();
    _cargarPermiso();
  }

  Future<void> _cargarPermiso() async {
    final user = await di.sl<LocalStorage>().getCachedUser();
    if (mounted) {
      setState(() {
        _puedePesoManual = user?.rol == 'ADMIN' || user?.rol == 'SUPERVISOR';
      });
    }
  }

  @override
  void dispose() {
    _pesoSalidaCtrl.dispose();
    _pesoRemolqueSalidaCtrl.dispose();
    _pesoNetoDeclaradoCtrl.dispose();
    _densidadCtrl.dispose();
    _unidadesCtrl.dispose();
    _costoFleteCtrl.dispose();
    _observacionesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.local_shipping_outlined,
                      size: 20, color: SwsColors.accent),
                  const SizedBox(width: 8),
                  const Text('Cerrar Pesaje — Salida',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: SwsColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text('Boleto pendiente',
                        style: TextStyle(
                            fontSize: 11, color: SwsColors.warning, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ScaleMonitorWidget(
                client: _scaleClient,
                label: 'Báscula de salida',
                balanzaId: widget.idBalanza,
                initialWeight: double.tryParse(_pesoSalidaCtrl.text) ?? 0,
                onPesoLeido: (peso) {
                  _pesoSalidaCtrl.text = peso.toStringAsFixed(2);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pesoSalidaCtrl,
                readOnly: !_esPesoManual,
                decoration: InputDecoration(
                  labelText: 'Peso Salida Vehículo (kg) *',
                  prefixIcon: !_esPesoManual
                      ? const Icon(Icons.link)
                      : const Icon(Icons.monitor_weight),
                  helperText: _esPesoManual
                      ? 'Registro manual (solo Supervisor/Admin)'
                      : 'Peso registrado por la báscula: no se puede editar',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) => Validators.positiveNumber(v, 'Peso Salida'),
              ),
              if (_puedePesoManual) ...[
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Registro manual del peso',
                      style: TextStyle(fontSize: 12.5)),
                  subtitle: const Text('Solo Supervisor/Admin',
                      style: TextStyle(fontSize: 11)),
                  value: _esPesoManual,
                  activeThumbColor: Theme.of(context).colorScheme.primary,
                  onChanged: (v) => setState(() => _esPesoManual = v),
                ),
              ],
              const SizedBox(height: 10),
              TextFormField(
                controller: _pesoRemolqueSalidaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Peso Remolque Salida (kg)',
                  prefixIcon: Icon(Icons.local_shipping_outlined),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final num = double.tryParse(v);
                  if (num == null || num < 0) return 'Peso remolque debe ser positivo';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _pesoNetoDeclaradoCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Peso Neto Declarado (kg)',
                        prefixIcon: Icon(Icons.balance),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _densidadCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Densidad',
                        prefixIcon: Icon(Icons.speed_outlined),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final num = double.tryParse(v);
                        if (num == null || num <= 0) return 'Densidad debe ser positiva';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _unidadesCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Unidades',
                        prefixIcon: Icon(Icons.straighten_outlined),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final num = double.tryParse(v);
                        if (num == null || num < 0) return 'Unidades debe ser positivo';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _costoFleteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Costo del Flete',
                        prefixIcon: Icon(Icons.attach_money),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final num = double.tryParse(v);
                        if (num == null || num < 0) return 'Costo debe ser positivo';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _observacionesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Observaciones',
                  prefixIcon: Icon(Icons.notes),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              BlocBuilder<WeighingBloc, WeighingState>(
                builder: (context, state) {
                  final isLoading = state is WeighingLoading;
                  return SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: isLoading
                          ? null
                          : () {
                              if (!(_formKey.currentState?.validate() ?? false)) return;
                              final data = {
                                'peso_salida_vehiculo': double.tryParse(_pesoSalidaCtrl.text) ?? 0,
                                'peso_salida_remolque': double.tryParse(_pesoRemolqueSalidaCtrl.text),
                                'peso_neto_declarado': double.tryParse(_pesoNetoDeclaradoCtrl.text),
                                'densidad': double.tryParse(_densidadCtrl.text),
                                'unidades': double.tryParse(_unidadesCtrl.text),
                                'costo_flete': double.tryParse(_costoFleteCtrl.text),
                                'observaciones': _observacionesCtrl.text.isNotEmpty
                                    ? _observacionesCtrl.text
                                    : null,
                              };
                              context.read<WeighingBloc>().add(CloseWeighingEvent(widget.boleto, data));
                              Navigator.pop(context);
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: SwsColors.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: isLoading
                          ? const SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Confirmar Cierre'),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FotosBoleto extends StatefulWidget {
  final String boleto;

  const _FotosBoleto({required this.boleto});

  @override
  State<_FotosBoleto> createState() => _FotosBoletoState();
}

class _FotosBoletoState extends State<_FotosBoleto> {
  late Future<List<_FotoRemote>> _future;

  @override
  void initState() {
    super.initState();
    _future = _cargar();
  }

  Future<List<_FotoRemote>> _cargar() async {
    final api = di.sl<ApiClient>();
    final response = await api.listImages(widget.boleto);
    final data = response.data;
    if (data is! List) return const [];
    final fotos = <_FotoRemote>[];
    for (final item in data) {
      final url = item['url'] as String?;
      final tipo = item['tipo'] as String?;
      if (url == null || url.isEmpty) continue;
      fotos.add(_FotoRemote(url: api.mediaUrl(url), tipo: tipo ?? 'foto'));
    }
    return fotos;
  }

  @override
  void didUpdateWidget(covariant _FotosBoleto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.boleto != widget.boleto) {
      _future = _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_FotoRemote>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 22, height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final fotos = snapshot.data ?? const <_FotoRemote>[];
        if (fotos.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Icon(Icons.photo_library_outlined, size: 18, color: SwsColors.gray400),
                SizedBox(width: 8),
                Text('Este boleto no tiene fotos',
                    style: TextStyle(color: SwsColors.gray500, fontSize: 13)),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(title: 'Fotos'),
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: fotos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final foto = fotos[index];
                  return GestureDetector(
                    onTap: () => _verFoto(foto),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        foto.url,
                        width: 96,
                        height: 96,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 96,
                          height: 96,
                          color: SwsColors.light,
                          child: const Icon(Icons.broken_image_outlined,
                              color: SwsColors.gray400),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _verFoto(_FotoRemote foto) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: SwsColors.blue100,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                'Foto · ${foto.tipo}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Image.network(
              foto.url,
              errorBuilder: (_, __, ___) => const SizedBox(
                height: 200,
                child: Center(
                  child: Icon(Icons.broken_image_outlined,
                      size: 48, color: SwsColors.gray400),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FotoRemote {
  final String url;
  final String tipo;

  const _FotoRemote({required this.url, required this.tipo});
}