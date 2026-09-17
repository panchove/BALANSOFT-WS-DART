import 'package:balansoft_ws/core/widgets/scale_monitor_widget.dart';
import 'package:balansoft_ws/data/services/scale_tcp_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeScaleClient extends ScaleTcpClient {
  _FakeScaleClient({this.sample});

  final PesoEnVivo? sample;

  @override
  bool get conectado => true;
  @override
  bool get conectando => false;
  @override
  String get error => '';
  @override
  PesoEnVivo? get ultimoPeso => sample;
  @override
  double? get pesoActual => sample?.pesoKg;
  @override
  String get host => '127.0.0.1';
  @override
  int get port => 5555;

  @override
  Future<void> conectar([String? host, int port = 5555]) async {}
}

PesoEnVivo _muestra(double kg, String estado) => PesoEnVivo(
      pesoKg: kg,
      estado: estado,
      timestamp: DateTime.now(),
    );

Widget _wrap(ScaleTcpClient client) => MaterialApp(
      home: Scaffold(
        body: ScaleMonitorWidget(
          client: client,
          initialWeight: 123.4,
          mostrarBotones: false,
        ),
      ),
    );

void main() {
  testWidgets('muestra "Recibiendo peso…" mientras el peso cambia',
      (tester) async {
    final client = _FakeScaleClient(sample: _muestra(123.4, 'reading'));

    await tester.pumpWidget(_wrap(client));

    expect(find.textContaining('Recibiendo peso'), findsOneWidget);
    expect(find.text('123.4'), findsOneWidget);
  });

  testWidgets('muestra "Estable" cuando el peso se asienta', (tester) async {
    final client = _FakeScaleClient(sample: _muestra(250.0, 'stable'));

    await tester.pumpWidget(_wrap(client));

    expect(find.textContaining('Estable'), findsOneWidget);
    expect(find.textContaining('Recibiendo peso'), findsNothing);
  });
}
