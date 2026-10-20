// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 25010 / ISO/IEC 27001
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

import 'package:flutter/material.dart';

/// Servicio para rastrear si hay modales/diálogos abiertos.
///
/// Permite que los atajos globales (en `HomeShell`) se desactiven cuando
/// hay un modal abierto, evitando la navegación "debajo" del modal.
class ModalManager extends ChangeNotifier {
  int _openModals = 0;

  int get openModals => _openModals;
  bool get hasOpenModals => _openModals > 0;

  void registerModalOpen() {
    _openModals++;
    notifyListeners();
  }

  void registerModalClose() {
    _openModals = (_openModals - 1).clamp(0, 100).toInt();
    notifyListeners();
  }

  /// Wrapper para showDialog que registra automáticamente la apertura/cierre
  Future<T?> showModal<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
    bool useRootNavigator = false,
    RouteSettings? routeSettings,
  }) {
    registerModalOpen();
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      useRootNavigator: useRootNavigator,
      routeSettings: routeSettings,
      builder: builder,
    ).whenComplete(registerModalClose);
  }

  /// Wrapper para showModalBottomSheet
  Future<T?> showBottomSheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = false,
    bool useRootNavigator = false,
    RouteSettings? routeSettings,
  }) {
    registerModalOpen();
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      useRootNavigator: useRootNavigator,
      routeSettings: routeSettings,
      builder: builder,
    ).whenComplete(registerModalClose);
  }
}