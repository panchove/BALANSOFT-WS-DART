import 'package:balansoft_ws/core/utils/report_presets.dart';
import 'package:flutter_test/flutter_test.dart';

/// REPORTES → Diarios / Mensuales / Personalizado.
///
/// Los tres ítems del menú abren la MISMA pantalla con un estado inicial
/// distinto. La decisión vive en una función pura para poder verificarla sin
/// montar el widget ni depender de la API.
void main() {
  // Fecha fija: evita depender del reloj de la máquina.
  final hoy = DateTime(2026, 10, 20, 15, 30);

  group('estadoInicialReporte', () {
    test('sin preset conserva el comportamiento previo (día actual)', () {
      final estado = estadoInicialReporte(null, hoy);
      expect(estado.modo, ReportMode.diario);
      expect(estado.fecha, hoy);
    });

    test('DIARIOS fija la fecha de hoy en modo diario', () {
      final estado = estadoInicialReporte(ReportPreset.diarios, hoy);
      expect(estado.modo, ReportMode.diario);
      expect(estado.fecha.day, 20);
      expect(estado.fecha.month, 10);
      expect(estado.fecha.year, 2026);
    });

    test('MENSUALES fija el mes en curso en modo mensual', () {
      final estado = estadoInicialReporte(ReportPreset.mensuales, hoy);
      expect(estado.modo, ReportMode.mensual);
      expect(estado.year, 2026);
      expect(estado.month, 10);
    });

    test('PERSONALIZADO abre en modo avanzado con el mes en curso', () {
      final estado = estadoInicialReporte(ReportPreset.personalizado, hoy);
      expect(estado.modo, ReportMode.avanzado);
      // El rango arranca el primer día del mes y termina hoy: el operador lo
      // ajusta a voluntad desde la pantalla.
      expect(estado.desde, DateTime(2026, 10, 1));
      expect(estado.hasta, hoy);
    });

    test('los tres presets son modos distintos entre sí', () {
      final modos = {
        for (final p in ReportPreset.values)
          estadoInicialReporte(p, hoy).modo,
      };
      expect(modos, {ReportMode.diario, ReportMode.mensual, ReportMode.avanzado});
    });
  });
}
