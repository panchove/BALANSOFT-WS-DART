import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:balansoft_ws/core/theme/app_theme.dart';
import 'package:balansoft_ws/data/datasources/remote/api_client.dart';
import 'package:balansoft_ws/data/repositories/sesiones_repository.dart';
import 'package:balansoft_ws/domain/entities/sesion_equipo.dart';
import 'package:balansoft_ws/presentation/screens/sesiones/sesiones_screen.dart';

class _DummyApi extends ApiClient {}

/// Repositorio en memoria: ni red ni servidor central.
class _FakeSesiones extends SesionesRepository {
  _FakeSesiones(SesionesEquipo data) : _data = data, super(apiClient: _DummyApi());

  final SesionesEquipo _data;
  bool sinCredencial = false;
  int actualizaciones = 0;
  String? ultimoId;
  String? ultimoEstado;
  String? ultimoRol;

  @override
  Future<SesionesEquipo> listar() async {
    if (sinCredencial) throw StateError('Sin credencial');
    return _data;
  }

  @override
  Future<SesionEquipo> actualizar(
    String idDispositivo, {
    String? estado,
    String? rolSesion,
  }) async {
    actualizaciones++;
    ultimoId = idDispositivo;
    ultimoEstado = estado;
    ultimoRol = rolSesion;
    final equipo = _data.items.firstWhere((e) => e.idDispositivo == idDispositivo);
    return SesionEquipo(
      idDispositivo: equipo.idDispositivo,
      hardwareId: equipo.hardwareId,
      nombreEquipo: equipo.nombreEquipo,
      estado: estado ?? equipo.estado,
      rolSesion: rolSesion ?? equipo.rolSesion,
    );
  }
}

SesionEquipo _equipo({
  String id = 'd-1',
  String nombre = 'Estación 1',
  String estado = SesionEquipo.estadoPendiente,
  String? rol,
  bool dueno = false,
}) =>
    SesionEquipo(
      idDispositivo: id,
      hardwareId: 'HW-$id',
      nombreEquipo: nombre,
      sistemaOperativo: 'Linux',
      versionApp: '1.0.0',
      estado: estado,
      rolSesion: rol,
      esDueno: dueno,
    );

Widget _montar(SesionesRepository repo) => MaterialApp(
      theme: buildLightTheme(),
      locale: const Locale('es'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es')],
      home: SesionesScreen(repository: repo),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('lista los equipos de la cuenta', (tester) async {
    final repo = _FakeSesiones(SesionesEquipo(items: [
      _equipo(id: 'a', nombre: 'Caja 1'),
      _equipo(id: 'b', nombre: 'Caja 2', estado: SesionEquipo.estadoAprobado),
    ]));

    await tester.pumpWidget(_montar(repo));
    await tester.pumpAndSettle();

    expect(find.text('Sesiones y Equipos'), findsOneWidget);
    expect(find.text('Caja 1'), findsOneWidget);
    expect(find.text('Caja 2'), findsOneWidget);
    expect(find.byKey(const Key('sesiones_pendientes_chip')), findsOneWidget);
  });

  testWidgets('el equipo titular no se puede modificar', (tester) async {
    final repo = _FakeSesiones(SesionesEquipo(
      items: [_equipo(id: 't', nombre: 'Torre', dueno: true)],
      hardwareTitular: 'HW-t',
    ));

    await tester.pumpWidget(_montar(repo));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sesion_aprobar_t')), findsNothing);
    expect(find.byKey(const Key('sesion_rechazar_t')), findsNothing);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
  });

  testWidgets('aprobar abre el diálogo, asigna rol y llama al backend',
      (tester) async {
    final repo = _FakeSesiones(SesionesEquipo(
      items: [_equipo(id: 'a')],
      maxEquipos: 3,
    ));

    await tester.pumpWidget(_montar(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sesion_aprobar_a')));
    await tester.pumpAndSettle();

    // El diálogo exige elegir rol (por defecto OPERADOR).
    expect(find.byKey(const Key('sesiones_rol_dropdown')), findsOneWidget);
    await tester.tap(find.byKey(const Key('sesiones_confirmar_aprobar')));
    await tester.pumpAndSettle();

    expect(repo.actualizaciones, 1);
    expect(repo.ultimoId, 'a');
    expect(repo.ultimoEstado, SesionEquipo.estadoAprobado);
    expect(repo.ultimoRol, 'OPERADOR');
  });

  testWidgets('rechazar pide confirmación y llama al backend', (tester) async {
    final repo = _FakeSesiones(SesionesEquipo(items: [_equipo(id: 'a')]));

    await tester.pumpWidget(_montar(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sesion_rechazar_a')));
    await tester.pumpAndSettle();
    expect(find.textContaining('¿Rechazar este equipo?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sesiones_confirmar_rechazar')));
    await tester.pumpAndSettle();

    expect(repo.actualizaciones, 1);
    expect(repo.ultimoEstado, SesionEquipo.estadoRechazado);
  });

  testWidgets('cancelar el rechazo no llama al backend', (tester) async {
    final repo = _FakeSesiones(SesionesEquipo(items: [_equipo(id: 'a')]));

    await tester.pumpWidget(_montar(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sesion_rechazar_a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(repo.actualizaciones, 0);
  });

  testWidgets('sin credencial del servidor central lo explica',
      (tester) async {
    final repo = _FakeSesiones(const SesionesEquipo())..sinCredencial = true;

    await tester.pumpWidget(_montar(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('servidor central'), findsOneWidget);
  });
}
