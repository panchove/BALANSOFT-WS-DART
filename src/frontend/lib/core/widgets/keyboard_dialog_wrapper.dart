// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 25010 (Usabilidad/Accesibilidad)
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Marca interna: el diálogo gestiona ENTER/ESC con [KeyboardDialogWrapper].
///
/// El manejador global de teclado (`DialogKeyboard`, usado por `HomeShell`)
/// consulta esta marca para ceder el paso cuando el propio wrapper ya tiene
/// una acción asignada, evitando disparar la acción dos veces.
class TeclasDialogoScope extends InheritedWidget {
  /// El wrapper tiene `onEnter` asignado → ENTER lo resuelve el wrapper.
  final bool manejaEnter;

  /// El wrapper tiene `onEscape` asignado → ESC lo resuelve el wrapper.
  final bool manejaEscape;

  const TeclasDialogoScope({
    super.key,
    required this.manejaEnter,
    required this.manejaEscape,
    required super.child,
  });

  /// Lookup sin registrar dependencia (seguro fuera de `build`, p. ej. en
  /// manejadores de teclado).
  static TeclasDialogoScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TeclasDialogoScope>();

  @override
  bool updateShouldNotify(TeclasDialogoScope oldWidget) =>
      oldWidget.manejaEnter != manejaEnter ||
      oldWidget.manejaEscape != manejaEscape;
}

/// Wrapper reutilizable para añadir manejo de teclado (ENTER/ESC) a diálogos.
///
/// Uso típico:
/// ```dart
/// KeyboardDialogWrapper(
///   onEnter: () => _confirmar(),
///   onEscape: () => Navigator.of(context).pop(),
///   child: AlertDialog(...),
/// )
/// ```
///
/// Los diálogos envueltos con este wrapper también quedan marcados con
/// [TeclasDialogoScope] para que los atajos globales no compitan con las
/// acciones asignadas aquí.
class KeyboardDialogWrapper extends StatelessWidget {
  final Widget child;
  final VoidCallback? onEnter;
  final VoidCallback? onEscape;
  final bool autoFocus;

  const KeyboardDialogWrapper({
    super.key,
    required this.child,
    this.onEnter,
    this.onEscape,
    this.autoFocus = true,
  });

  @override
  Widget build(BuildContext context) {
    return TeclasDialogoScope(
      manejaEnter: onEnter != null,
      manejaEscape: onEscape != null,
      child: CallbackShortcuts(
        bindings: {
          if (onEnter != null)
            const SingleActivator(LogicalKeyboardKey.enter): onEnter!,
          if (onEnter != null)
            const SingleActivator(LogicalKeyboardKey.numpadEnter): onEnter!,
          if (onEscape != null)
            const SingleActivator(LogicalKeyboardKey.escape): onEscape!,
        },
        child: Focus(autofocus: autoFocus, child: child),
      ),
    );
  }
}

/// Extension para facilitar el uso en showDialog
extension KeyboardDialogExtension on BuildContext {
  /// Muestra un diálogo con manejo automático de ENTER/ESC
  Future<T?> showKeyboardDialog<T>({
    required WidgetBuilder builder,
    VoidCallback? onEnter,
    VoidCallback? onEscape,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: this,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => KeyboardDialogWrapper(
        onEnter: onEnter,
        onEscape: onEscape ?? () => Navigator.of(ctx).pop(),
        child: builder(ctx),
      ),
    );
  }
}
