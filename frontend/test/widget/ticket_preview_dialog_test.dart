import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balansoft_ws/core/i18n/translations.dart';
import 'package:balansoft_ws/domain/entities/printer_preset.dart';
import 'package:balansoft_ws/domain/entities/weighing.dart';
import 'package:balansoft_ws/presentation/widgets/ticket_preview_dialog.dart';

const _perfilDemo = <String, dynamic>{
  'nombre_comercial': 'VARIEDADES S&S C.A.',
  'nombre_fiscal': 'VARIEDADES S&S C.A.',
  'rif_nit': 'J-31490236-2',
  'telefono': '+58 412-1234567',
  'direccion': 'Av. Principal, Edif. Torre, Chacao, Caracas 1060',
  'email': 'operaciones@variedades-ss.com.ve',
  // Logo inexistente de propósito: el errorBuilder del preview lo descarta.
  'logo_url': '/media/empresa/logo.png',
};

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
    Future<Map<String, dynamic>>? empresaPerfilFuture,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: TicketPreviewDialog(
          weighing: weighingDemo,
          initialPreset: initialPreset ?? const PrinterPreset(boletosPorHoja: 2),
          onConfirmPrint: onConfirmPrint,
          empresaPerfilFuture: empresaPerfilFuture,
        ),
      ),
    );
  }

  testWidgets(
      'Con nombres resueltos muestra nombres completos y nunca el UUID crudo',
      (tester) async {
    final conNombres = Weighing(
      boleto: 'b1b2b3b4-b5b6-4b7b-8b9b-babbbcbdbebf',
      numeroBoleto: 'TA-00000001',
      idVehiculo: 'RAP44W',
      remolque: true,
      remolquePlaca: 'RAP55M',
      idTransporte: 'fe000000-0000-4000-8000-000000000001',
      idConductor: 'V-18293041',
      idProducto: 'f1000000-0000-4000-8000-000000000004',
      idAlmacen: 'fa000000-0000-4000-8000-000000000001',
      transporteNombre: 'Transportes Expresos del Centro C.A.',
      conductorNombre: 'Carlos Eduardo Mendoza',
      productoNombre: 'Cemento Tipo I a Granel',
      almacenNombre: 'Silo Principal',
      pesoEntradaVehiculo: 38250.0,
      pesoSalidaVehiculo: 15800.0,
      pesoNeto: 22450.0,
      fechaHoraEntrada: now,
      fechaHoraSalida: now,
      estadoBoleto: 'CERRADO',
      createdAt: now,
      updatedAt: now,
    );
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TicketPreviewDialog(
            weighing: conNombres,
            initialPreset: const PrinterPreset(boletosPorHoja: 2),
            onConfirmPrint: (formato, preset) {},
            empresaPerfilFuture: Future.value(_perfilDemo),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Transportes Expresos del Centro C.A.'), findsOneWidget);
    expect(find.text('Cemento Tipo I a Granel'), findsOneWidget);
    expect(find.text('Silo Principal'), findsOneWidget);
    // La cédula es legible; el UUID del ID no debe colarse en la UI.
    expect(find.text('RAP55M'), findsOneWidget);
    expect(find.textContaining('fe000000'), findsNothing);
    expect(find.textContaining('f1000000'), findsNothing);
    expect(find.textContaining('fa000000'), findsNothing);
  });

  testWidgets('Sin nombres cae a N/A sin mostrar identificadores crudos',
      (tester) async {
    final sinNombres = Weighing(
      boleto: 'b1b2b3b4-b5b6-4b7b-8b9b-babbbcbdbebf',
      numeroBoleto: 'TA-00000001',
      idVehiculo: 'RAP44W',
      remolque: false,
      idTransporte: 'fe000000-0000-4000-8000-000000000001',
      idConductor: null,
      idProducto: 'f1000000-0000-4000-8000-000000000004',
      idAlmacen: 'fa000000-0000-4000-8000-000000000001',
      transporteNombre: null,
      conductorNombre: null,
      productoNombre: null,
      almacenNombre: null,
      pesoEntradaVehiculo: 38250.0,
      fechaHoraEntrada: now,
      estadoBoleto: 'PENDIENTE',
      createdAt: now,
      updatedAt: now,
    );
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TicketPreviewDialog(
            weighing: sinNombres,
            initialPreset: const PrinterPreset(boletosPorHoja: 2),
            onConfirmPrint: (formato, preset) {},
            empresaPerfilFuture: Future.value(_perfilDemo),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('N/A'), findsWidgets);
    expect(find.textContaining('fe000000'), findsNothing);
    expect(find.textContaining('f1000000'), findsNothing);
    expect(find.textContaining('fa000000'), findsNothing);
  });

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

  testWidgets('Muestra los datos reales de la empresa en el encabezado', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(createWidgetUnderTest(
      empresaPerfilFuture: Future.value(_perfilDemo),
      initialPreset: const PrinterPreset(
        boletosPorHoja: 1,
        tamanoPapel: 'Letter',
        mostrarEncabezado: true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('VARIEDADES S&S C.A.'), findsOneWidget);
    expect(find.textContaining('RIF: J-31490236-2'), findsOneWidget);
    expect(find.textContaining('+58 412-1234567'), findsOneWidget);
    expect(find.textContaining('Chacao, Caracas 1060'), findsOneWidget);
    // La fallback demo queda reemplazada por los datos reales del backend.
    expect(find.text('demo_company'.tr()), findsNothing);
  });

  testWidgets('El térmico no muestra logo pero sí el resto de la empresa', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(createWidgetUnderTest(
      empresaPerfilFuture: Future.value(_perfilDemo),
      initialPreset: const PrinterPreset(
        boletosPorHoja: 1,
        tamanoPapel: '80mm',
        mostrarEncabezado: true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('VARIEDADES S&S C.A.'), findsOneWidget);
    expect(find.textContaining('+58 412-1234567'), findsOneWidget);
  });

  testWidgets('Sin perfil cae al nombre demo sin romper', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    expect(find.text('demo_company'.tr()), findsOneWidget);
    expect(find.textContaining('Previsualización del Boleto: TA-00000001'), findsOneWidget);
  });
}
