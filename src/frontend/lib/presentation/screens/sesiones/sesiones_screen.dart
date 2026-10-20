// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 25010 (Usabilidad/Accesibilidad)
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

import 'package:flutter/material.dart';

import '../../../core/i18n/translations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/mensaje_error.dart';
import '../../../data/repositories/sesiones_repository.dart';
import '../../../domain/entities/sesion_equipo.dart';
import '../../../injection.dart' as di;

/// Pantalla de **Sesiones y Equipos** (RB-12).
///
/// Es el mismo listado que ve la tutora en el servidor central
/// (`GET /api/v1/auth/sesiones`), pero desde la estación: el ADMIN de la cuenta
/// aprueba (con su rol de sesión) o rechaza los equipos que intentan operar.
///
/// Autoridad: el **servidor central**, no la estación. Sin la credencial
/// global (`_serverToken`) la pantalla no puede listar nada y lo explica.
///
/// Nombre deliberadamente distinto de «Dispositivos de Campo», que en WS es la
/// básculas/impresoras de la estación (no los equipos de la cuenta).
class SesionesScreen extends StatefulWidget {
  const SesionesScreen({super.key, this.repository});

  /// Inyectable para los tests; en producción sale del contenedor.
  final SesionesRepository? repository;

  @override
  State<SesionesScreen> createState() => _SesionesScreenState();
}

class _SesionesScreenState extends State<SesionesScreen> {
  late final SesionesRepository _repo = widget.repository ?? di.sl<SesionesRepository>();

  SesionesEquipo? _data;
  bool _cargando = true;
  bool _ocupado = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  String _tr(String clave, [List<String>? args]) => AppTranslations.tr(
        clave,
        langCode: Localizations.localeOf(context).languageCode,
        args: args,
      );

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final data = await _repo.listar();
      if (!mounted) return;
      setState(() {
        _data = data;
        _cargando = false;
      });
    } on StateError {
      // Sin credencial del servidor central: no es un fallo de red, es que la
      // sesión actual no trae token de servidor (login local/offline).
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = _tr('sesiones_sin_credencial');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = mensajeDeError(e, fallback: _tr('sesiones_error'));
      });
    }
  }

  Future<void> _aplicar(
    SesionEquipo equipo, {
    String? estado,
    String? rolSesion,
  }) async {
    setState(() => _ocupado = true);
    try {
      await _repo.actualizar(
        equipo.idDispositivo,
        estado: estado,
        rolSesion: rolSesion,
      );
      if (!mounted) return;
      final msg = estado == SesionEquipo.estadoRechazado
          ? _tr('sesiones_rechazado_msg')
          : _tr('sesiones_aprobado_msg');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensajeDeError(e, fallback: _tr('sesiones_error')))),
      );
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _aprobar(SesionEquipo equipo) async {
    var rol = equipo.rolSesion ?? 'OPERADOR';
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(_tr('sesiones_aprobar_titulo')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(equipo.nombreEquipo ?? equipo.hardwareId),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: const Key('sesiones_rol_dropdown'),
                initialValue: rol,
                decoration: InputDecoration(labelText: _tr('sesiones_rol_campo')),
                items: [
                  for (final r in SesionEquipo.rolesSesion)
                    DropdownMenuItem(value: r, child: Text(r)),
                ],
                onChanged: (v) {
                  if (v != null) setLocal(() => rol = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(_tr('cancel')),
            ),
            FilledButton(
              key: const Key('sesiones_confirmar_aprobar'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(_tr('sesiones_aprobar')),
            ),
          ],
        ),
      ),
    );
    if (confirmar != true) return;
    await _aplicar(
      equipo,
      estado: SesionEquipo.estadoAprobado,
      rolSesion: rol,
    );
  }

  Future<void> _rechazar(SesionEquipo equipo) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_tr('sesiones_rechazar')),
        content: Text(_tr('sesiones_confirmar_rechazo')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_tr('cancel')),
          ),
          FilledButton(
            key: const Key('sesiones_confirmar_rechazar'),
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: SwsColors.danger),
            child: Text(_tr('sesiones_rechazar')),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    await _aplicar(equipo, estado: SesionEquipo.estadoRechazado);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('sesiones_titulo')),
        actions: [
          IconButton(
            key: const Key('sesiones_refrescar_btn'),
            tooltip: _tr('sesiones_reintentar'),
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cuerpo(),
    );
  }

  Widget _cuerpo() {
    if (_cargando && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _data == null) {
      return _mensaje(
        icono: Icons.cloud_off_outlined,
        texto: _error!,
        accion: TextButton(
          key: const Key('sesiones_reintentar_btn'),
          onPressed: _cargar,
          child: Text(_tr('sesiones_reintentar')),
        ),
      );
    }
    final data = _data;
    if (data == null || data.items.isEmpty) {
      return _mensaje(
        icono: Icons.devices_other_outlined,
        texto: _tr('sesiones_vacio'),
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: data.items.length + 1,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          if (i == 0) return _resumen(data);
          final equipo = data.items[i - 1];
          return _EquipoTile(
            equipo: equipo,
            ocupado: _ocupado,
            tr: _tr,
            onAprobar: () => _aprobar(equipo),
            onRechazar: () => _rechazar(equipo),
          );
        },
      ),
    );
  }

  Widget _resumen(SesionesEquipo data) {
    final max = data.maxEquipos;
    final texto = max == null
        ? _tr('sesiones_ilimitado')
        : '$max';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          const Icon(Icons.group_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _tr('sesiones_resumen', [texto]),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          if (data.pendientes > 0)
            Chip(
              key: const Key('sesiones_pendientes_chip'),
              visualDensity: VisualDensity.compact,
              backgroundColor: SwsColors.warning.withValues(alpha: 0.15),
              label: Text(
                _tr('sesiones_pendientes', ['${data.pendientes}']),
              ),
            ),
        ],
      ),
    );
  }

  Widget _mensaje({
    required IconData icono,
    required String texto,
    Widget? accion,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 48, color: Theme.of(context).disabledColor),
            const SizedBox(height: 12),
            Text(texto, textAlign: TextAlign.center),
            if (accion != null) ...[const SizedBox(height: 8), accion],
          ],
        ),
      ),
    );
  }
}

class _EquipoTile extends StatelessWidget {
  const _EquipoTile({
    required this.equipo,
    required this.ocupado,
    required this.tr,
    required this.onAprobar,
    required this.onRechazar,
  });

  final SesionEquipo equipo;
  final bool ocupado;
  final String Function(String clave, [List<String>? args]) tr;
  final VoidCallback onAprobar;
  final VoidCallback onRechazar;

  static Color colorEstado(String estado) {
    switch (estado) {
      case SesionEquipo.estadoPendiente:
        return SwsColors.warning;
      case SesionEquipo.estadoRechazado:
        return SwsColors.danger;
      default:
        return SwsColors.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = colorEstado(equipo.estado);
    // Texto/icono legibles sobre el tinte al 15 % del propio color de estado
    // (en tema claro el color puro no alcanza WCAG AA).
    final colorTexto = colorDeEstadoLegible(context, color);
    final subsistema = <String>[
      if (equipo.sistemaOperativo != null && equipo.sistemaOperativo!.isNotEmpty)
        equipo.sistemaOperativo!,
      if (equipo.versionApp != null && equipo.versionApp!.isNotEmpty)
        'v${equipo.versionApp}',
      equipo.rolDispositivo,
    ].join(' · ');

    return ListTile(
      key: Key('sesion_equipo_${equipo.idDispositivo}'),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(
          equipo.esDueno ? Icons.verified_user_outlined : Icons.computer_outlined,
          color: colorTexto,
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              equipo.nombreEquipo?.isNotEmpty == true
                  ? equipo.nombreEquipo!
                  : equipo.hardwareId,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (equipo.esDueno) ...[
            const SizedBox(width: 8),
            _Etiqueta(texto: tr('sesiones_titular_badge')),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(equipo.hardwareId, style: Theme.of(context).textTheme.bodySmall),
          Text(subsistema, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  tr(_claveEstado(equipo.estado)),
                  style: TextStyle(color: colorTexto, fontSize: 12),
                ),
              ),
              if (equipo.rolSesion != null) ...[
                const SizedBox(width: 8),
                Text(
                  '${tr('sesiones_rol_campo')}: ${equipo.rolSesion}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ],
      ),
      trailing: equipo.esDueno || !equipo.esEditable
          ? Tooltip(
              message: tr('sesiones_titular_no_editable'),
              child: const Icon(Icons.lock_outline),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: Key('sesion_aprobar_${equipo.idDispositivo}'),
                  tooltip: tr('sesiones_aprobar'),
                  icon: const Icon(Icons.check_circle_outline),
                  color: SwsColors.success,
                  onPressed: ocupado ? null : onAprobar,
                ),
                IconButton(
                  key: Key('sesion_rechazar_${equipo.idDispositivo}'),
                  tooltip: tr('sesiones_rechazar'),
                  icon: const Icon(Icons.block_outlined),
                  color: SwsColors.danger,
                  onPressed: ocupado ? null : onRechazar,
                ),
              ],
            ),
    );
  }

  static String _claveEstado(String estado) {
    switch (estado) {
      case SesionEquipo.estadoPendiente:
        return 'sesiones_estado_pendiente';
      case SesionEquipo.estadoRechazado:
        return 'sesiones_estado_rechazado';
      default:
        return 'sesiones_estado_aprobado';
    }
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: SwsColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(texto, style: const TextStyle(fontSize: 12)),
    );
  }
}
