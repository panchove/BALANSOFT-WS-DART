import 'package:flutter/widgets.dart';

/// Bus de foco para el atajo `F6` ("enfocar la búsqueda").
///
/// Las pantallas registran su campo de búsqueda con [registrar] al montarse y
/// lo liberan en `dispose`. El `home_shell` llama [enfocar] para llevar el
/// cursor al buscador de la pantalla activa sin acoplar ambas capas.
class FocusSearchBus {
  FocusSearchBus._();

  static final FocusSearchBus instance = FocusSearchBus._();

  FocusNode? _node;
  String? _textoPendiente;

  /// Campo de búsqueda de la pantalla activa (o `null` si no hay).
  FocusNode? get node => _node;

  /// Registra el campo de búsqueda de una pantalla.
  void registrar(FocusNode node) => _node = node;

  /// Deja un texto pendiente para la próxima pantalla que registre su
  /// buscador (búsqueda dirigida desde la paleta: `t:#123`, `p:A12BC3`).
  void registrarTexto(String texto) => _textoPendiente = texto;

  /// Consume el texto pendiente (lo devuelve una sola vez).
  String? tomarTexto() {
    final texto = _textoPendiente;
    _textoPendiente = null;
    return texto;
  }

  /// Libera el campo si es el registrado por esa pantalla.
  void liberar(FocusNode node) {
    if (identical(_node, node)) _node = null;
  }

  /// Lleva el foco al buscador. Devuelve `false` si la pantalla activa no
  /// tiene campo de búsqueda registrado.
  bool enfocar() {
    final actual = _node;
    if (actual == null) return false;
    if (actual.hasFocus) return true;
    actual.requestFocus();
    return true;
  }
}
