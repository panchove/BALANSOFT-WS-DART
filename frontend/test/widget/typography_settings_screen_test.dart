import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:balansoft_ws/core/controllers/typography_controller.dart';
import 'package:balansoft_ws/core/i18n/translations.dart';
import 'package:balansoft_ws/core/theme/app_theme.dart';
import 'package:balansoft_ws/data/datasources/remote/api_client.dart';
import 'package:balansoft_ws/domain/entities/user.dart';
import 'package:balansoft_ws/domain/repositories/i_auth_repository.dart';
import 'package:balansoft_ws/domain/usecases/auth_usecases.dart';
import 'package:balansoft_ws/injection.dart' as di;
import 'package:balansoft_ws/presentation/providers/bloc/auth/auth_bloc.dart';
import 'package:balansoft_ws/presentation/screens/settings/typography_settings_screen.dart';

/// Backend de la empresa en memoria: guarda lo que recibe por `PUT` y lo
/// devuelve por `GET`, igual que `empresas.tamano_ticket_pdf`.
class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super();

  String tamano = 'AUTOMATICO';
  final List<Map<String, dynamic>> puts = [];
  bool getFalla = false;
  bool putFalla = false;
  int gets = 0;

  @override
  Future<Map<String, dynamic>> getEmpresaPerfil() async {
    gets++;
    if (getFalla) throw StateError('sin conexion con la estacion');
    return {'tamano_ticket_pdf': tamano};
  }

  @override
  Future<Map<String, dynamic>> updateEmpresaPerfil(
    Map<String, dynamic> body,
  ) async {
    puts.add(body);
    if (putFalla) throw StateError('403 Forbidden');
    final v = body['tamano_ticket_pdf'];
    if (v is String) tamano = v;
    return {'tamano_ticket_pdf': tamano};
  }
}

class _FakeAuthRepository implements IAuthRepository {
  _FakeAuthRepository(this.usuario);

  final User usuario;

  @override
  Future<User> login({
    required String email,
    required String password,
    String? hardwareId,
    String? deviceBrand,
    String? deviceModel,
    String? osVersion,
    String? macAddress,
  }) async =>
      usuario;

  @override
  Future<User> register({
    required String empresaNombre,
    required String empresaRif,
    required String usuarioNombre,
    required String email,
    required String password,
    String? licenciaKey,
  }) async =>
      usuario;

  @override
  Future<void> logout() async {}

  @override
  Future<String> refreshToken(String refreshToken) async => 'token';

  @override
  Future<String?> refreshAccessToken() async => 'token';

  @override
  Future<void> forgotPassword(String email) async {}

  @override
  Future<void> resetPassword(String token, String newPassword) async {}

  @override
  Future<User?> getCachedUser() async => usuario;

  @override
  Future<SesionRestaurada> restoreSession() async => SesionRestaurada.ok;

  @override
  Future<void> cacheUser(User user) async {}

  @override
  Future<void> clearCache() async {}
}

const _admin = User(
  idUsuario: 'u-admin',
  nombre: 'Administrador',
  email: 'admin@balansoft.com.ve',
  rol: 'ADMIN',
  idEmpresa: 'emp-1',
);

const _operador = User(
  idUsuario: 'u-op',
  nombre: 'Operador',
  email: 'op@balansoft.com.ve',
  rol: 'OPERADOR',
  idEmpresa: 'emp-1',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeApiClient api;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    api = _FakeApiClient();
    // El reset de GetIt es asíncrono: sin await su continuación se ejecuta
    // dentro del FakeAsync de testWidgets y borra lo registrado después.
    await di.sl.reset();
    di.sl.registerLazySingleton<ApiClient>(() => api);
  });

  Widget buildApp(User usuario) {
    final repo = _FakeAuthRepository(usuario);
    final authBloc = AuthBloc(
      loginUseCase: LoginUseCase(repo),
      registerUseCase: RegisterUseCase(repo),
      logoutUseCase: LogoutUseCase(repo),
      getCachedUserUseCase: GetCachedUserUseCase(repo),
      restoreSessionUseCase: RestoreSessionUseCase(repo),
      forgotPasswordUseCase: ForgotPasswordUseCase(repo),
      resetPasswordUseCase: ResetPasswordUseCase(repo),
    )..add(const CheckAuthStatusEvent());

    return BlocProvider<AuthBloc>(
      create: (_) => authBloc,
      child: MaterialApp(
        theme: buildLightTheme(),
        home: const TypographySettingsScreen(),
      ),
    );
  }

  Future<void> render(WidgetTester tester, User usuario) async {
    // Ventana alta: las 5 familias, el factor y el selector del ticket deben
    // caber sin scroll para poder tocarlos.
    tester.view.physicalSize = const Size(1100, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildApp(usuario));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('ofrece las 5 familias de REQ-FN-007 con etiqueta traducida',
      (tester) async {
    await render(tester, _operador);

    expect(find.text('Familia de letra de la interfaz'), findsOneWidget);
    expect(find.text('Sistema (por defecto)'), findsOneWidget);
    expect(find.text('Sans Serif'), findsOneWidget);
    expect(find.text('Serif'), findsOneWidget);
    expect(find.text('Monospace'), findsOneWidget);
    expect(find.text('Roboto'), findsOneWidget);

    // RadioListTile dense por familia, con la del sistema marcada.
    expect(find.byType(RadioListTile<String>), findsNWidgets(5));
    final sistema = tester.widget<RadioListTile<String>>(
      find.widgetWithText(RadioListTile<String>, 'Sistema (por defecto)'),
    );
    expect(sistema.value, equals('SISTEMA'));
  });

  testWidgets('elegir una familia la persiste en el dispositivo',
      (tester) async {
    await render(tester, _operador);

    await tester.tap(find.text('Serif'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app.familiaUi'), equals('SERIF'));

    // Y la vista previa usa esa familia.
    final previa = tester.widget<Text>(find.text('AaBbCc 0123456789'));
    expect(previa.style?.fontFamily, equals('serif'));
  });

  testWidgets('ADMIN ve el selector del ticket y lo guarda en la empresa',
      (tester) async {
    await render(tester, _admin);

    expect(find.text('Tamaño del ticket PDF'), findsOneWidget);

    await tester.tap(find.text('Pequeño'));
    await tester.pumpAndSettle();

    // PUT con el valor pedido y GET para releer lo que quedó guardado.
    expect(api.puts, hasLength(1));
    expect(api.puts.single['tamano_ticket_pdf'], equals('PEQUENO'));
    expect(api.gets, greaterThanOrEqualTo(2));
    expect(
        find.textContaining('Tamaño del ticket actualizado'), findsOneWidget);
  });

  testWidgets('el valor guardado en la empresa se refleja al abrir',
      (tester) async {
    api.tamano = 'MEDIANO';
    await render(tester, _admin);

    expect(find.text('Tamaño del ticket PDF'), findsOneWidget);
    final boton = tester.widget<SegmentedButton<String>>(
      find.byType(SegmentedButton<String>),
    );
    expect(boton.selected, equals({'MEDIANO'}));
  });

  testWidgets('un rol distinto de ADMIN no ve el selector del ticket',
      (tester) async {
    await render(tester, _operador);

    // Los ajustes del dispositivo (familia y tamaño) sí están para todos.
    expect(find.text('Familia de letra de la interfaz'), findsOneWidget);
    expect(find.text('Tamaño del texto de la interfaz'), findsOneWidget);

    // El del ticket es un ajuste de la empresa: el PUT da 403 para el resto.
    expect(find.text('Tamaño del ticket PDF'), findsNothing);
    expect(find.byType(SegmentedButton<String>), findsNothing);
    expect(find.text('Fuente del ticket PDF'), findsOneWidget);
    expect(api.puts, isEmpty);
    expect(api.gets, isZero);
  });

  testWidgets('si el PUT falla se avisa y el valor local se conserva',
      (tester) async {
    api.putFalla = true;
    await render(tester, _admin);

    await tester.tap(find.text('Grande'));
    await tester.pumpAndSettle();

    expect(api.puts, hasLength(1));
    expect(find.textContaining('No se pudo guardar el tamaño del ticket'),
        findsOneWidget);

    // Offline-first: lo que eligió el operador no se pierde en este equipo.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('empresa.tamanoTicketPdf'), equals('GRANDE'));
  });

  testWidgets('si el GET inicial falla se avisa y se muestra el valor local',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'empresa.tamanoTicketPdf': 'GRANDE'});
    api.getFalla = true;
    await render(tester, _admin);

    expect(find.textContaining('No se pudo leer el tamaño del ticket'),
        findsOneWidget);
    final boton = tester.widget<SegmentedButton<String>>(
      find.byType(SegmentedButton<String>),
    );
    expect(boton.selected, equals({'GRANDE'}));
  });

  testWidgets('restablecer devuelve los valores por defecto y avisa',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'app.familiaUi': 'SERIF',
      'app.textScaleFactor': 1.25,
      'empresa.tamanoTicketPdf': 'PEQUENO',
    });
    api.tamano = 'PEQUENO';
    await render(tester, _admin);

    await tester.tap(find.text('Restablecer valores'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app.familiaUi'), equals('SISTEMA'));
    expect(prefs.getDouble('app.textScaleFactor'), closeTo(1.00, 1e-4));
    expect(prefs.getString('empresa.tamanoTicketPdf'), equals('AUTOMATICO'));

    // El ticket es de la empresa: también se manda al backend.
    expect(api.puts.single['tamano_ticket_pdf'], equals('AUTOMATICO'));
    expect(find.textContaining('Valores restaurados'), findsOneWidget);
  });

  testWidgets('las etiquetas cambian con el idioma', (tester) async {
    await render(tester, _operador);
    expect(find.text('Sistema (por defecto)'), findsOneWidget);

    // El texto en español se traduce al inglés por el mismo mecanismo.
    expect(AppTranslations.tr('tipografia_familia_sistema', langCode: 'en'),
        equals('System (default)'));
    expect(AppTranslations.tr('tipografia_familia_monospace', langCode: 'pt'),
        equals('Monoespaçada'));
  });

  testWidgets('el controlador expuesto es el de preferencias del dispositivo',
      (tester) async {
    await render(tester, _operador);
    expect(TypographyController.familiasUi, hasLength(5));
    expect(TypographyController.minUiScale, closeTo(0.85, 1e-9));
    expect(TypographyController.maxUiScale, closeTo(1.40, 1e-9));
  });

  // ── Instancia compartida (REQ-FN-004) ───────────────────────────────────
  //
  // El punto de fallo más caro de T9 no es pintar bien el texto: es que Ajustes
  // se haga su **propia copia** del controlador. El cambio se vería dentro de la
  // pantalla y en ningún otro sitio, `main.dart` seguiría con la instancia del
  // contenedor y no habría forma de notarlo mirando la UI. Estos dos tests
  // atacan esa rama del código (`di.sl.isRegistered` / fallback local) en vez
  // del pintado.

  testWidgets('con el controlador registrado la pantalla usa esa misma '
      'instancia, no una copia local', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final registrado = TypographyController(prefs: prefs);
    di.sl.registerSingleton<TypographyController>(registrado);

    await render(tester, _operador);

    // El slider y el selector de familia escriben sobre el objeto del
    // contenedor. Si la pantalla hubiera creado el suyo, esto no se movería.
    await tester.tap(find.text('Serif'));
    await tester.pumpAndSettle();
    expect(registrado.familiaUi, equals('SERIF'));

    await tester.drag(find.byType(Slider), const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(registrado.textScale, greaterThan(1.0));

    // Y lo que se guardó llegó a las preferencias del dispositivo.
    expect(prefs.getString('app.familiaUi'), equals('SERIF'));
  });

  testWidgets('sin el controlador registrado la pantalla se sostiene sola '
      '(no revienta)', (tester) async {
    expect(di.sl.isRegistered<TypographyController>(), isFalse);
    await render(tester, _operador);

    await tester.tap(find.text('Monospace'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app.familiaUi'), equals('MONOSPACE'));
  });
}
