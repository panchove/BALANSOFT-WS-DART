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

Widget _wrapConfigurable(
  ScaleTcpClient client, {
  int? baudrate = 9600,
  Future<void> Function(int)? onBaudrateCambiado,
  bool puedeEditarBaudrate = true,
  Duration intervalo = const Duration(seconds: 2),
  ValueChanged<Duration>? onIntervaloCambiado,
  bool permitirCambiarFuente = true,
}) =>
    MaterialApp(
      home: Scaffold(
        body: ScaleMonitorWidget(
          client: client,
          initialWeight: 0,
          mostrarBotones: false,
          permitirCambiarFuente: permitirCambiarFuente,
          baudrate: baudrate,
          onBaudrateCambiado: onBaudrateCambiado,
          puedeEditarBaudrate: puedeEditarBaudrate,
          intervaloActualizacion: intervalo,
          onIntervaloCambiado: onIntervaloCambiado,
        ),
      ),
    );

/// Abre el engranaje del display.
Future<void> _abrirEngranaje(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.settings));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('muestra "Recibiendo peso…" mientras el peso cambia',
      (tester) async {
    final client = _FakeScaleClient(sample: _muestra(123.4, 'reading'));

    await tester.pumpWidget(_wrap(client));

    expect(find.textContaining('Recibiendo peso'), findsOneWidget);
    expect(find.text('123.40'), findsOneWidget);
  });

  testWidgets('muestra "Estable" cuando el peso se asienta', (tester) async {
    final client = _FakeScaleClient(sample: _muestra(250.0, 'stable'));

    await tester.pumpWidget(_wrap(client));

    expect(find.textContaining('Estable'), findsOneWidget);
    expect(find.textContaining('Recibiendo peso'), findsNothing);
  });

  group('engranaje de configuración del display', () {
    testWidgets('sin nada que configurar no aparece el engranaje',
        (tester) async {
      final client = _FakeScaleClient(sample: _muestra(10, 'stable'));

      await tester.pumpWidget(
        _wrapConfigurable(client, baudrate: null, permitirCambiarFuente: false),
      );

      expect(find.byIcon(Icons.settings), findsNothing);
    });

    testWidgets('abre el diálogo con fuente, baudios y refresco',
        (tester) async {
      final client = _FakeScaleClient(sample: _muestra(10, 'stable'));

      await tester.pumpWidget(
        _wrapConfigurable(client, onIntervaloCambiado: (_) {}),
      );
      await _abrirEngranaje(tester);

      expect(find.text('Configuración del display'), findsOneWidget);
      expect(find.byKey(const Key('display_font_dropdown')), findsOneWidget);
      expect(
          find.byKey(const Key('display_baudrate_dropdown')), findsOneWidget);
      expect(
          find.byKey(const Key('display_refresh_dropdown')), findsOneWidget);
    });

    testWidgets('cambiar los baudios dispara el callback con el valor elegido',
        (tester) async {
      final client = _FakeScaleClient(sample: _muestra(10, 'stable'));
      int? elegido;

      await tester.pumpWidget(
        _wrapConfigurable(
          client,
          onBaudrateCambiado: (b) async => elegido = b,
        ),
      );
      await _abrirEngranaje(tester);

      await tester.tap(find.byKey(const Key('display_baudrate_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('19200').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('display_config_apply')));
      await tester.pumpAndSettle();

      expect(elegido, 19200);
      expect(find.textContaining('19200'), findsOneWidget);
    });

    testWidgets('sin permiso el selector de baudios queda bloqueado',
        (tester) async {
      final client = _FakeScaleClient(sample: _muestra(10, 'stable'));

      await tester.pumpWidget(
        _wrapConfigurable(
          client,
          puedeEditarBaudrate: false,
          onBaudrateCambiado: (_) async {},
        ),
      );
      await _abrirEngranaje(tester);

      final dropdown = tester.widget<DropdownButtonFormField<int>>(
        find.byKey(const Key('display_baudrate_dropdown')),
      );
      expect(dropdown.onChanged, isNull);
      expect(
        find.textContaining('Solo un administrador'),
        findsOneWidget,
      );
    });

    testWidgets('si guardar los baudios falla avisa y no rompe',
        (tester) async {
      final client = _FakeScaleClient(sample: _muestra(10, 'stable'));

      await tester.pumpWidget(
        _wrapConfigurable(
          client,
          onBaudrateCambiado: (_) async => throw Exception('sin red'),
        ),
      );
      await _abrirEngranaje(tester);

      await tester.tap(find.byKey(const Key('display_baudrate_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('38400').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('display_config_apply')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No se pudo guardar la velocidad'),
        findsOneWidget,
      );
    });

    testWidgets('cambiar la frecuencia de refresco dispara el callback',
        (tester) async {
      final client = _FakeScaleClient(sample: _muestra(10, 'stable'));
      Duration? elegido;

      await tester.pumpWidget(
        _wrapConfigurable(
          client,
          onIntervaloCambiado: (d) => elegido = d,
        ),
      );
      await _abrirEngranaje(tester);

      await tester.tap(find.byKey(const Key('display_refresh_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('250 ms').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('display_config_apply')));
      await tester.pumpAndSettle();

      expect(elegido, const Duration(milliseconds: 250));
    });
  });
}
