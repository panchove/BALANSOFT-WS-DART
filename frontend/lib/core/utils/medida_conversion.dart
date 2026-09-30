import '../i18n/translations.dart';

/// Medidas de facturación soportadas en el pesaje.
///
/// La báscula siempre entrega **kilogramos**; la medida es la unidad en la que
/// la empresa factura o registra la mercancía.
enum UnidadMedida { kg, litros, galones, toneladas, unidades }

extension UnidadMedidaDatos on UnidadMedida {
  /// Clave de traducción de la etiqueta visible en pantalla.
  String get claveI18n => switch (this) {
        UnidadMedida.kg => 'measure_kg',
        UnidadMedida.litros => 'measure_litros',
        UnidadMedida.galones => 'measure_galones',
        UnidadMedida.toneladas => 'measure_toneladas',
        UnidadMedida.unidades => 'measure_unidades',
      };

  /// Etiqueta traducida según el idioma activo.
  String get etiqueta => claveI18n.tr();

  /// Texto que se persiste en el boleto (`weighings.medida`).
  String get etiquetaPersistida => switch (this) {
        UnidadMedida.kg => 'Kilogramos',
        UnidadMedida.litros => 'Litros',
        UnidadMedida.galones => 'Galones',
        UnidadMedida.toneladas => 'Toneladas',
        UnidadMedida.unidades => 'Unidades',
      };

  /// `true` cuando la conversión necesita la densidad del producto (kg/L).
  bool get requiereDensidad =>
      this == UnidadMedida.litros || this == UnidadMedida.galones;

  /// `true` cuando la conversión necesita el peso por unidad del producto.
  bool get requierePesoUnidad => this == UnidadMedida.unidades;

  /// Símbolo corto para mostrar junto al resultado.
  String get simbolo => switch (this) {
        UnidadMedida.kg => 'kg',
        UnidadMedida.litros => 'L',
        UnidadMedida.galones => 'gal',
        UnidadMedida.toneladas => 't',
        UnidadMedida.unidades => 'und',
      };
}

/// Conversión del peso neto (kg) a la medida de facturación.
///
/// Fórmulas (reglas de negocio invariables):
/// - Litros    = PNT kg / densidad (kg/L)
/// - Galones   = Litros / 3.78541
/// - Toneladas = PNT kg / 1000
/// - Unidades  = PNT kg / peso unitario del producto (kg/saco)
/// - Kilogramos = PNT kg
class ConversionMedida {
  /// Litros por galón (US gallon).
  static const double litrosPorGalon = 3.78541;

  /// Mapea la `unidad_medida` del catálogo de productos a la medida del
  /// formulario. `TON`→Toneladas, `UN`→Unidades, `KG`/`LBS`→Kilogramos.
  static UnidadMedida? desdeUnidadProducto(String? unidadMedida) {
    switch (unidadMedida?.trim().toUpperCase()) {
      case 'TON':
      case 'TONELADA':
      case 'TONELADAS':
      case 'T':
        return UnidadMedida.toneladas;
      case 'UN':
      case 'UND':
      case 'UNDADES':
      case 'SACOS':
      case 'BULTOS':
      case 'CAJAS':
        return UnidadMedida.unidades;
      case 'L':
      case 'LITRO':
      case 'LITROS':
      case 'LT':
        return UnidadMedida.litros;
      case 'GAL':
      case 'GALON':
      case 'GALONES':
        return UnidadMedida.galones;
      case 'KG':
      case 'KGS':
      case 'LBS':
      case 'KILOGRAMOS':
      case null:
      case '':
        return UnidadMedida.kg;
    }
    return UnidadMedida.kg;
  }

  /// Interpreta el texto legado de `weighings.medida` (boletos ya registrados).
  static UnidadMedida? desdeTexto(String? texto) {
    final t = texto?.trim().toUpperCase();
    if (t == null || t.isEmpty) return null;
    return desdeUnidadProducto(t);
  }

  /// Resultado de la conversión. Devuelve `null` cuando falta el factor
  /// requerido (densidad o peso unitario) o el peso no es válido.
  static double? calcular({
    required double pesoNetoKg,
    required UnidadMedida medida,
    double? densidad,
    double? pesoUnidad,
  }) {
    if (pesoNetoKg <= 0) return null;
    return switch (medida) {
      UnidadMedida.kg => pesoNetoKg,
      UnidadMedida.litros => _dividir(pesoNetoKg, densidad),
      UnidadMedida.galones => _litros(pesoNetoKg, densidad) == null
          ? null
          : _litros(pesoNetoKg, densidad)! / litrosPorGalon,
      UnidadMedida.toneladas => pesoNetoKg / 1000.0,
      UnidadMedida.unidades => _dividir(pesoNetoKg, pesoUnidad),
    };
  }

  /// Litros del peso neto (para liquids), independientemente de la medida
  /// elegida: se persiste en `weighings.litros` para reportes.
  static double? litros({required double pesoNetoKg, double? densidad}) =>
      _litros(pesoNetoKg, densidad);

  /// Texto listo para mostrar en el campo `Unidades` (2 decimales, sin
  /// separador de miles para no romper el `TextInputType` numérico).
  static String formatear(double? valor) {
    if (valor == null) return '';
    return valor.toStringAsFixed(2);
  }

  /// Texto de la fórmula aplicada, para el texto de ayuda del campo.
  static String formula(UnidadMedida medida) => switch (medida) {
        UnidadMedida.kg => 'measure_formula_kg',
        UnidadMedida.litros => 'measure_formula_litros',
        UnidadMedida.galones => 'measure_formula_galones',
        UnidadMedida.toneladas => 'measure_formula_toneladas',
        UnidadMedida.unidades => 'measure_formula_unidades',
      };

  static double? _dividir(double peso, double? factor) {
    if (factor == null || factor <= 0) return null;
    return peso / factor;
  }

  static double? _litros(double peso, double? densidad) =>
      _dividir(peso, densidad);
}
