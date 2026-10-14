import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/i18n/translations.dart';
import '../../core/theme/app_theme.dart';
import '../providers/bloc/notifications/notifications_cubit.dart';
import '../screens/notifications/notification_center_screen.dart';

/// Campana del centro de notificaciones con contador de no leídas.
///
/// El contador lo refresca [NotificationsCubit] desde
/// `GET /api/v1/notificaciones/resumen`; los avisos los genera el WServer de la
/// estación (residente, incluso con esta app cerrada).
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    return BlocBuilder<NotificationsCubit, NotificationsState>(
      builder: (context, state) {
        final noLeidas = state.resumen.noLeidas;
        return IconButton(
          key: const Key('notificaciones_campana_btn'),
          tooltip: AppTranslations.tr('notificaciones_campana', langCode: lang),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const NotificationCenterScreen(),
              ),
            );
          },
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications_outlined, color: Colors.white70),
              if (noLeidas > 0)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    constraints: const BoxConstraints(minWidth: 16),
                    decoration: BoxDecoration(
                      color: SwsColors.danger,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: SwsColors.primary, width: 1),
                    ),
                    child: Text(
                      noLeidas > 99 ? '99+' : '$noLeidas',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
