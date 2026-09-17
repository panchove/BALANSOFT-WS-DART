import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_text.dart';
import '../providers/bloc/auth/auth_bloc.dart';
import '../providers/bloc/sync/sync_bloc.dart' hide SyncWeighingsEvent;
import '../providers/bloc/weighing/weighing_bloc.dart';

/// Top navbar (HEAD) según docs/NAV.md.
/// Responsive: en móvil oculta texto de usuario/rol y el toggle sidebar.
class TopNavBar extends StatelessWidget {
  final VoidCallback onToggleSidebar;
  final VoidCallback onLogout;
  final VoidCallback? onOpenConfig;

  const TopNavBar({
    super.key,
    required this.onToggleSidebar,
    required this.onLogout,
    this.onOpenConfig,
  });

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    String? nombre;
    String? email;
    String? rol;
    if (authState is AuthAuthenticated) {
      nombre = authState.user.nombre;
      email = authState.user.email;
      rol = authState.user.rol;
    }

    final compacto = MediaQuery.sizeOf(context).width < 600;

    return Container(
      decoration: BoxDecoration(
        color: SwsColors.primary,
        // Borde inferior sutil para delimitar la barra
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1.0,
          ),
        ),
        // Sombra inferior para dar elevación y profundidad
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: _TopRow(
          nombre: nombre,
          email: email,
          rol: rol,
          compacto: compacto,
          onToggleSidebar: onToggleSidebar,
          onLogout: onLogout,
          onOpenConfig: onOpenConfig,
        ),
      ),
    );
  }
}

class _TopRow extends StatelessWidget {
  final String? nombre;
  final String? email;
  final String? rol;
  final bool compacto;
  final VoidCallback onToggleSidebar;
  final VoidCallback onLogout;
  final VoidCallback? onOpenConfig;

  const _TopRow({
    required this.nombre,
    required this.email,
    required this.rol,
    required this.compacto,
    required this.onToggleSidebar,
    required this.onLogout,
    this.onOpenConfig,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compacto ? 8 : 12,
        vertical: 6,
      ),
      child: Row(
        children: [
          // En móvil abre el menú de navegación lateral (mismas opciones
          // que el sidebar de desktop).
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.white70),
            onPressed: onToggleSidebar,
            tooltip: compacto ? 'Menú (Navegación)' : 'Toggle Sidebar (Ctrl+B / F10)',
          ),

          // BrandText SIEMPRE visible (tamaño reducido en móvil)
          BrandText(size: compacto ? 14 : 18),

          const Spacer(),

          // Estado del backend
          const _HealthStatusBadge(),

          // Botón de sincronizar
          IconButton(
            tooltip: 'Sincronizar',
            icon: const Icon(Icons.sync_outlined, color: Colors.white70),
            onPressed: () {
              context.read<WeighingBloc>().add(SyncWeighingsEvent());
            },
          ),

          const SizedBox(width: 4),

          // Perfil de usuario
          if (nombre != null || email != null)
            _buildUserProfile(compacto: compacto),
        ],
      ),
    );
  }

  Widget _buildUserProfile({required bool compacto}) {
    final iniciales = _iniciales(nombre ?? email ?? '');

    // ── Móvil: solo avatar + logout ──────────────────────────────────
    if (compacto) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onOpenConfig,
            child: CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white.withValues(alpha: 0.16),
              child: Text(
                iniciales,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white70, size: 18),
            onPressed: onLogout,
            tooltip: 'Cerrar Sesión',
            visualDensity: VisualDensity.compact,
          ),
        ],
      );
    }

    // ── Desktop/tablet: avatar + nombre + rol + logout ───────────────
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onOpenConfig,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: Colors.white.withValues(alpha: 0.16),
              child: Text(
                iniciales,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  nombre ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Rol: ${rol ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.white70, size: 18),
              onPressed: onLogout,
              tooltip: 'Cerrar Sesión',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  String _iniciales(String texto) {
    final partes =
        texto.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return '?';
    if (partes.length == 1) {
      return partes.first.characters.take(2).toString().toUpperCase();
    }
    return '${partes.first.characters.first}${partes.last.characters.first}'
        .toUpperCase();
  }
}

/// Indicador de estado del backend (online/offline) + botón de reintento.
class _HealthStatusBadge extends StatelessWidget {
  const _HealthStatusBadge();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SyncBloc, SyncState>(
      builder: (context, state) {
        final online = state is HealthOnline;
        final modoOffline = AppConfig.offline;
        final (mensaje, color) = modoOffline
            ? ('Estación en modo sin conexión', SwsColors.warning)
            : (
                online
                    ? 'Backend en línea'
                    : 'Backend sin conexión (toca para reintentar)',
                online ? SwsColors.success : SwsColors.danger,
              );
        return Tooltip(
          message: mensaje,
          child: InkWell(
            onTap: () => context.read<SyncBloc>().add(HealthCheckEvent()),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, size: 12, color: color),
                  const SizedBox(width: 6),
                  Text(
                    modoOffline ? 'Sin red' : (online ? 'Online' : 'Offline'),
                    style: TextStyle(fontSize: 12, color: color),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}