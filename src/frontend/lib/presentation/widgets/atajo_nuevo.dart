import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/dialog_keyboard.dart';

/// Envuelve un [Scaffold] y captura el atajo `Ctrl+=` / `Ctrl++` /
/// `Ctrl+NumpadAdd` para disparar la acción "crear nuevo" de un CRUD.
///
/// Se registra como handler global del binding (igual que `home_shell.dart`)
/// para funcionar en cualquier pantalla, sin depender del foco del widget.
///
/// **Los handlers globales del binding NO se cortan entre sí** (el binding
/// invoca a todos), así que devolver `true` en `HomeShell` no impide que este
/// atajo se dispare con un modal abierto: hay que autoprotegerse aquí. Sin
/// esta guarda, pulsar `Ctrl+=` con un diálogo abierto abría OTRO diálogo
/// encima («se apilan»).
class AtajoNuevo extends StatefulWidget {
  final VoidCallback onNuevo;
  final Widget child;

  const AtajoNuevo({super.key, required this.onNuevo, required this.child});

  @override
  State<AtajoNuevo> createState() => _AtajoNuevoState();
}

class _AtajoNuevoState extends State<AtajoNuevo> {
  @override
  void initState() {
    super.initState();
    ServicesBinding.instance.keyboard.addHandler(_onKey);
  }

  @override
  void dispose() {
    ServicesBinding.instance.keyboard.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    // Con un modal abierto el atajo no debe operar: el propio modal resolverá
    // la tecla (el gate del shell ya se encarga de ENTER/ESC).
    if (DialogKeyboard.hayModalAbierto()) return false;
    final kb = HardwareKeyboard.instance;
    final ctrl = kb.isControlPressed || kb.isMetaPressed;
    final key = event.logicalKey;
    final esNuevo = (ctrl && key == LogicalKeyboardKey.equal) ||
        (ctrl && key == LogicalKeyboardKey.numpadAdd);
    if (esNuevo) {
      widget.onNuevo();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}