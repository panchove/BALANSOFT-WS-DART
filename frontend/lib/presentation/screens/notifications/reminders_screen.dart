import 'package:flutter/material.dart';

import '../../../core/i18n/translations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/notification_repository.dart';
import '../../../domain/entities/notification.dart';
import '../../../injection.dart' as di;

/// Pantalla de recordatorios de la estación (solo ADMIN).
///
/// Un recordatorio es texto libre + fecha/hora (con repetición opcional). El
/// **programador del WServer** dispara la notificación cuando vence, incluso
/// con la app Flutter cerrada; esta pantalla solo administra el CRUD.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key, this.repository});

  /// Inyectable para los tests; por defecto, el registrado en el contenedor.
  final NotificationRepository? repository;

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  late final NotificationRepository _repo;

  List<Reminder> _items = const [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? di.sl<NotificationRepository>();
    _cargar();
  }

  String _tr(String clave) => AppTranslations.tr(
        clave,
        langCode: Localizations.localeOf(context).languageCode,
      );

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final items = await _repo.listarRecordatorios();
      if (!mounted) return;
      setState(() {
        _items = items;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar los recordatorios';
      });
    }
  }

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _abrirFormulario({Reminder? existente}) async {
    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _RecordatorioDialog(recordatorio: existente),
    );
    if (resultado == null) return;
    try {
      if (existente == null) {
        await _repo.crearRecordatorio(
          titulo: resultado['titulo'] as String,
          mensaje: resultado['mensaje'] as String?,
          programadaPara: resultado['programada_para'] as DateTime,
          recurrencia: resultado['recurrencia'] as String,
        );
        _aviso(_tr('notificaciones_creado'));
      } else {
        await _repo.actualizar(
          existente.id,
          titulo: resultado['titulo'] as String,
          mensaje: resultado['mensaje'] as String?,
          programadaPara: resultado['programada_para'] as DateTime,
          recurrencia: resultado['recurrencia'] as String,
        );
        _aviso(_tr('notificaciones_actualizado'));
      }
      await _cargar();
    } catch (_) {
      _aviso(_tr('notificaciones_error'));
    }
  }

  Future<void> _alternarActivo(Reminder r) async {
    try {
      await _repo.actualizar(r.id, activo: !r.activo);
      await _cargar();
    } catch (_) {
      _aviso(_tr('notificaciones_error'));
    }
  }

  Future<void> _probar(Reminder r) async {
    try {
      await _repo.probarRecordatorio(r.id);
      _aviso(_tr('notificaciones_aviso_prueba'));
    } catch (_) {
      _aviso(_tr('notificaciones_error'));
    }
  }

  Future<void> _eliminar(Reminder r) async {
    final confirma = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(_tr('notificaciones_recordatorios')),
        content: Text(_tr('notificaciones_confirmar_eliminar')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: Text(_tr('notificaciones_cancelar')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SwsColors.danger),
            onPressed: () => Navigator.of(c).pop(true),
            child: Text(_tr('notificaciones_eliminar')),
          ),
        ],
      ),
    );
    if (confirma != true) return;
    try {
      await _repo.eliminar(r.id);
      _aviso(_tr('notificaciones_eliminado'));
      await _cargar();
    } catch (_) {
      _aviso(_tr('notificaciones_error'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_tr('notificaciones_recordatorios'))),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('recordatorio_nuevo_btn'),
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.add_alarm),
        label: Text(_tr('notificaciones_nuevo_recordatorio')),
      ),
      body: _cuerpo(),
    );
  }

  Widget _cuerpo() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _cargar,
              child: Text(_tr('notificaciones_reintentar')),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(child: Text(_tr('notificaciones_sin_recordatorios')));
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) => _fila(_items[i]),
    );
  }

  Widget _fila(Reminder r) {
    final local = r.programadaPara.toLocal();
    final fecha = '${_dos(local.day)}/${_dos(local.month)}/${local.year} '
        '${_dos(local.hour)}:${_dos(local.minute)}';
    return ListTile(
      key: Key('recordatorio_${r.id}'),
      leading: Icon(
        r.activo ? Icons.alarm_on : Icons.alarm_off,
        color: r.activo ? SwsColors.success : Theme.of(context).disabledColor,
      ),
      title: Text(r.titulo),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (r.mensaje != null && r.mensaje!.trim().isNotEmpty)
            Text(r.mensaje!),
          const SizedBox(height: 4),
          Text(
            '$fecha · ${_textoRecurrencia(r.recurrencia)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: Key('recordatorio_probar_${r.id}'),
            tooltip: _tr('notificaciones_probar_ahora'),
            icon: const Icon(Icons.play_arrow),
            onPressed: () => _probar(r),
          ),
          IconButton(
            key: Key('recordatorio_editar_${r.id}'),
            tooltip: _tr('notificaciones_guardar'),
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _abrirFormulario(existente: r),
          ),
          IconButton(
            key: Key('recordatorio_eliminar_${r.id}'),
            tooltip: _tr('notificaciones_eliminar'),
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _eliminar(r),
          ),
          Switch(
            key: Key('recordatorio_activo_${r.id}'),
            value: r.activo,
            onChanged: (_) => _alternarActivo(r),
          ),
        ],
      ),
    );
  }

  String _textoRecurrencia(String recurrencia) {
    switch (recurrencia) {
      case 'daily':
        return _tr('notificaciones_recurrencia_daily');
      case 'weekly':
        return _tr('notificaciones_recurrencia_weekly');
      case 'monthly':
        return _tr('notificaciones_recurrencia_monthly');
      default:
        return _tr('notificaciones_recurrencia_none');
    }
  }

  static String _dos(int v) => v.toString().padLeft(2, '0');
}

/// Formulario de alta/edición de un recordatorio.
class _RecordatorioDialog extends StatefulWidget {
  const _RecordatorioDialog({this.recordatorio});

  final Reminder? recordatorio;

  @override
  State<_RecordatorioDialog> createState() => _RecordatorioDialogState();
}

class _RecordatorioDialogState extends State<_RecordatorioDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titulo;
  late final TextEditingController _mensaje;
  late DateTime _fecha;
  late String _recurrencia;

  @override
  void initState() {
    super.initState();
    final r = widget.recordatorio;
    _titulo = TextEditingController(text: r?.titulo ?? '');
    _mensaje = TextEditingController(text: r?.mensaje ?? '');
    _fecha = (r?.programadaPara.toLocal() ?? DateTime.now().add(const Duration(minutes: 5)));
    _recurrencia = r?.recurrencia ?? 'none';
  }

  @override
  void dispose() {
    _titulo.dispose();
    _mensaje.dispose();
    super.dispose();
  }

  String _tr(String clave) => AppTranslations.tr(
        clave,
        langCode: Localizations.localeOf(context).languageCode,
      );

  Future<void> _elegirFecha() async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (elegida == null || !mounted) return;
    setState(() {
      _fecha = DateTime(
        elegida.year,
        elegida.month,
        elegida.day,
        _fecha.hour,
        _fecha.minute,
      );
    });
  }

  Future<void> _elegirHora() async {
    final elegida = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_fecha),
    );
    if (elegida == null || !mounted) return;
    setState(() {
      _fecha = DateTime(
        _fecha.year,
        _fecha.month,
        _fecha.day,
        elegida.hour,
        elegida.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final fecha = '${_dos(_fecha.day)}/${_dos(_fecha.month)}/${_fecha.year}';
    final hora = '${_dos(_fecha.hour)}:${_dos(_fecha.minute)}';
    return AlertDialog(
      title: Text(_tr(widget.recordatorio == null
          ? 'notificaciones_nuevo_recordatorio'
          : 'notificaciones_recordatorios')),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const Key('recordatorio_titulo_field'),
                  controller: _titulo,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: _tr('notificaciones_titulo_campo'),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? _tr('notificaciones_titulo_obligatorio')
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('recordatorio_mensaje_field'),
                  controller: _mensaje,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: _tr('notificaciones_mensaje_campo'),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('recordatorio_fecha_btn'),
                        onPressed: _elegirFecha,
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text('${_tr('notificaciones_fecha')}: $fecha'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      key: const Key('recordatorio_hora_btn'),
                      onPressed: _elegirHora,
                      icon: const Icon(Icons.access_time),
                      label: Text(hora),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('recordatorio_recurrencia_field'),
                  initialValue: _recurrencia,
                  decoration: InputDecoration(
                    labelText: _tr('notificaciones_recurrencia'),
                  ),
                  items: [
                    for (final r in Reminder.recurrencias)
                      DropdownMenuItem(
                        value: r,
                        child: Text(_tr('notificaciones_recurrencia_$r')),
                      ),
                  ],
                  onChanged: (v) => setState(() => _recurrencia = v ?? 'none'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_tr('notificaciones_cancelar')),
        ),
        FilledButton(
          key: const Key('recordatorio_guardar_btn'),
          onPressed: _guardar,
          child: Text(_tr('notificaciones_guardar')),
        ),
      ],
    );
  }

  void _guardar() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final mensaje = _mensaje.text.trim();
    Navigator.of(context).pop({
      'titulo': _titulo.text.trim(),
      'mensaje': mensaje.isEmpty ? null : mensaje,
      'programada_para': _fecha,
      'recurrencia': _recurrencia,
    });
  }

  static String _dos(int v) => v.toString().padLeft(2, '0');
}
