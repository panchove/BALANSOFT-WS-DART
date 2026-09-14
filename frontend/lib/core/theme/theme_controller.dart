import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TemaApp { sistema, claro, oscuro }

class ThemeController extends ChangeNotifier {
  TemaApp _tema = TemaApp.sistema;
  SharedPreferences? _prefs;

  TemaApp get tema => _tema;

  ThemeMode get themeMode {
    switch (_tema) {
      case TemaApp.claro:
        return ThemeMode.light;
      case TemaApp.oscuro:
        return ThemeMode.dark;
      case TemaApp.sistema:
        return ThemeMode.system;
    }
  }

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final index = _prefs?.getInt('balansoft.tema') ?? 0;
    _tema = TemaApp.values[index.clamp(0, TemaApp.values.length - 1)];
    notifyListeners();
  }

  Future<void> setTema(TemaApp tema) async {
    _tema = tema;
    await _prefs?.setInt('balansoft.tema', tema.index);
    notifyListeners();
  }
}
