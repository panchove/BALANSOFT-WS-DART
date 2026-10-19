import 'package:flutter/material.dart';

import 'package:balansoft_ws/core/controllers/typography_controller.dart';
import 'package:balansoft_ws/core/utils/clamped_text_scaler.dart';

/// Aplica el ajuste de tipografía del operador a **todo** lo que hay debajo.
///
/// Se monta en el `builder` del `MaterialApp` de `main.dart`, que es el único
/// punto que queda por encima de todas las rutas, diálogos y `showDialog` y por
/// debajo del `Navigator`. Desde aquí, los `fontSize:` fijos en el código escalan
/// sin tocar ninguno, porque cada `Text` lee el `textScaler` de este
/// `MediaQuery` (REQ-FN-002).
///
/// Vive en su propia clase, y no en el `builder` en línea, para que el
/// comportamiento se pueda comprobar montando el árbol real en un test: el
/// pegamento entre el `MediaQuery` y el ajuste del operador es justo lo que hay
/// que verificar (REQ-FN-002, REQ-FN-004).
class TipografiaScope extends StatelessWidget {
  const TipografiaScope({
    super.key,
    required this.controlador,
    required this.child,
  });

  final TypographyController controlador;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // El `ListenableBuilder` es lo que hace que el ajuste se aplique **sin
    // reiniciar** (REQ-FN-004): al cambiar el factor en Ajustes, el controlador
    // notifica y aquí se reconstruye el `MediaQuery` entero. Sin él habría que
    // depender de que el padre (`MaterialApp` en `main.dart`) también rebuild.
    return ListenableBuilder(
      listenable: controlador,
      builder: (context, _) {
        final mq = MediaQuery.of(context);
        // (1) El factor externo se acota a [0.85, 1.60] (REQ-FN-002b) y (2) el
        // factor del operador (0.85..1.40) se compone encima, sin que ese clamp
        // lo recorte (REQ-FN-002c). Ver `escalarTexto`.
        return MediaQuery(
          data: mq.copyWith(
            textScaler: escalarTexto(
              externo: mq.textScaler,
              factorOperador: controlador.textScale,
            ),
          ),
          child: child,
        );
      },
    );
  }
}
