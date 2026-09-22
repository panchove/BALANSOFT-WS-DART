import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Envuelve un [Scaffold] y captura el atajo `Ctrl+=` / `Ctrl++` /
/// `Ctrl+NumpadAdd` para disparar la acción "crear nuevo" de un CRUD.
///
/// Se registra como handler global del binding (igual que `home_shell.dart`)
/// para funcionar en cualquier pantalla, sin depender del foco del widget.
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