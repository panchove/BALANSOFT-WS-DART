import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balansoft_ws/domain/entities/printer_preset.dart';
import 'package:balansoft_ws/domain/entities/weighing.dart';
import 'package:balansoft_ws/presentation/widgets/ticket_preview_dialog.dart';

void main() {
  final now = DateTime(2026, 9, 8, 10, 0);
  final weighingDemo = Weighing(
    boleto: 'b1b2b3b4-b5b6-4b7b-8b9b-babbbcbdbebf',
    numeroBoleto: 'TA-00000001',
    idVehiculo: 'ABC123',
    remolque: false,
    idTransporte: 'TRANSPORTE DEMO',
    idConductor: 'JUAN PEREZ',
    idProducto: 'MAIZ',
    idAlmacen: 'SILO 01',
    terceroNombre: 'AGROINSUMOS C.A.',
    pesoEntradaVehiculo: 50000.0,
    pesoSalidaVehiculo: 45000.0,
    pesoNeto: 5000.0,
    fechaHoraEntrada: now.subtract(const Duration(minutes: 30)),
    fechaHoraSalida: now,
    estadoBoleto: 'CERRADO',
    createdAt: now,
    updatedAt: now,
    observaciones: 'Sin observaciones',
  );

  Widget createWidgetUnderTest({
    PrinterPreset? initialPreset,
    void Function(String formato, PrinterPreset preset)? onConfirmPrint,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: TicketPreviewDialog(
          weighing: weighingDemo,
          initialPreset: initialPreset ?? const PrinterPreset(boletosPorHoja: 2),
          onConfirmPrint: onConfirmPrint,
        ),
      ),
    );
  }

  testWidgets('Renderiza previsualización con número de boleto y controles', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    expect(find.textContaining('Previsualización del Boleto: TA-00000001'), findsOneWidget);
    expect(find.text('Por Hoja: '), findsOneWidget);
    expect(find.text('PDF'), findsWidgets);
    expect(find.text('TXT'), findsOneWidget);
    expect(find.text('Confirmar e Imprimir (1)'), findsOneWidget);
  });

  testWidgets('Muestra líneas de corte si boletosPorHoja > 1', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(createWidgetUnderTest(
      initialPreset: const PrinterPreset(boletosPorHoja: 3, tamanoPapel: 'Letter'),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.content_cut), findsNWidgets(2));
  });

  testWidgets('onConfirmPrint es invocado con formato y preset al presionar Confirmar', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    String? formatoSeleccionado;
    PrinterPreset? presetSeleccionado;

    await tester.pumpWidget(createWidgetUnderTest(
      initialPreset: const PrinterPreset(copias: 3),
      onConfirmPrint: (f, p) {
        formatoSeleccionado = f;
        presetSeleccionado = p;
      },
    ));
    await tester.pumpAndSettle();

    final btnConfirmar = find.text('Confirmar e Imprimir (3)');
    expect(btnConfirmar, findsOneWidget);

    await tester.tap(btnConfirmar);
    await tester.pumpAndSettle();

    expect(formatoSeleccionado, equals('PDF'));
    expect(presetSeleccionado?.copias, equals(3));
  });
}
