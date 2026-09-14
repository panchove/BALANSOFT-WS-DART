import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../providers/bloc/auth/auth_bloc.dart';
import '../../providers/bloc/weighing/weighing_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/number_utils.dart';
import '../../../core/utils/save_file_utils.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/scale_monitor_widget.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../data/repositories/weighing_repository.dart' show WeighingRepository;
import '../../../data/services/scale_api_client.dart';
import '../../../injection.dart' as di;

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
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SectionHeader(title: 'Información General'),
                _InfoRow(label: 'Boleto', value: w.boleto),
                _InfoRow(
                    label: 'Número de Boleto',
                    value: w.numeroBoleto ?? 'N/A'),
                _InfoRow(label: 'Estado', value: w.estadoBoleto),
                _InfoRow(
                    label: 'Fecha Entrada',
                    value: w.fechaHoraEntrada.toLocal().toString().substring(0, 19)),
                if (w.fechaHoraSalida != null)
                  _InfoRow(
                      label: 'Fecha Salida',
                      value: w.fechaHoraSalida!.toLocal().toString().substring(0, 19)),
                if (w.motivoAnulacion != null)
                  _InfoRow(label: 'Motivo Anulación', value: w.motivoAnulacion!),
                const Divider(),
                const SectionHeader(title: 'Vehículo'),
                _InfoRow(label: 'ID Vehículo', value: w.idVehiculo ?? 'N/A'),
                _InfoRow(label: 'Remolque', value: w.remolque ? 'Sí' : 'No'),
                if (w.idRemolque != null)
                  _InfoRow(label: 'ID Remolque', value: w.idRemolque!),
                _InfoRow(label: 'Peso Entrada', value: NumberUtils.formatKg(w.pesoEntradaVehiculo)),
                if (w.pesoEntradaRemolque != null)
                  _InfoRow(
                      label: 'Peso Remolque Entrada',
                      value: NumberUtils.formatKg(w.pesoEntradaRemolque!)),
                const Divider(),
                if (w.isClosed) ...[
                  const SectionHeader(title: 'Salida'),
                  if (w.pesoSalidaVehiculo != null)
                    _InfoRow(label: 'Peso Salida', value: NumberUtils.formatKg(w.pesoSalidaVehiculo!)),
                  if (w.pesoSalidaRemolque != null)
                    _InfoRow(
                        label: 'Peso Remolque Salida',
                        value: NumberUtils.formatKg(w.pesoSalidaRemolque!)),
                  if (w.pesoNeto != null)
                    _InfoRow(
                        label: 'Peso Neto',
                        value: NumberUtils.formatKg(w.pesoNeto!),
                        isBold: true),
                  const Divider(),
                ],
                const SectionHeader(title: 'Operación'),
                _InfoRow(label: 'Transporte', value: w.idTransporte ?? 'N/A'),
                _InfoRow(label: 'Conductor', value: w.idConductor ?? 'N/A'),
                _InfoRow(label: 'Producto', value: w.idProducto ?? 'N/A'),
                _InfoRow(label: 'Almacén', value: w.idAlmacen ?? 'N/A'),
                _InfoRow(label: 'Balanza', value: w.idBalanza ?? 'N/A'),
                if (w.tipoTercero != null || w.idTercero != null)
                  _InfoRow(
                      label: 'Tercero',
                      value:
                          '${w.tipoTercero ?? ''} ${w.idTercero ?? ''}'.trim()),
                _InfoRow(label: 'Documento', value: w.documento ?? 'N/A'),
                if (w.flete != null && w.flete!.isNotEmpty)
                  _InfoRow(label: 'Flete', value: w.flete!),
                if (w.costoFlete != null)
                  _InfoRow(
                      label: 'Costo Flete',
                      value: NumberUtils.formatCurrency(w.costoFlete)),
                if (w.densidad != null)
                  _InfoRow(label: 'Densidad', value: w.densidad.toString()),
                if (w.litros != null)
                  _InfoRow(
                      label: 'Litros',
                      value: NumberUtils.formatWeight(w.litros)),
                if (w.observaciones != null && w.observaciones!.isNotEmpty)
                  _InfoRow(label: 'Observaciones', value: w.observaciones!),
                const Divider(),
                const SectionHeader(title: 'Fotos'),
                _FotosBoleto(boleto: boleto),
                if (w.isOpen) ...[
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: () =>
                        _showCloseDialog(context, boleto, w.idBalanza),
                      style: FilledButton.styleFrom(
                        backgroundColor: SwsColors.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cerrar Pesaje'),
                    ),
                  ),
                ],
                if (!w.isAnulado && puedeAnular) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () => _confirmarAnulacion(context, boleto),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Anular Boleto', style: TextStyle(color: Colors.red)),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () => _reimprimirTicket(
                        context, boleto, w.numeroBoleto ?? w.boleto),
                    icon: const Icon(Icons.print),
                    label: const Text('Reimprimir Ticket'),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
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

  Future<void> _reimprimirTicket(
      BuildContext context, String boleto, String nombreBoleto) async {
    try {
      final response =
          await di.sl<WeighingRepository>().getTicketPdf(boleto);
      final bytes = response.data;
      if (bytes is! List<int> || bytes.isEmpty) {
        throw Exception('El servidor no devolvió un PDF válido.');
      }
      final ruta =
          await SaveFileUtils.save(bytes, 'ticket_$nombreBoleto.pdf', subcarpeta: 'tickets');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ticket guardado en: $ruta'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al generar ticket: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
  final _densidadCtrl = TextEditingController();
  final _unidadesCtrl = TextEditingController();
  final _costoFleteCtrl = TextEditingController();
  final _observacionesCtrl = TextEditingController();
  final _scaleClient = di.sl<ScaleApiClient>();

  @override
  void dispose() {
    _pesoSalidaCtrl.dispose();
    _pesoRemolqueSalidaCtrl.dispose();
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
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Cerrar Pesaje',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
              decoration: const InputDecoration(
                labelText: 'Peso Salida (kg) *',
                prefixIcon: Icon(Icons.monitor_weight),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) => Validators.positiveNumber(v, 'Peso Salida'),
            ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 12),
            TextFormField(
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
            const SizedBox(height: 12),
            TextFormField(
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
            const SizedBox(height: 12),
            TextFormField(
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
            const SizedBox(height: 12),
            TextFormField(
              controller: _observacionesCtrl,
              decoration: const InputDecoration(
                labelText: 'Observaciones',
                prefixIcon: Icon(Icons.notes),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () {
                  if (!(_formKey.currentState?.validate() ?? false)) return;
                  final data = {
                    'peso_salida_vehiculo': double.tryParse(_pesoSalidaCtrl.text) ?? 0,
                    'peso_salida_remolque': double.tryParse(_pesoRemolqueSalidaCtrl.text),
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
                child: const Text('Confirmar Cierre'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;

  const _InfoRow({
    required this.label,
    required this.value,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: isBold ? SwsColors.accent : null,
              ),
            ),
          ),
        ],
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
      fotos.add(_FotoRemote(
        url: api.mediaUrl(url),
        tipo: tipo ?? 'foto',
      ));
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
                width: 22,
                height: 22,
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
        return SizedBox(
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
