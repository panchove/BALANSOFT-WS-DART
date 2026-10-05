import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TypographyController extends ChangeNotifier {
  static const String _keyTextScale = 'app.textScaleFactor';
  static const String _keyFamiliaUi = 'app.familiaUi';
  static const String _keyTipoFuenteTicket = 'empresa.tipoFuenteTicket';
  static const String _keyTamanoTicketPdf = 'empresa.tamanoTicketPdf';

  static const double minUiScale = 0.85;
  static const double maxUiScale = 1.40;

  /// Familias de UI ofrecidas al operador (REQ-FN-007), en el orden en que se
  /// pintan. Son identificadores internos: el texto visible va por i18n.
  static const List<String> familiasUi = [
    'SISTEMA',
    'SANS_SERIF',
    'SERIF',
    'MONOSPACE',
    'ROBOTO',
  ];

  /// Familia por defecto: deja `fontFamily` en `null`, que es lo que hace
  /// Flutter para tomar la fuente del sistema operativo.
  static const String familiaUiPorDefecto = 'SISTEMA';

  /// `null` = fuente del sistema. Las otras son familias genéricas de Flutter y
  /// `Roboto`, que ya viene en el bundle (spec 001, H-6): 0 KB y 0 dependencias.
  static const Map<String, String?> _familiaFontFamily = {
    'SISTEMA': null,
    'SANS_SERIF': 'sans-serif',
    'SERIF': 'serif',
    'MONOSPACE': 'monospace',
    'ROBOTO': 'Roboto',
  };

  /// Valores admitidos por `empresas.tamano_ticket_pdf`: los mismos del `CHECK`
  /// de la migración 021 y de los `Literal` de `EmpresaPerfilOut/Update`.
  static const List<String> tamanosTicket = [
    'AUTOMATICO',
    'GRANDE',
    'MEDIANO',
    'PEQUENO',
  ];
  static const String tamanoTicketPorDefecto = 'AUTOMATICO';

  /// Única fuente del PDF (REQ-FN-014). No es seleccionable: el `CHECK` de la
  /// BD la fija en `DejaVu`.
  static const String fuenteTicket = 'DejaVu';

  final SharedPreferences prefs;
  double _textScale = 1.00;
  String _familiaUi = familiaUiPorDefecto;
  String _tipoFuenteTicket = fuenteTicket;
  String _tamanoTicketPdf = tamanoTicketPorDefecto;

  TypographyController({required this.prefs});

  double get textScale => _textScale;
  String get familiaUi => _familiaUi;
  String get tipoFuenteTicket => _tipoFuenteTicket;
  String get tamanoTicketPdf => _tamanoTicketPdf;

  /// `fontFamily` a aplicar al `textTheme` para la familia elegida. `null` deja
  /// la fuente del sistema, que es el comportamiento actual sin ajustes.
  String? get familiaUiFontFamily => _familiaFontFamily[_familiaUi];

  static bool esFamiliaUiValida(String value) => familiasUi.contains(value);
  static bool esTamanoTicketValido(String value) => tamanosTicket.contains(value);

  bool isValidScale(double value) {
    return value >= minUiScale && value <= maxUiScale;
  }

  Future<void> load() async {
    // Se recuerda lo anterior para no notificar cuando nada cambia. `load()` se
    // llama desde el `initState` de `TypographySettingsScreen` y desde el
    // `initState` de la app: en ambos casos el controlador **ya** tiene estos
    // valores, y notificar aquí marca como sucio el `ListenableBuilder` de
    // `TipografiaScope` **durante el build**, que es una aserción de Flutter
    // («setState() or markNeedsBuild() called during build»). Se detectó
    // abriendo Ajustes → Tipografía con T10b; el aviso salía cada vez.
    final escalaPrevia = _textScale;
    final familiaPrevia = _familiaUi;
    final fuentePrevia = _tipoFuenteTicket;
    final tamanoPrevio = _tamanoTicketPdf;

    final scale = prefs.getDouble(_keyTextScale);
    if (scale != null) {
      _textScale = _clampToUi(scale);
    } else {
      _textScale = 1.00;
    }

    // Una preferencia corrupta (escrita a mano, restaurada desde un backup de
    // otra versión) cae al valor por defecto en lugar de romper el arranque
    // (REQ-FN-006).
    final familia = prefs.getString(_keyFamiliaUi);
    _familiaUi = (familia != null && esFamiliaUiValida(familia))
        ? familia
        : familiaUiPorDefecto;

    final fuente = prefs.getString(_keyTipoFuenteTicket);
    if (fuente != null && fuente.isNotEmpty) {
      _tipoFuenteTicket = fuente;
    } else {
      _tipoFuenteTicket = fuenteTicket;
    }

    final tamano = prefs.getString(_keyTamanoTicketPdf);
    _tamanoTicketPdf = (tamano != null && esTamanoTicketValido(tamano))
        ? tamano
        : tamanoTicketPorDefecto;

    if (_textScale != escalaPrevia ||
        _familiaUi != familiaPrevia ||
        _tipoFuenteTicket != fuentePrevia ||
        _tamanoTicketPdf != tamanoPrevio) {
      notifyListeners();
    }
  }

  Future<void> setTextScale(double value) async {
    _textScale = _clampToUi(value);
    await prefs.setDouble(_keyTextScale, _textScale);
    notifyListeners();
  }

  Future<void> setFamiliaUi(String value) async {
    // No se persiste un valor desconocido: si la lista de familias cambiara,
    // una preferencia vieja no debe ensuciar las preferencias.
    if (!esFamiliaUiValida(value)) return;
    _familiaUi = value;
    await prefs.setString(_keyFamiliaUi, value);
    notifyListeners();
  }

  Future<void> setTipoFuenteTicket(String value) async {
    _tipoFuenteTicket = value;
    await prefs.setString(_keyTipoFuenteTicket, value);
    notifyListeners();
  }

  Future<void> setTamanoTicketPdf(String value) async {
    _tamanoTicketPdf = value;
    await prefs.setString(_keyTamanoTicketPdf, value);
    notifyListeners();
  }

  double _clampToUi(double v) {
    if (v < minUiScale) return minUiScale;
    if (v > maxUiScale) return maxUiScale;
    return v;
  }
}
