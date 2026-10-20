// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 25010 (Usabilidad/Accesibilidad)
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/config/app_config.dart';
import '../../core/i18n/translations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand_text.dart';
import '../../data/datasources/remote/api_client.dart';
import '../../injection.dart' as di;
import '../providers/bloc/auth/auth_bloc.dart';
import '../providers/bloc/sync/sync_bloc.dart' hide SyncWeighingsEvent;
import '../providers/bloc/weighing/weighing_bloc.dart';
import 'notification_bell.dart';

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
    String? empresaNombre;
    String? empresaRif;
    String? empresaDireccion;
    String empresaLogoUrl = '';

    if (authState is AuthAuthenticated) {
      nombre = authState.user.nombre;
      email = authState.user.email;
      rol = authState.user.rol;
      empresaNombre = authState.user.empresaNombre;
      empresaRif = authState.user.empresaRif;
      empresaDireccion = authState.user.empresaDireccion;
      // URL del logo de empresa (puede venir vacía si no hay logo)
      empresaLogoUrl = authState.user.logoUrl ?? '';
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
          empresaNombre: empresaNombre,
          empresaRif: empresaRif,
          empresaDireccion: empresaDireccion,
          empresaLogoUrl: empresaLogoUrl, // ← AGREGADO
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
  final String? empresaNombre;
  final String? empresaRif;
  final String? empresaDireccion;
  final String empresaLogoUrl; // ← AGREGADO
  final bool compacto;
  final VoidCallback onToggleSidebar;
  final VoidCallback onLogout;
  final VoidCallback? onOpenConfig;

  const _TopRow({
    required this.nombre,
    required this.email,
    required this.rol,
    required this.empresaNombre,
    required this.empresaRif,
    required this.empresaDireccion,
    required this.empresaLogoUrl, // ← AGREGADO
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
          // ── ZONA IZQUIERDA: menú + logo ─────────────────────────
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.white70),
            onPressed: onToggleSidebar,
            tooltip: compacto
                ? 'Menú (Navegación)'
                : 'Toggle Sidebar (Ctrl+B / F10)',
          ),

          // BrandText SIEMPRE visible (tamaño reducido en móvil)
          BrandText(size: compacto ? 14 : 18),

          // ── ZONA CENTRAL: información de la empresa ─────────────
          // Ocupa todo el espacio flexible y centra su contenido.
          Expanded(
            child: (empresaNombre != null && empresaNombre!.isNotEmpty)
                ? Center(
                    child: _buildEmpresaInfo(compacto: compacto),
                  )
                : const SizedBox.shrink(),
          ),

          // ── ZONA DERECHA: estado + sync + usuario ───────────────
          const _HealthStatusBadge(),

          IconButton(
            tooltip: AppTranslations.tr('sync_btn',
                langCode: Localizations.localeOf(context).languageCode),
            icon: const Icon(Icons.sync_outlined, color: Colors.white70),
            onPressed: () {
              context.read<WeighingBloc>().add(SyncWeighingsEvent());
            },
          ),

          const NotificationBell(),

          const SizedBox(width: 4),

          if (nombre != null || email != null)
            _buildUserProfile(context, compacto: compacto, logoUrl: empresaLogoUrl),
        ],
      ),
    );
  }

  /// Bloque de la empresa:
  ///   NOMBRE EMPRESA - RIF
  ///        DIRECCION
  Widget _buildEmpresaInfo({required bool compacto}) {
    final tieneRif = empresaRif != null && empresaRif!.isNotEmpty;
    final linea1 =
        '${empresaNombre!}${tieneRif ? ' - $empresaRif' : ''}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          linea1,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: compacto ? 11.5 : 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        if (!compacto &&
            empresaDireccion != null &&
            empresaDireccion!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              empresaDireccion!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10.5,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildUserProfile(BuildContext context, {required bool compacto, required String logoUrl}) {
    final iniciales = _iniciales(nombre ?? email ?? '');
    // Resuelve URL absoluta si es relativa
    final resolvedLogoUrl = logoUrl.isNotEmpty ? di.sl<ApiClient>().mediaUrl(logoUrl) : '';

    Widget inicialesAvatar(String txt) => CircleAvatar(
      backgroundColor: Colors.white.withValues(alpha: 0.16),
      child: Text(
        txt,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    // Widget que muestra o el logo de empresa o las iniciales
    Widget avatarContent() {
      if (resolvedLogoUrl.isNotEmpty) {
        // Intenta mostrar el logo de la empresa NetworkImage
        // Si falla, cae a iniciales en el errorBuilder
        return ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: Image.network(
            resolvedLogoUrl,
            width: 34,
            height: 34,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                inicialesAvatar(iniciales),
          ),
        );
      }
      return inicialesAvatar(iniciales);
    }

    // ── Móvil: solo avatar + logout ──────────────────────────────────
    if (compacto) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onOpenConfig,
            child: avatarContent(),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white70, size: 18),
            onPressed: onLogout,
            tooltip: AppTranslations.tr('logout_btn',
                langCode: Localizations.localeOf(context).languageCode),
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
            avatarContent(),
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
              tooltip: AppTranslations.tr('logout_btn',
                  langCode: Localizations.localeOf(context).languageCode),
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
    final lang = Localizations.localeOf(context).languageCode;
    return BlocBuilder<SyncBloc, SyncState>(
      builder: (context, state) {
        final online = state.isOnline;
        final modoOffline = AppConfig.offline;
        final (mensaje, color) = modoOffline
            ? (
                AppTranslations.tr('tooltip_no_network', langCode: lang),
                SwsColors.warning
              )
            : (
                online
                    ? AppTranslations.tr('tooltip_online', langCode: lang)
                    : AppTranslations.tr('tooltip_offline', langCode: lang),
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
                    modoOffline
                        ? AppTranslations.tr('status_no_network', langCode: lang)
                        : (online
                            ? AppTranslations.tr('status_online', langCode: lang)
                            : AppTranslations.tr(
                                'status_offline', langCode: lang)),
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
