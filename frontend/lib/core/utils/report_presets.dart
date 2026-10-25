/// Preset de fecha con el que se abre la pantalla de reportes, elegido desde
/// el ítem del menú REPORTES (Diarios / Mensuales / Personalizado).
enum ReportPreset {
  /// Reporte del día en curso.
  diarios,

  /// Reporte consolidado del mes en curso.
  mensuales,

  /// Rango de fechas libre (reportes avanzados).
  personalizado,
}

/// Modo de consulta que resulta de aplicar un preset.
enum ReportMode {
  diario,
  mensual,
  avanzado,
}

/// Estado inicial de la pantalla de reportes para un preset dado.
///
/// Función pura: el widget la usa en `initState`, y el test la verifica sin
/// montar la pantalla ni depender de la API. `null` conserva el estado previo
/// (día actual, modo diario).
class ReportInitialState {
  final ReportMode modo;
  final DateTime fecha;
  final int year;
  final int month;
  final DateTime desde;
  final DateTime hasta;

  const ReportInitialState({
    required this.modo,
    required this.fecha,
    required this.year,
    required this.month,
    required this.desde,
    required this.hasta,
  });
}

ReportInitialState estadoInicialReporte(ReportPreset? preset, DateTime hoy) {
  switch (preset) {
    case ReportPreset.diarios:
      return ReportInitialState(
        modo: ReportMode.diario,
        fecha: hoy,
        year: hoy.year,
        month: hoy.month,
        desde: hoy.subtract(const Duration(days: 30)),
        hasta: hoy,
      );
    case ReportPreset.mensuales:
      return ReportInitialState(
        modo: ReportMode.mensual,
        fecha: hoy,
        year: hoy.year,
        month: hoy.month,
        desde: hoy.subtract(const Duration(days: 30)),
        hasta: hoy,
      );
    case ReportPreset.personalizado:
      return ReportInitialState(
        modo: ReportMode.avanzado,
        fecha: hoy,
        year: hoy.year,
        month: hoy.month,
        desde: DateTime(hoy.year, hoy.month, 1),
        hasta: hoy,
      );
    case null:
      return ReportInitialState(
        modo: ReportMode.diario,
        fecha: hoy,
        year: hoy.year,
        month: hoy.month,
        desde: hoy.subtract(const Duration(days: 30)),
        hasta: hoy,
      );
  }
}
