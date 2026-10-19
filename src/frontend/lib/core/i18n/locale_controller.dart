import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage {
  system,
  es,
  en,
  pt,
}

class LocaleController extends ChangeNotifier {
  static const _prefKey = 'balansoft.idioma';
  AppLanguage _language = AppLanguage.system;
  SharedPreferences? _prefs;

  AppLanguage get language => _language;

  /// Devuelve el `Locale` activo concreto (espejo del comportamiento del SG).
  Locale get locale => Locale(activeLanguageCode);

  /// Código de idioma activo resuelto (si es system, resuelve según el dispositivo).
  String get activeLanguageCode {
    if (_language != AppLanguage.system) {
      return _language.name;
    }
    try {
      final locales = WidgetsBinding.instance.platformDispatcher.locales;
      final code = locales.isEmpty ? null : locales.first.languageCode.toLowerCase();
      if (code == 'en' || code == 'pt') {
        return code!;
      }
    } catch (_) {}
    return 'es'; // Fallback predeterminado del sistema
  }


  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final saved = _prefs?.getString(_prefKey);
    if (saved != null) {
      _language = AppLanguage.values.firstWhere(
        (l) => l.name == saved,
        orElse: () => AppLanguage.system,
      );
    } else {
      _language = AppLanguage.system;
    }
    notifyListeners();
  }

  Future<void> setLanguage(AppLanguage language) async {
    _language = language;
    await _prefs?.setString(_prefKey, language.name);
    notifyListeners();
  }
}
