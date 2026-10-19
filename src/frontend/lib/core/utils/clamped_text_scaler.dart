import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Escalador de texto que compone el factor elegido por el operador con el
/// factor que llega de fuera (accesibilidad del SO, ancestros).
///
/// Se compone con [escalarTexto], que es lo que llama `TipografiaScope` desde el
/// `builder` del `MaterialApp` (`main.dart`):
///
/// ```dart
/// // TipografiaScope
/// MediaQuery(
///   data: mq.copyWith(
///     textScaler: escalarTexto(
///       externo: mq.textScaler,                        // el del SO
///       factorOperador: controlador.textScale,         // 0.85 .. 1.40
///     ),
///   ),
///   child: child,
/// );
/// ```
///
/// **Por qué compone y no multiplica números.** `TextScaler` no tiene operador de
/// producto: leer `textScaleFactor` para multiplicar a mano aplana el escalado no
/// lineal del sistema operativo y además usa un miembro deprecado (que
/// `flutter analyze` trata como error, `AGENTS.md` v3.11). Con [interno] se
/// conserva el escalado real del SO y solo se le multiplica el factor del
/// operador encima.
class ClampedTextScaler extends TextScaler {
  /// Piso del **clamp técnico** de REQ-FN-002b.
  static const double minPorDefecto = 0.85;

  /// Techo del **clamp técnico** de REQ-FN-002b.
  ///
  /// Va **por encima** del rango del selector del operador
  /// (`TypographyController.minUiScale`/`maxUiScale` = 0.85/1.40) a propósito: con
  /// el SO en 1.0 el operador elige hasta 1.40 sin que el clamp lo recorte.
  ///
  /// Ojo al leerlo: el clamp acota el **producto**, no solo el factor externo. Con
  /// el SO ya en 1.60 y el operador en 1.40 el producto da 2.24 y se recorta a
  /// 1.60, porque REQ-FN-002b exige que ningún valor >1.60 llegue a la pantalla.
  static const double maxPorDefecto = 1.60;

  /// Factor que se aplica sobre el resultado de [interno]. Sin [interno] es el
  /// factor lineal del propio escalador (comportamiento heredado de la clase).
  final double scaleValue;

  /// Escalador externo ya acotado. `null` = el factor lineal es [scaleValue].
  final TextScaler? interno;

  /// Límites del factor, usados por [clampValue] y por [_effective].
  final double minScale;
  final double maxScale;

  const ClampedTextScaler(
    this.scaleValue, {
    this.interno,
    double min = minPorDefecto,
    double max = maxPorDefecto,
  })  : minScale = min,
        maxScale = max;

  /// Factor realmente aplicado: [scaleValue] acotado a `[minScale, maxScale]`.
  double get _effective => _clampValue(scaleValue);

  double _clampValue(double value) {
    return math.min(math.max(value, minScale), maxScale);
  }

  double clampValue(double value) => _clampValue(value);

  /// Escala respetando el escalado de [interno] si lo hay (REQ-FN-002).
  ///
  /// Multiplicar aquí, y no en el `TextStyle`, es lo que hace que los **322
  /// `fontSize:` fijos en código** escalen sin tocar ninguno: todos los `Text`
  /// leen el `textScaler` del `MediaQuery`.
  ///
  /// El clamp acota el factor **efectivo**, es decir el que resulta de componer
  /// el externo con el del operador. Acotar solo el externo no bastaría: con el
  /// SO a 2.0 (acotado a 1.60) y el operador a 1.40, el producto llegaría a 2.24
  /// y REQ-FN-002b exige que el clamp **nunca** deje pasar un valor >1.60.
  @override
  double scale(double fontSize) {
    final base = interno?.scale(fontSize) ?? fontSize;
    return math.min(
      math.max(base * _effective, minScale * fontSize),
      maxScale * fontSize,
    );
  }

  // El miembro es abstracto **y** deprecado en esta versión del SDK: hay que
  // implementarlo para poder heredar de `TextScaler`, y no se puede eliminar
  // (REQ-FN-002c). La supresión va **solo** aquí: leer el valor en cualquier
  // otro sitio sí es un error de análisis.
  // ignore: deprecated_member_use
  @override
  double get textScaleFactor => _effective;

  @override
  TextScaler clamp({double minScaleFactor = 0, double maxScaleFactor = double.infinity}) {
    final base = interno;
    if (base == null) {
      // Escalado lineal: el factor es lo que hay que acotar.
      final clamped =
          math.min(math.max(scaleValue, minScaleFactor), maxScaleFactor);
      return ClampedTextScaler(
        clamped,
        min: minScaleFactor,
        max: maxScaleFactor,
      );
    }
    // `scale()` devuelve `interno.scale(fs) * factor`, así que para caer en
    // `[minScaleFactor * fs, maxScaleFactor * fs]` — que es lo que promete
    // `TextScaler.clamp` — hay que acotar el interno con esos límites
    // **divididos** por el factor del operador. Este camino no es teórico:
    // varios widgets de Material piden `clamp` sobre el `textScaler` heredado
    // (`NavigationBar` a 1.3, `AppBar` en el título, `Slider`, selectores de
    // fecha) y un `clamp` que ignorara el factor dejaría esos textos sin
    // escalar.
    final factor = _effective;
    return ClampedTextScaler(
      scaleValue,
      interno: factor > 0
          ? base.clamp(
              minScaleFactor: minScaleFactor / factor,
              maxScaleFactor: maxScaleFactor / factor,
            )
          : base,
    );
  }

  TextScaler copyWith({double? min, double? max}) => ClampedTextScaler(
        scaleValue,
        interno: interno,
        min: min ?? minScale,
        max: max ?? maxScale,
      );

  TextScaler interpolate(TextScaler other, double t) {
    if (other is ClampedTextScaler) {
      final v = scaleValue + (other.scaleValue - scaleValue) * t;
      final mn = minScale + (other.minScale - minScale) * t;
      final mx = maxScale + (other.maxScale - maxScale) * t;
      return ClampedTextScaler(v, interno: interno, min: mn, max: mx);
    }
    return ClampedTextScaler(scaleValue, interno: interno, min: minScale, max: maxScale);
  }
}

/// Escala efectivo de la aplicación: el factor que eligió el operador
/// compuesto **por encima** del factor externo ya acotado.
///
/// Es la fórmula que `main.dart` aplica en el `builder` del `MaterialApp`:
/// un factor externo de 2.0 (accesibilidad del SO, un `MediaQuery` tocado por
/// otro widget, un defecto) queda acotado a [ClampedTextScaler.maxPorDefecto]
/// = 1.60, y el factor del operador (0.85..1.40) llega sin que ese clamp lo
/// recorte, porque su techo está por encima del rango del selector
/// (REQ-FN-002b). El factor **efectivo** tampoco pasa nunca de 1.60, aunque se
/// compongan los dos: es lo que garantiza el clamp del propio escalador.
///
/// Se expone como función suelta, y no solo como constructor, para que el
/// comportamiento se pueda comprobar en aislamiento sin montar la app entera.
TextScaler escalarTexto({
  required TextScaler externo,
  required double factorOperador,
}) {
  return ClampedTextScaler(
    factorOperador,
    // Acota lo que venga de fuera antes de componer (red de seguridad de
    // REQ-FN-002b); el escalador acota además el producto.
    interno: externo.clamp(
      minScaleFactor: ClampedTextScaler.minPorDefecto,
      maxScaleFactor: ClampedTextScaler.maxPorDefecto,
    ),
  );
}