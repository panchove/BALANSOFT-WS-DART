import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/keyboard_dialog_wrapper.dart';

/// Manejo de teclado cuando hay un modal (diálogo o popup) abierto.
///
/// Reglas de UX de la estación (AGENTS/UX de modales):
///  * `ENTER` → activa el botón primario (relleno) del diálogo; si el diálogo
///    ya gestiona ENTER con [KeyboardDialogWrapper], cede el paso para no
///    disparar la acción dos veces.
///  * `ESC`   → cancela/cierra el diálogo (aunque sea `barrierDismissible:
///    false`); si el wrapper gestiona ESC, cede el paso.
///  * Los atajos globales del shell (F1..F12, Ctrl/Alt+letra) quedan
///    **bloqueados** mientras el modal esté abierto: no deben navegar ni
///    operar debajo de él.
///  * Las teclas de texto y de edición estándar (Ctrl+C/V/X/Z, escribir)
///    pasan sin más al modal.
///
/// [HomeShell] invoca este servicio desde su manejador global de teclado:
/// ```dart
/// if (di.sl<ModalManager>().hasOpenModals || DialogKeyboard.hayModalAbierto()) {
///   return DialogKeyboard.manejarTeclaEnModal(event);
/// }
/// ```
/// Resultado de la búsqueda del botón primario de un diálogo.
class _BotonBuscado {
  final FocusNode? nodo;
  final bool manejadoPorWrapper;
  const _BotonBuscado(this.nodo, this.manejadoPorWrapper);
}

class DialogKeyboard {
  DialogKeyboard._();

  /// ¿Hay un diálogo o popup (dropdown, menú, bottom sheet) con el foco?
  ///
  /// Se detecta por la ruta del nodo con foco: al abrirse, el Navigator
  /// enfoca el scope de la ruta nueva, así que el foco vive dentro del
  /// modal aunque este esté montado en un navegador interno.
  static bool hayModalAbierto() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ModalRoute.of(ctx) is PopupRoute;
  }

  /// Tecla recibida con un modal abierto. Devuelve `true` si la consumió
  /// (el evento no debe seguir hacia otros manejadores).
  static bool manejarTeclaEnModal(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) return _cancelarDialogo();
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      return _activarPrimario();
    }
    return _atajoShellBloqueado(event);
  }

  // ── ESC ─────────────────────────────────────────────────────────────────

  static bool _cancelarDialogo() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    final ruta = ModalRoute.of(ctx);
    // Dropdowns, menús y bottom sheets: los cierra su propia ruta nativa.
    if (ruta is! DialogRoute) return false;
    // El diálogo ya gestiona ESC con KeyboardDialogWrapper → ceder el paso.
    if (TeclasDialogoScope.maybeOf(ctx)?.manejaEscape ?? false) return false;
    // Cierra aunque el diálogo tenga `barrierDismissible: false` (ESC es
    // siempre "cancelar"). El resultado `null` lo tratan los diálogos como
    // cancelación (`?? false`, `== true`).
    Navigator.of(ctx).pop();
    return true;
  }

  // ── ENTER ───────────────────────────────────────────────────────────────

  static bool _activarPrimario() {
    // Si el foco está en un campo de texto, ENTER es del campo (submit /
    // salto de línea), no del diálogo.
    if (_hayTextoEnFoco()) return false;

    final foco = FocusManager.instance.primaryFocus;
    final ctx = foco?.context;
    if (foco == null || ctx == null) return false;
    if (ModalRoute.of(ctx) is! DialogRoute) return false;

    final buscado = _buscarBotonPrimario(foco);
    if (buscado.manejadoPorWrapper) return false;
    final nodo = buscado.nodo;
    final nctx = nodo?.context;
    if (nodo == null || nctx == null) return false;

    Actions.maybeInvoke(nctx, const ButtonActivateIntent());
    return true;
  }

  static bool _hayTextoEnFoco() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.findAncestorStateOfType<EditableTextState>() != null;
  }

  /// Recorre el árbol de foco del diálogo en preorden y devuelve:
  ///  1. `manejadoPorWrapper` si el diálogo gestiona ENTER con
  ///     [KeyboardDialogWrapper] (entonces no hay que intervenir);
  ///  2. el primer botón **relleno** (FilledButton/ElevatedButton) — por
  ///     convención Material el botón de confirmación;
  ///  3. en su defecto, el último [TextButton]/[OutlinedButton] solo si el
  ///     diálogo tiene 1 o 2 botones de texto (confirmación típica
  ///     «Cancelar / Aceptar»); con 3+ no se decide para no pulsar a ciegas;
  ///  4. `null` si no hay botones (listas, dropdowns: ENTER queda nativo).
  static _BotonBuscado _buscarBotonPrimario(FocusNode raiz) {
    FocusNode? primario;
    FocusNode? ultimoTexto;
    var botonesTexto = 0;
    var wrapperEnter = false;

    void visitar(FocusNode n) {
      if (wrapperEnter) return;
      final ctx = n.context;
      if (ctx == null) return;

      // Marca del wrapper: si gestiona ENTER, no intervenir.
      if (TeclasDialogoScope.maybeOf(ctx)?.manejaEnter ?? false) {
        wrapperEnter = true;
        return;
      }

      // Subárbol no enfocable (p. ej. botón deshabilitado) → podar.
      if (!n.canRequestFocus) return;

      final accion = Actions.maybeFind<ButtonActivateIntent>(
        ctx,
        intent: const ButtonActivateIntent(),
      );
      if (accion == null) {
        for (final hijo in n.children) {
          visitar(hijo);
        }
        return;
      }

      // ¿Es un botón de estilo conocido?
      if (ctx.findAncestorWidgetOfExactType<FilledButton>() != null ||
          ctx.findAncestorWidgetOfExactType<ElevatedButton>() != null) {
        primario ??= n;
        return;
      }
      if (ctx.findAncestorWidgetOfExactType<TextButton>() != null ||
          ctx.findAncestorWidgetOfExactType<OutlinedButton>() != null) {
        botonesTexto++;
        ultimoTexto = n;
        return;
      }
      // Otro elemento activable (ListTile de SimpleDialog, Dropdown…):
      // no se decide con ENTER.
    }

    visitar(raiz);

    if (wrapperEnter) return const _BotonBuscado(null, true);
    if (primario != null) return _BotonBuscado(primario, false);
    if (botonesTexto >= 1 && botonesTexto <= 2) {
      return _BotonBuscado(ultimoTexto, false);
    }
    return const _BotonBuscado(null, false);
  }

  // ── Bloqueo de atajos del shell ─────────────────────────────────────────

  /// `true` → la tecla es un atajo de acción/navegación del shell y debe
  /// consumirse (el modal no la recibe, pero tampoco navega debajo).
  /// `false` → texto/edición normal: dejar que llegue al modal.
  static bool _atajoShellBloqueado(KeyEvent event) {
    final key = event.logicalKey;
    final kb = HardwareKeyboard.instance;
    final ctrl = kb.isControlPressed || kb.isMetaPressed;
    final alt = kb.isAltPressed;
    final shift = kb.isShiftPressed;

    // Sin modificadores: teclas de función del shell (F1..F12).
    if (!ctrl && !alt && _esTeclaFuncion(key)) return true;

    // Alt+* (mnemónicos) y Ctrl+Enter (ventana) siempre bloqueados.
    if (alt) return true;
    if (ctrl && (key == LogicalKeyboardKey.enter)) return true;

    if (ctrl && !shift) {
      // Combos propios del shell. Ctrl+C/V/X/Z/A y el resto de Ctrl+tecla
      // son de edición estándar y pasan al modal.
      if (key == LogicalKeyboardKey.keyQ || // salir
          key == LogicalKeyboardKey.keyN || // nuevo pesaje
          key == LogicalKeyboardKey.keyT || // transportes
          key == LogicalKeyboardKey.keyL || // cerrar sesión
          key == LogicalKeyboardKey.keyB || // sidebar
          key == LogicalKeyboardKey.keyK || // paleta de comandos
          key == LogicalKeyboardKey.keyH || // inicio
          key == LogicalKeyboardKey.keyR || // sincronizar
          key == LogicalKeyboardKey.comma || // configuración
          key == LogicalKeyboardKey.digit1 ||
          key == LogicalKeyboardKey.digit2 ||
          key == LogicalKeyboardKey.digit3 ||
          key == LogicalKeyboardKey.digit4 ||
          key == LogicalKeyboardKey.digit5) {
        return true;
      }
      return false;
    }
    if (ctrl && shift) return true; // Ctrl+Shift+* (nuevo vehículo, tema…)

    // Backspace/Delete sin campo enfocado: no "volver atrás" bajo el modal.
    if ((key == LogicalKeyboardKey.backspace ||
            key == LogicalKeyboardKey.delete) &&
        !_hayTextoEnFoco()) {
      return true;
    }

    // Texto normal y el resto → al modal.
    return false;
  }

  static bool _esTeclaFuncion(LogicalKeyboardKey k) {
    return k == LogicalKeyboardKey.f1 ||
        k == LogicalKeyboardKey.f2 ||
        k == LogicalKeyboardKey.f3 ||
        k == LogicalKeyboardKey.f4 ||
        k == LogicalKeyboardKey.f5 ||
        k == LogicalKeyboardKey.f6 ||
        k == LogicalKeyboardKey.f7 ||
        k == LogicalKeyboardKey.f8 ||
        k == LogicalKeyboardKey.f9 ||
        k == LogicalKeyboardKey.f10 ||
        k == LogicalKeyboardKey.f11 ||
        k == LogicalKeyboardKey.f12;
  }
}
