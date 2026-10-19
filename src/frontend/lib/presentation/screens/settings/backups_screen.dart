import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/i18n/translations.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../injection.dart' as di;

/// Pantalla de Respaldos de estación (REQ-NF-BKP-001/002/003).
///
/// Lista los snapshots de la empresa (solo ADMIN), permite crear uno al
/// instante, descargar el `.json.gz` y restaurarlo. La restauración exige
/// confirmación explícita y el backend crea siempre un respaldo de seguridad
/// previo. La entrada está visible únicamente en estaciones SERVIDOR.
class BackupsScreen extends StatefulWidget {
  const BackupsScreen({super.key, this.apiClient});

  /// Inyectable para tests; en producción usa el singleton compartido.
  final ApiClient? apiClient;

  @override
  State<BackupsScreen> createState() => _BackupsScreenState();
}

/// Metadatos de un snapshot tal como los devuelve `GET /api/v1/backups`.
class _BackupItem {
  _BackupItem.fromJson(Map<String, dynamic> json)
      : archivo = json['archivo'] as String? ?? '',
        creadoEn = DateTime.tryParse(json['creado_en'] as String? ?? ''),
        motivo = json['motivo'] as String? ?? '',
        tamanoBytes = (json['tamano_bytes'] as num?)?.toInt() ?? 0,
        conteos = (json['conteos'] as Map<String, dynamic>? ?? const {})
            .map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0));

  final String archivo;
  final DateTime? creadoEn;
  final String motivo;
  final int tamanoBytes;
  final Map<String, int> conteos;

  String get fechaLocal {
    final d = creadoEn?.toLocal();
    if (d == null) return '';
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${dos(d.month)}-${dos(d.day)} '
        '${dos(d.hour)}:${dos(d.minute)}';
  }

  String get tamanoLegible {
    if (tamanoBytes < 1024) return '$tamanoBytes B';
    if (tamanoBytes < 1024 * 1024) {
      return '${(tamanoBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(tamanoBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get conteoBoletos {
    // El backend emite las claves por nombre de tabla (`__tablename__`),
    // p. ej. `boletos_pesaje` (contrato BackupOut).
    final boletos = conteos['boletos_pesaje'];
    return boletos == null ? '' : '$boletos';
  }
}

class _BackupsScreenState extends State<BackupsScreen> {
  late final ApiClient _api;
  List<_BackupItem> _items = [];
  bool _cargando = true;
  bool _creando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = widget.apiClient ?? di.sl<ApiClient>();
    _cargar();
  }

  void _snack(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje)));
  }

  /// Mensaje accionable: prioriza el permiso (403) localizado; si no, usa
  /// el ``detail`` del backend (400/409…) y como último recurso el genérico.
  String _mensajeError(Object e) {
    if (e is DioException) {
      if (e.response?.statusCode == 403) {
        return 'backup_permiso_denegado'.tr();
      }
      final data = e.response?.data;
      if (data is Map && data['detail'] is String) {
        return data['detail'] as String;
      }
    }
    return 'backup_error'.tr();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final items = await _api.listarBackups();
      if (!mounted) return;
      setState(() {
        _items = items.map(_BackupItem.fromJson).toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = _mensajeError(e);
      });
    }
  }

  Future<void> _crearAhora() async {
    setState(() => _creando = true);
    try {
      await _api.crearBackupAuto();
      _snack('backup_creado'.tr());
      await _cargar();
    } catch (e) {
      _snack(_mensajeError(e));
    } finally {
      if (mounted) setState(() => _creando = false);
    }
  }

  Future<void> _descargar(_BackupItem item) async {
    try {
      final bytes = await _api.descargarBackup(item.archivo);
      if (bytes.isEmpty) throw Exception('vacio');
      final dir = await _directorioDescargas();
      final ruta =
          '${dir.path}${Platform.pathSeparator}${item.archivo}';
      await File(ruta).writeAsBytes(bytes, flush: true);
      _snack('${'backup_descargado'.tr()}\n$ruta');
    } catch (e) {
      _snack(_mensajeError(e));
    }
  }

  Future<Directory> _directorioDescargas() async {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      final d = await getDownloadsDirectory();
      if (d != null) return d;
    }
    return getApplicationDocumentsDirectory();
  }

  Future<void> _confirmarRestauracion(_BackupItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('backup_restaurar_titulo')),
        content: Text(ctx.tr('backup_restaurar_mensaje')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr('backup_cancelar')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('backup_confirmar')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _api.restaurarBackup(item.archivo, confirmar: true);
      _snack('backup_restaurado'.tr());
      await _cargar();
    } catch (e) {
      _snack(_mensajeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('backup_titulo'.tr())),
      body: _body(),
    );
  }

  Widget _body() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: _items.isEmpty ? _vacio() : _lista(),
    );
  }

  Widget _vacio() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 24),
        const Icon(Icons.backup_outlined, size: 64),
        const SizedBox(height: 12),
        Center(child: Text('backup_lista_vacia'.tr())),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Center(
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Center(child: _botonCrear()),
      ],
    );
  }

  Widget _lista() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _botonCrear(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 8),
        for (final item in _items) _tarjeta(item),
      ],
    );
  }

  Widget _botonCrear() {
    return FilledButton.icon(
      onPressed: _creando ? null : _crearAhora,
      icon: _creando
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.add),
      label: Text('backup_crear'.tr()),
    );
  }

  Widget _tarjeta(_BackupItem item) {
    final boletos = item.conteoBoletos;
    final subtitulo = [
      item.fechaLocal,
      item.tamanoLegible,
      if (boletos.isNotEmpty) '${'backup_boletos'.tr()}: $boletos',
    ].join(' • ');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.archive_outlined),
        title: Text(item.archivo, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitulo),
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              tooltip: 'backup_descargar'.tr(),
              icon: const Icon(Icons.download_outlined),
              onPressed: () => _descargar(item),
            ),
            IconButton(
              tooltip: 'backup_restaurar'.tr(),
              icon: const Icon(Icons.restore_outlined),
              onPressed: () => _confirmarRestauracion(item),
            ),
          ],
        ),
      ),
    );
  }
}