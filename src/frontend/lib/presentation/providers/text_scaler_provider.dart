import 'package:flutter/material.dart';
import '../../core/controllers/typography_controller.dart';
import '../../core/utils/clamped_text_scaler.dart';

class TextScalerProvider extends ChangeNotifier {
  final TypographyController controller;

  TextScalerProvider({required this.controller}) {
    controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  double get textScale => controller.textScale;

  /// Rango del clamp **técnico** de REQ-FN-002b: [0.85, 1.60], no el rango del
  /// selector ([0.85, 1.40]). El techo va por encima a propósito para que el
  /// clamp acote los factores externos sin recortar lo que eligió el operador.
  TextScaler get textScaler => ClampedTextScaler(
        textScale,
        min: ClampedTextScaler.minPorDefecto,
        max: ClampedTextScaler.maxPorDefecto,
      );
}
