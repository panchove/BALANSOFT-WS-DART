import 'package:intl/intl.dart';

class NumberUtils {
  static final _fmt = NumberFormat('#,##0.00', 'es_VE');
  static final _fmtInt = NumberFormat('#,##0', 'es_VE');

  static String formatWeight(double? value) {
    if (value == null) return '0.00';
    return _fmt.format(value);
  }

  static String formatKg(double? value) {
    if (value == null) return '0.00 kg';
    return '${_fmt.format(value)} kg';
  }

  static String formatTons(double? value) {
    if (value == null) return '0.000 t';
    final tons = value / 1000;
    return '${NumberFormat('#,##0.000').format(tons)} t';
  }

  static String formatPercent(double? value) {
    if (value == null) return '0.00%';
    return '${NumberFormat('#,##0.00').format(value)}%';
  }

  static String formatCurrency(double? value) {
    if (value == null) return 'Bs. 0,00';
    return 'Bs. ${_fmt.format(value)}';
  }

  static String formatInt(int? value) {
    if (value == null) return '0';
    return _fmtInt.format(value);
  }
}
