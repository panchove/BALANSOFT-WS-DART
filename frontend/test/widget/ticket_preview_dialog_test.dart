import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
          initialPreset: initialPreset ?? const PrinterPreset(),
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
            initialPreset: const PrinterPreset(copias: 2),
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
            initialPreset: const PrinterPreset(copias: 2),
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
    expect(find.text('tickets_to_print'.tr()), findsOneWidget);
    expect(find.text('PDF'), findsWidgets);
    expect(find.text('TXT'), findsOneWidget);
    expect(find.text('Confirmar e Imprimir (1)'), findsOneWidget);
  });

  testWidgets('Cantidad de tickets no apila el boleto en la hoja', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(createWidgetUnderTest(
      initialPreset: const PrinterPreset(copias: 3, tamanoPapel: 'Letter'),
    ));
    await tester.pumpAndSettle();

    // «Cantidad de tickets» son N boletos completos: el preview muestra un
    // único bloque y ya no dibuja líneas de corte por página.
    expect(find.byIcon(Icons.content_cut), findsNothing);
    expect(find.text('Preset: Letter | PORTRAIT | 3 ticket(s)'), findsOneWidget);
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
        copias: 1,
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
        copias: 1,
        tamanoPapel: '80mm',
        mostrarEncabezado: true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('VARIEDADES S&S C.A.'), findsOneWidget);
    expect(find.textContaining('+58 412-1234567'), findsOneWidget);
  });

  testWidgets('El térmico muestra la tabla de lecturas con sus 5 columnas',
      (tester) async {
    final conRemolque = Weighing(
      boleto: 'b1b2b3b4-b5b6-4b7b-8b9b-babbbcbdbebf',
      numeroBoleto: 'TA-00000042',
      idVehiculo: 'ABC123',
      remolque: true,
      remolquePlaca: 'RTA987',
      pesoEntradaVehiculo: 50000.0,
      pesoEntradaRemolque: 12500.0,
      pesoSalidaVehiculo: 45000.0,
      pesoSalidaRemolque: 11500.0,
      pesoNeto: 7500.0,
      fechaHoraEntrada: now.subtract(const Duration(minutes: 45)),
      fechaHoraSalida: now,
      estadoBoleto: 'CERRADO',
      createdAt: now,
      updatedAt: now,
    );
    await tester.binding.setSurfaceSize(const Size(1280, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TicketPreviewDialog(
          weighing: conRemolque,
          initialPreset: const PrinterPreset(
            copias: 1,
            tamanoPapel: '80mm',
            mostrarEncabezado: true,
          ),
          onConfirmPrint: (_, __) {},
          empresaPerfilFuture: Future.value(_perfilDemo),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Cabecera de la tabla: (vacío) | Fec, Hrs | CAMIÓN | REMOLQUE | TOTAL.
    expect(find.text('ticket_col_datetime'.tr()), findsOneWidget);
    expect(find.text('ticket_col_camion'.tr()), findsOneWidget);
    expect(find.text('ticket_col_remolque'.tr()), findsOneWidget);
    expect(find.text('ticket_col_total'.tr()), findsOneWidget);
    // Una fila por pesada + la de TOTALES (los netos por vehículo).
    expect(find.text('${'ticket_col_entry'.tr()}:'), findsOneWidget);
    expect(find.text('${'ticket_col_exit'.tr()}:'), findsOneWidget);
    expect(find.text('${'ticket_col_totales'.tr()}:'), findsOneWidget);
    expect(find.text('PESO NETO:'), findsOneWidget);
    // 'Camión:'/'Remolque:' solo salen ya en la cabecera de datos.
    expect(find.text('Camión:'), findsOneWidget);
    expect(find.text('Remolque:'), findsOneWidget);
    // El desglose por vehículo en las tres filas: entrada, salida y netos.
    for (final valor in [
      '50.000,00 kg', // camión, entrada
      '12.500,00 kg', // remolque, entrada
      '62.500,00 kg', // total, entrada
      '45.000,00 kg', // camión, salida
      '11.500,00 kg', // remolque, salida
      '56.500,00 kg', // total, salida
      '5.000,00 kg', // neto camión
      '1.000,00 kg', // neto remolque
    ]) {
      expect(find.text(valor), findsOneWidget, reason: valor);
    }
    // El neto sale dos veces: en TOTALES y en el PESO NETO.
    expect(find.text('7.500,00 kg'), findsNWidgets(2));
    expect(find.textContaining('(INGRESO)'), findsOneWidget);
  });

  testWidgets('El térmico sin remolque mantiene la rejilla de 5 columnas',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(createWidgetUnderTest(
      initialPreset: const PrinterPreset(
        copias: 1,
        tamanoPapel: '80mm',
        mostrarEncabezado: true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('ticket_col_camion'.tr()), findsOneWidget);
    expect(find.text('ticket_col_remolque'.tr()), findsOneWidget);
    expect(find.text('${'ticket_col_totales'.tr()}:'), findsOneWidget);
    expect(find.text('0,00 kg'), findsNWidgets(2)); // remolque: entrada y neto
    // Sin remolque, 'Remolque:' solo aparece en la cabecera de datos.
    expect(find.text('Remolque:'), findsOneWidget);
  });

  testWidgets('El térmico reparte etiqueta y valor en DOS columnas alineadas',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(createWidgetUnderTest(
      initialPreset: const PrinterPreset(
        copias: 1,
        tamanoPapel: '80mm',
        mostrarEncabezado: true,
      ),
    ));
    await tester.pumpAndSettle();

    // Espejo del PDF: la etiqueta va a la DERECHA de su celda y el valor a la
    // IZQUIERDA de la suya, cada mitad con su alineación (una sola variable
    // movería las dos).
    final Text etiqueta = tester.widget<Text>(find.text('Camión:').first);
    expect(etiqueta.textAlign, TextAlign.right);
    final Text valor = tester.widget<Text>(find.text('ABC123'));
    expect(valor.textAlign, TextAlign.left);
    // Son celdas distintas: el valor arranca a la derecha de la etiqueta.
    final cajaEtiqueta = tester.getRect(find.text('Camión:').first);
    final cajaValor = tester.getRect(find.text('ABC123'));
    expect(cajaValor.left, greaterThan(cajaEtiqueta.left));
    expect(cajaValor.left, greaterThanOrEqualTo(cajaEtiqueta.right));
  });

  testWidgets('La hoja (media carta/Carta/A4) usa las DOS columnas del térmico',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(createWidgetUnderTest(
      initialPreset:
          const PrinterPreset(copias: 1, tamanoPapel: 'Letter'),
    ));
    await tester.pumpAndSettle();

    // La hoja imprime el bloque de DATOS igual que el rollo (espejo de la tabla
    // de 2 celdas del PDF): etiqueta a la DERECHA de su columna y valor a la
    // IZQUIERDA de la siguiente.
    final Text etiqueta = tester.widget<Text>(find.text('Camión:').first);
    expect(etiqueta.textAlign, TextAlign.right);

    final Text valor = tester.widget<Text>(find.text('ABC123').first);
    expect(valor.textAlign, TextAlign.left);

    final Rect etiquetaRect = tester.getRect(find.text('Camión:').first);
    final Rect valorRect = tester.getRect(find.text('ABC123').first);
    expect(valorRect.left, greaterThan(etiquetaRect.left));
    expect(valorRect.left, greaterThanOrEqualTo(etiquetaRect.right));
  });

  testWidgets('La hoja usa la MISMA tabla de lecturas que el térmico',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(createWidgetUnderTest(
      initialPreset:
          const PrinterPreset(copias: 1, tamanoPapel: 'Letter'),
    ));
    await tester.pumpAndSettle();

    // Misma rejilla que el rollo: (vacío) | Fec, Hrs | CAMIÓN | REMOLQUE | TOTAL.
    expect(find.text('ticket_col_datetime'.tr()), findsOneWidget);
    expect(find.text('ticket_col_camion'.tr()), findsOneWidget);
    expect(find.text('ticket_col_remolque'.tr()), findsOneWidget);
    expect(find.text('ticket_col_total'.tr()), findsOneWidget);
    expect(find.text('${'ticket_col_entry'.tr()}:'), findsOneWidget);
    expect(find.text('${'ticket_col_exit'.tr()}:'), findsOneWidget);
    expect(find.text('${'ticket_col_totales'.tr()}:'), findsOneWidget);
    // La columna de etiquetas va a la IZQUIERDA y las de kilos a la DERECHA.
    expect(
      tester.widget<Text>(find.text('${'ticket_col_entry'.tr()}:')).textAlign,
      TextAlign.left,
    );
    expect(
      tester.widget<Text>(find.text('50.000,00 kg').first).textAlign,
      TextAlign.right,
    );
  });

  testWidgets('Sin perfil cae al nombre demo sin romper', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    expect(find.text('demo_company'.tr()), findsOneWidget);
    expect(find.textContaining('Previsualización del Boleto: TA-00000001'), findsOneWidget);
  });

  testWidgets('Enter imprime sin usar el ratón', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    String? formato;
    PrinterPreset? preset;
    await tester.pumpWidget(createWidgetUnderTest(
      initialPreset: const PrinterPreset(copias: 2),
      onConfirmPrint: (f, p) {
        formato = f;
        preset = p;
      },
    ));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(formato, equals('PDF'));
    expect(preset?.copias, equals(2));
  });

  testWidgets('Enter del teclado numérico también imprime', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var confirmaciones = 0;
    await tester.pumpWidget(createWidgetUnderTest(
      onConfirmPrint: (_, __) => confirmaciones++,
    ));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    await tester.pump();

    expect(confirmaciones, equals(1));
  });
}
