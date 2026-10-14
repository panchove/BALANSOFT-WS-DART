import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/i18n/translations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/weighing_repository.dart';
import '../../../domain/entities/boleto_edicion.dart';
import '../../../domain/entities/weighing.dart';
import '../../../domain/repositories/i_weighing_repository.dart';
import '../../../injection.dart' as di;

/// Diálogo de edición de un boleto ya existente.
///
/// Reglas de negocio (migración 024):
/// - La edición exige **justificación** (mínimo 10 caracteres); queda
///   registrada en `boletos_ediciones` con quién, cuándo y qué cambió.
/// - Si la empresa fija un **tope de ediciones**, el backend responde 409 y el
///   mensaje se muestra tal cual (el ADMIN nunca choca con el tope).
/// - Los pesos capturados por la báscula **no se editan**: aquí solo se tocan
///   los datos adicionales del boleto.
/// - Un boleto anulado no se puede editar (el backend también lo rechaza).
class EditarBoletoDialog extends StatefulWidget {
  /// Boleto a editar (la copia en memoria del listado).
  final Weighing boleto;

  const EditarBoletoDialog({super.key, required this.boleto});

  /// Abre el diálogo y devuelve `true` si el boleto quedó editado.
  static Future<bool> mostrar(BuildContext context, Weighing boleto) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EditarBoletoDialog(boleto: boleto),
    );
    return ok ?? false;
  }

  @override
  State<EditarBoletoDialog> createState() => _EditarBoletoDialogState();
}

class _EditarBoletoDialogState extends State<EditarBoletoDialog> {
  // Datos adicionales editables (mismos campos que `WeighingUpdate`).
  final _documentoCtrl = TextEditingController();
  final _guiaCtrl = TextEditingController();
  final _medidaCtrl = TextEditingController();
  final _fleteCtrl = TextEditingController();
  final _costoFleteCtrl = TextEditingController();
  final _observacionesCtrl = TextEditingController();
  final _pesoDeclaradoCtrl = TextEditingController();
  final _densidadCtrl = TextEditingController();
  final _litrosCtrl = TextEditingController();
  final _unidadesCtrl = TextEditingController();

  final _justificacionCtrl = TextEditingController();
  final _justificacionFocus = FocusNode();

  List<BoletoEdicion> _historial = const [];
  bool _cargandoHistorial = true;
  bool _guardando = false;
  String? _error;

  bool get _esAnulado => widget.boleto.isAnulado;

  @override
  void initState() {
    super.initState();
    _cargarDesdeBoleto();
    _cargarHistorial();
  }

  @override
  void dispose() {
    _documentoCtrl.dispose();
    _guiaCtrl.dispose();
    _medidaCtrl.dispose();
    _fleteCtrl.dispose();
    _costoFleteCtrl.dispose();
    _observacionesCtrl.dispose();
    _pesoDeclaradoCtrl.dispose();
    _densidadCtrl.dispose();
    _litrosCtrl.dispose();
    _unidadesCtrl.dispose();
    _justificacionCtrl.dispose();
    _justificacionFocus.dispose();
    super.dispose();
  }

  static String _num(double? v) {
    if (v == null) return '';
    // Sin notación científica ni ceros de relleno molestos.
    final s = v.toString();
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  void _cargarDesdeBoleto() {
    final w = widget.boleto;
    _documentoCtrl.text = w.documento ?? '';
    _guiaCtrl.text = w.guiaSunagro ?? '';
    _medidaCtrl.text = w.medida ?? '';
    _fleteCtrl.text = w.flete ?? '';
    _costoFleteCtrl.text = _num(w.costoFlete);
    _observacionesCtrl.text = w.observaciones ?? '';
    _pesoDeclaradoCtrl.text = _num(w.pesoNetoDeclarado);
    _densidadCtrl.text = _num(w.densidad);
    _litrosCtrl.text = _num(w.litros);
    _unidadesCtrl.text = _num(w.unidades);
  }

  Future<void> _cargarHistorial() async {
    setState(() => _cargandoHistorial = true);
    final lista =
        await di.sl<WeighingRepository>().getEdiciones(widget.boleto.boleto);
    if (!mounted) return;
    setState(() {
      _historial = lista;
      _cargandoHistorial = false;
    });
  }

  double? _parse(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t.replaceAll(',', '.'));
  }

  /// Payload del `PUT`, con **solo** los campos adicionales + justificación.
  ///
  /// Se envían siempre los diez campos adicionales (aunque vengan vacíos como
  /// `null`) para que vaciar un campo en la UI también se persista.
  Map<String, dynamic> _construirPayload(String justificacion) {
    String? vacioComoNulo(TextEditingController c) {
      final t = c.text.trim();
      return t.isEmpty ? null : t;
    }

    return <String, dynamic>{
      'documento': vacioComoNulo(_documentoCtrl),
      'guia_sunagro': vacioComoNulo(_guiaCtrl),
      'medida': vacioComoNulo(_medidaCtrl),
      'flete': vacioComoNulo(_fleteCtrl),
      'costo_flete': _parse(_costoFleteCtrl),
      'observaciones': vacioComoNulo(_observacionesCtrl),
      'peso_neto_declarado': _parse(_pesoDeclaradoCtrl),
      'densidad': _parse(_densidadCtrl),
      'litros': _parse(_litrosCtrl),
      'unidades': _parse(_unidadesCtrl),
      'justificacion': justificacion,
    };
  }

  /// ¿Hay algún cambio real frente a lo que trae el boleto?
  bool _hayCambios() {
    final w = widget.boleto;
    return _documentoCtrl.text.trim() != (w.documento ?? '') ||
        _guiaCtrl.text.trim() != (w.guiaSunagro ?? '') ||
        _medidaCtrl.text.trim() != (w.medida ?? '') ||
        _fleteCtrl.text.trim() != (w.flete ?? '') ||
        _costoFleteCtrl.text.trim() != _num(w.costoFlete) ||
        _observacionesCtrl.text.trim() != (w.observaciones ?? '') ||
        _pesoDeclaradoCtrl.text.trim() != _num(w.pesoNetoDeclarado) ||
        _densidadCtrl.text.trim() != _num(w.densidad) ||
        _litrosCtrl.text.trim() != _num(w.litros) ||
        _unidadesCtrl.text.trim() != _num(w.unidades);
  }

  Future<void> _guardar() async {
    final justificacion = _justificacionCtrl.text.trim();
    if (justificacion.length < 10) {
      setState(() => _error = 'edit_ticket_justification_hint'.tr());
      _justificacionFocus.requestFocus();
      return;
    }
    if (!_hayCambios()) {
      setState(() => _error = 'edit_ticket_no_changes'.tr());
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });

    try {
      final repo = di.sl<WeighingRepository>();
      final actualizado = await repo.updateWeighing(
        widget.boleto.boleto,
        _construirPayload(justificacion),
      );
      if (!mounted) return;
      // El backend incrementa `ediciones_count`; se muestra el número resultante
      // (1 si el listado venía sin el campo).
      final numero = _historial.length + 1;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('edit_ticket_ok'.tr(null, [numero.toString()])),
            backgroundColor: SwsColors.success,
          ),
        );
      Navigator.of(context).pop(true);
      // `actualizado` se descarta: quien abrió el diálogo recarga el listado.
      debugPrint('Boleto ${actualizado.boleto} editado (edición $numero)');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = e is EdicionRequiereConexionException
            ? 'edit_ticket_needs_connection'.tr()
            : e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w = widget.boleto;
    final ancho = MediaQuery.of(context).size.width;
    final esAngosto = ancho < 720;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.edit_note, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'edit_ticket_title'.tr(),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Chip(
            visualDensity: VisualDensity.compact,
            label: Text(
              w.numeroBoleto ?? w.boleto,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: esAngosto ? ancho * 0.9 : 720,
        child: _esAnulado
            ? _avisoAnulado(theme)
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _resumenBoleto(theme),
                    const SizedBox(height: 12),
                    _notaPesos(theme),
                    const SizedBox(height: 14),
                    _campos(theme, esAngosto),
                    const SizedBox(height: 14),
                    Divider(color: theme.colorScheme.outlineVariant),
                    const SizedBox(height: 8),
                    _campoJustificacion(theme),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      _avisoError(theme),
                    ],
                    const SizedBox(height: 14),
                    Divider(color: theme.colorScheme.outlineVariant),
                    const SizedBox(height: 8),
                    _seccionHistorial(theme),
                  ],
                ),
              ),
      ),
      actions: _esAnulado
          ? [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('close'.tr()),
              ),
            ]
          : [
              TextButton(
                onPressed:
                    _guardando ? null : () => Navigator.of(context).pop(false),
                child: Text('cancel'.tr()),
              ),
              FilledButton.icon(
                onPressed: _guardando ? null : _guardar,
                icon: _guardando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text('edit_ticket_save'.tr()),
              ),
            ],
    );
  }

  Widget _resumenBoleto(ThemeData theme) {
    final w = widget.boleto;
    final partes = <String>[
      if (w.productoNombre != null) w.productoNombre!,
      if (w.transporteNombre != null) w.transporteNombre!,
      if (w.conductorNombre != null) w.conductorNombre!,
      if (w.pesoNeto != null) '${_num(w.pesoNeto)} kg',
    ];
    return Row(
      children: [
        Icon(Icons.receipt_long_outlined,
            size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            partes.isEmpty ? w.boleto : partes.join('  ·  '),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        _chipEstado(theme),
      ],
    );
  }

  Widget _chipEstado(ThemeData theme) {
    final w = widget.boleto;
    final color = w.isAnulado
        ? SwsColors.danger
        : w.isClosed
            ? SwsColors.success
            : SwsColors.warning;
    final texto = w.isAnulado
        ? 'status_annulled'.tr()
        : w.isClosed
            ? 'status_closed'.tr()
            : w.isPendingSync || w.isOpen
                ? 'status_pending'.tr()
                : w.estadoBoleto;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colorDeEstadoLegible(context, color).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorDeEstadoLegible(context, color)),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: colorDeEstadoLegible(context, color),
        ),
      ),
    );
  }

  Widget _avisoAnulado(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          const Icon(Icons.block, color: SwsColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'edit_ticket_annulled'.tr(),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _notaPesos(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline,
              size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'edit_ticket_readonly_info'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _campo(TextEditingController c, String label, IconData icon,
      {bool numerico = false, int flex = 1}) {
    return Expanded(
      flex: flex,
      child: TextField(
        controller: c,
        keyboardType: numerico
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        inputFormatters: numerico
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
            : null,
        decoration: InputDecoration(
          labelText: label.tr(),
          prefixIcon: Icon(icon, size: 18),
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _campos(ThemeData theme, bool esAngosto) {
    // Etiquetas por clave (se traducen es/en/pt igual que el resto de la UI).
    final f1 = _campo(_documentoCtrl, 'field_documento', Icons.description_outlined);
    final f2 = _campo(_guiaCtrl, 'field_guia_sunagro', Icons.qr_code_outlined);
    final f3 = _campo(_medidaCtrl, 'field_medida', Icons.straighten);
    final f4 = _campo(_unidadesCtrl, 'field_unidades', Icons.numbers,
        numerico: true);
    final f5 = _campo(_densidadCtrl, 'field_densidad', Icons.water_drop_outlined,
        numerico: true);
    final f6 =
        _campo(_pesoDeclaradoCtrl, 'field_peso_declarado', Icons.scale_outlined,
            numerico: true);
    final f7 = _campo(_fleteCtrl, 'field_flete', Icons.local_shipping_outlined);
    final f8 = _campo(_costoFleteCtrl, 'field_costo_flete', Icons.attach_money,
        numerico: true);
    final f9 = _campo(_litrosCtrl, 'measure_litros', Icons.local_drink_outlined,
        numerico: true);

    Widget fila(List<Widget> hijos) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < hijos.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                hijos[i],
              ],
            ],
          ),
        );

    Widget observaciones() => TextField(
          controller: _observacionesCtrl,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: 'observations'.tr(),
            prefixIcon: const Icon(Icons.notes_outlined, size: 18),
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        );

    if (esAngosto) {
      return Column(
        children: [
          for (final campo in [f1, f2, f3, f4, f5, f6, f7, f8, f9])
            fila([campo]),
          observaciones(),
        ],
      );
    }

    return Column(
      children: [
        fila([f1, f2, f3]),
        fila([f4, f5, f6]),
        fila([f7, f8, f9]),
        Align(
          alignment: Alignment.centerLeft,
          child: observaciones(),
        ),
      ],
    );
  }

  Widget _campoJustificacion(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.edit_note, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              'edit_ticket_justification'.tr(),
              style: theme.textTheme.titleSmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _justificacionCtrl,
          focusNode: _justificacionFocus,
          maxLength: 500,
          maxLines: 2,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          decoration: InputDecoration(
            hintText: 'edit_ticket_justification_hint'.tr(),
            border: const OutlineInputBorder(),
            isDense: true,
            counterStyle: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _avisoError(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: SwsColors.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SwsColors.danger.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: SwsColors.danger, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorDeEstadoLegible(context, SwsColors.danger),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _seccionHistorial(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.history, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              'edit_ticket_history'.tr(),
              style: theme.textTheme.titleSmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_cargandoHistorial)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_historial.isEmpty)
          Text(
            'edit_ticket_no_editions'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _historial.length,
              separatorBuilder: (_, __) => const Divider(height: 12),
              itemBuilder: (_, i) => _filaEdicion(theme, _historial[i]),
            ),
          ),
      ],
    );
  }

  Widget _filaEdicion(ThemeData theme, BoletoEdicion e) {
    final quien = e.usuarioNombre?.isNotEmpty == true
        ? e.usuarioNombre!
        : (e.rolUsuario ?? '—');
    final campos = e.camposCambiados;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'edit_ticket_edition_n'.tr(null, [e.edicionNumero.toString()]),
              style: theme.textTheme.labelLarge,
            ),
            const Spacer(),
            Text(
              _fechaHora(e.fechaEdicion),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'edit_ticket_by'.tr(null, [quien]),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(e.justificacion, style: theme.textTheme.bodyMedium),
        if (campos.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'edit_ticket_fields'.tr(null, [campos.join(', ')]),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }

  String _fechaHora(DateTime utc) {
    final local = utc.toLocal();
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(local.day)}/${dos(local.month)}/${local.year} '
        '${dos(local.hour)}:${dos(local.minute)}';
  }
}
