import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/i18n/translations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/notification.dart';
import '../../providers/bloc/auth/auth_bloc.dart';
import '../../providers/bloc/notifications/notifications_cubit.dart';
import 'reminders_screen.dart';

/// Centro de notificaciones de la estación (bandeja de la campana).
///
/// Los avisos los genera el **WServer** (residente, incluso con esta app
/// cerrada): licencia por vencer, sincronización pendiente/fallida, boletos sin
/// cerrar, series por agotar y recordatorios. Aquí se leen y se archivan.
class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  bool _soloNoLeidas = false;
  bool _avisoMostrado = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<NotificationsCubit>().cargar();
    });
  }

  String _tr(String clave) => AppTranslations.tr(
        clave,
        langCode: Localizations.localeOf(context).languageCode,
      );

  bool get _esAdmin {
    final estado = context.read<AuthBloc>().state;
    if (estado is! AuthAuthenticated) return false;
    return estado.user.rol.toString().toUpperCase() == 'ADMIN';
  }

  Future<void> _cambiarFiltro(bool soloNoLeidas) async {
    setState(() => _soloNoLeidas = soloNoLeidas);
    await context
        .read<NotificationsCubit>()
        .cargar(soloNoLeidas: soloNoLeidas, filtro: null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('notificaciones_titulo')),
        actions: [
          IconButton(
            key: const Key('notif_marcar_todas_btn'),
            tooltip: _tr('notificaciones_marcar_todas'),
            icon: const Icon(Icons.done_all),
            onPressed: () async {
              await context.read<NotificationsCubit>().marcarTodasLeidas();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(_tr('notificaciones_marcar_todas'))),
                );
              }
            },
          ),
          if (_esAdmin)
            IconButton(
              key: const Key('notificaciones_recordatorios_btn'),
              tooltip: _tr('notificaciones_recordatorios'),
              icon: const Icon(Icons.alarm_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RemindersScreen()),
              ),
            ),
          if (_esAdmin)
            IconButton(
              key: const Key('notificaciones_probar_btn'),
              tooltip: _tr('notificaciones_probar'),
              icon: const Icon(Icons.notifications_active_outlined),
              onPressed: _probar,
            ),
        ],
      ),
      body: BlocConsumer<NotificationsCubit, NotificationsState>(
        listenWhen: (previo, actual) =>
            actual.error != null && actual.error != previo.error,
        listener: (context, state) {
          if (!_avisoMostrado) {
            _avisoMostrado = true;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(_tr('notificaciones_error'))),
            );
          }
        },
        builder: (context, state) {
          return Column(
            children: [
              _Filtros(
                soloNoLeidas: _soloNoLeidas,
                onCambio: _cambiarFiltro,
                tr: _tr,
              ),
              const Divider(height: 1),
              Expanded(child: _cuerpo(state)),
            ],
          );
        },
      ),
    );
  }

  Widget _cuerpo(NotificationsState state) {
    if (state.cargando && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.items.isEmpty) {
      return _vacio(
        icono: Icons.cloud_off_outlined,
        texto: _tr('notificaciones_error'),
        accion: TextButton(
          onPressed: () => context.read<NotificationsCubit>().cargar(),
          child: Text(_tr('notificaciones_reintentar')),
        ),
      );
    }
    if (state.items.isEmpty) {
      return _vacio(
        icono: Icons.notifications_none,
        texto: _soloNoLeidas
            ? _tr('notificaciones_sin_no_leidas')
            : _tr('notificaciones_vacio'),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: state.items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) => _NotificacionTile(
        notificacion: state.items[i],
        tr: _tr,
        onLeer: () =>
            context.read<NotificationsCubit>().marcarLeida(state.items[i].id),
        onArchivar: () =>
            context.read<NotificationsCubit>().archivar(state.items[i].id),
      ),
    );
  }

  Widget _vacio({required IconData icono, required String texto, Widget? accion}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 48, color: Theme.of(context).disabledColor),
          const SizedBox(height: 12),
          Text(texto, textAlign: TextAlign.center),
          if (accion != null) ...[const SizedBox(height: 8), accion],
        ],
      ),
    );
  }

  Future<void> _probar() async {
    final ok = await context.read<NotificationsCubit>().probar();
    if (!mounted || !ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_tr('notificaciones_aviso_prueba'))),
    );
  }
}

class _Filtros extends StatelessWidget {
  const _Filtros({
    required this.soloNoLeidas,
    required this.onCambio,
    required this.tr,
  });

  final bool soloNoLeidas;
  final ValueChanged<bool> onCambio;
  final String Function(String) tr;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          ChoiceChip(
            key: const Key('notificaciones_filtro_todas'),
            label: Text(tr('notificaciones_todas')),
            selected: !soloNoLeidas,
            onSelected: (_) => onCambio(false),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            key: const Key('notificaciones_filtro_no_leidas'),
            label: Text(tr('notificaciones_no_leidas')),
            selected: soloNoLeidas,
            onSelected: (_) => onCambio(true),
          ),
        ],
      ),
    );
  }
}

class _NotificacionTile extends StatelessWidget {
  const _NotificacionTile({
    required this.notificacion,
    required this.tr,
    required this.onLeer,
    required this.onArchivar,
  });

  final AppNotification notificacion;
  final String Function(String) tr;
  final VoidCallback onLeer;
  final VoidCallback onArchivar;

  static Color colorSeveridad(String severidad) {
    switch (severidad) {
      case 'critica':
        return SwsColors.danger;
      case 'alta':
        return SwsColors.warning;
      case 'media':
        return SwsColors.secondary;
      default:
        return SwsColors.info;
    }
  }

  static IconData iconoSeveridad(String severidad) {
    switch (severidad) {
      case 'critica':
        return Icons.error_outline;
      case 'alta':
        return Icons.warning_amber_outlined;
      case 'media':
        return Icons.info_outline;
      default:
        return Icons.notifications_outlined;
    }
  }

  static String textoSeveridad(String severidad, String Function(String) tr) {
    switch (severidad) {
      case 'critica':
        return tr('severidad_critica');
      case 'alta':
        return tr('severidad_alta');
      case 'media':
        return tr('severidad_media');
      default:
        return tr('severidad_info');
    }
  }

  @override
  Widget build(BuildContext context) {
    final noLeida = notificacion.estado == AppNotification.estadoNoLeida;
    final color = colorSeveridad(notificacion.severidad);
    final colorTexto = colorDeEstadoLegible(context, color);
    final local = notificacion.createdAt.toLocal();
    final fecha = '${_dos(local.day)}/${_dos(local.month)}/${local.year} '
        '${_dos(local.hour)}:${_dos(local.minute)}';

    return ListTile(
      key: Key('notificacion_${notificacion.id}'),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(iconoSeveridad(notificacion.severidad), color: colorTexto),
      ),
      title: Text(
        notificacion.titulo,
        style: TextStyle(
          fontWeight: noLeida ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (notificacion.mensaje != null &&
              notificacion.mensaje!.trim().isNotEmpty)
            Text(notificacion.mensaje!),
          const SizedBox(height: 4),
          Text(
            '$fecha · ${textoSeveridad(notificacion.severidad, tr)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (noLeida)
            IconButton(
              key: Key('notificacion_leer_${notificacion.id}'),
              tooltip: tr('notificaciones_marcar_leida'),
              icon: const Icon(Icons.done),
              onPressed: onLeer,
            ),
          IconButton(
            key: Key('notificacion_archivar_${notificacion.id}'),
            tooltip: tr('notificaciones_archivar'),
            icon: const Icon(Icons.archive_outlined),
            onPressed: onArchivar,
          ),
        ],
      ),
    );
  }

  static String _dos(int valor) => valor.toString().padLeft(2, '0');
}

/// Utilidad expuesta para los tests: color de la severidad.
Color colorSeveridadNotificacion(String severidad) =>
    _NotificacionTile.colorSeveridad(severidad);
