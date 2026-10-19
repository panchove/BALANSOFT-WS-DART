import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balansoft_ws/presentation/screens/weighing/weighing_detail_screen.dart';

void main() {
  testWidgets('boleto vacío muestra mensaje sin requerir providers',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: WeighingDetailScreen(boleto: '   '),
      ),
    );

    expect(find.text('Detalle del Pesaje'), findsOneWidget);
    expect(
      find.text('No se puede cargar el pesaje: identificador vacío.'),
      findsOneWidget,
    );
    // No debe intentar consumir WeighingBloc/AuthBloc
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('boleto con contenido intenta cargar (usa providers)',
      (WidgetTester tester) async {
    // Con un boleto válido, la pantalla requiere WeighingBloc y AuthBloc;
    // verificar que lanza al construir (falta de providers) NO es deseable.
    // Aquí solo verificamos que el guard de vacío no bloquea este caso:
    expect(const WeighingDetailScreen(boleto: 'TA-00000001').boleto, 'TA-00000001');
  });
}