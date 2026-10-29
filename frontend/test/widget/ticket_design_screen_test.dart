import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:balansoft_ws/core/theme/app_theme.dart';
import 'package:balansoft_ws/data/datasources/local/local_storage.dart';
import 'package:balansoft_ws/data/datasources/remote/api_client.dart';
import 'package:balansoft_ws/domain/entities/user.dart';
import 'package:balansoft_ws/domain/repositories/i_auth_repository.dart';
import 'package:balansoft_ws/domain/usecases/auth_usecases.dart';
import 'package:balansoft_ws/injection.dart' as di;
import 'package:balansoft_ws/presentation/providers/bloc/auth/auth_bloc.dart';
import 'package:balansoft_ws/presentation/screens/settings/ticket_design_screen.dart';

/// La configuración de **edición de boletos** (tope por boleto) y de **envío a
/// impresora** vive en `empresas` y solo la cambia el rol ADMIN (migración 024).
///
/// El resto de la pantalla (`PrinterPreset`) es una preferencia **local del
/// dispositivo** y no se toca aquí: son dos alcances distintos y no deben
/// mezclarse en el mismo guardado.
class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super();

  final List<Map<String, dynamic>> puts = [];
  Map<String, dynamic> empresa = {
    'max_ediciones_boleto': null,
    'impresion_automatica': false,
    'protocolo_impresion': null,
    'impresora_nombre': null,
    'impresora_host': null,
    'impresora_puerto': null,
  };

  @override
  Future<Map<String, dynamic>> getEmpresaPerfil() async => Map.of(empresa);

  @override
  Future<Map<String, dynamic>> updateEmpresaPerfil(
    Map<String, dynamic> body,
  ) async {
    puts.add(Map.of(body));
    empresa = {...empresa, ...body};
    return Map.of(empresa);
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
  Future<User?> refrescarEmpresaEnUsuarioCacheado() async => usuario;

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
    di.sl.registerLazySingleton<LocalStorage>(() => LocalStorage());
  });

  Widget buildApp(User usuario) {
    final repo = _FakeAuthRepository(usuario);
    final authBloc = AuthBloc(
      loginUseCase: LoginUseCase(repo),

      logoutUseCase: LogoutUseCase(repo),
      getCachedUserUseCase: GetCachedUserUseCase(repo),
      restoreSessionUseCase: RestoreSessionUseCase(repo),
      forgotPasswordUseCase: ForgotPasswordUseCase(repo),
      resetPasswordUseCase: ResetPasswordUseCase(repo),
      refrescarEmpresaUseCase: RefrescarEmpresaUseCase(repo),
    )..add(const CheckAuthStatusEvent());

    return BlocProvider<AuthBloc>(
      create: (_) => authBloc,
      child: MaterialApp(
        theme: buildLightTheme(),
        home: const TicketDesignScreen(),
      ),
    );
  }

  Future<void> render(WidgetTester tester, User usuario) async {
    // Ventana alta: la tarjeta nueva debe caber para poder tocarla sin scroll.
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildApp(usuario));
    await tester.pumpAndSettle();
  }

  testWidgets('el OPERADOR no ve la configuración de edición e impresión',
      (tester) async {
    await render(tester, _operador);

    expect(find.text('Edición e impresión'), findsNothing);
    expect(find.text('Máximo de ediciones por boleto'), findsNothing);
    expect(
      find.text('¿Enviar a impresora tras generar el ticket?'),
      findsNothing,
    );
    // Sin llamada al backend: la pantalla no consulta la empresa para el
    // operador (solo la vería para mostrarla, y no se muestra).
    expect(api.puts, isEmpty);
  });

  testWidgets('el ADMIN ve el tope, el interruptor y el protocolo como ADMIN',
      (tester) async {
    await render(tester, _admin);

    expect(find.text('Edición e impresión'), findsOneWidget);
    expect(find.text('Máximo de ediciones por boleto'), findsOneWidget);
    expect(
      find.text('¿Enviar a impresora tras generar el ticket?'),
      findsOneWidget,
    );
    expect(find.text('Protocolo de envío'), findsOneWidget);
    expect(find.text('ADMIN'), findsOneWidget);
  });

  testWidgets('el ADMIN guarda el tope y el protocolo en la empresa',
      (tester) async {
    await render(tester, _admin);

    await tester.enterText(
      find.widgetWithText(TextField, 'Máximo de ediciones por boleto'),
      '3',
    );
    // Elegir el protocolo RAW abre los campos de destino.
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, 'Protocolo de envío'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('RAW (puerto 9100)').last);
    await tester.pumpAndSettle();

    expect(find.text('Host / IP'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Host / IP'),
        '192.168.1.50');
    await tester.enterText(
      find.widgetWithText(TextField, 'Puerto'),
      '9100',
    );

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(api.puts, hasLength(1));
    final enviado = api.puts.single;
    expect(enviado['max_ediciones_boleto'], 3);
    expect(enviado['protocolo_impresion'], 'raw_9100');
    expect(enviado['impresora_host'], '192.168.1.50');
    expect(enviado['impresora_puerto'], 9100);
    // Lo que no se tocó va explícito como nulo, no ausente.
    expect(enviado.containsKey('impresion_automatica'), isTrue);
    expect(enviado['impresion_automatica'], isFalse);
  });

  testWidgets('vaciar el tope se guarda como nulo (sin tope)', (tester) async {
    await render(tester, _admin);

    // El campo filtra a dígitos, así que vaciarlo es la vía de un valor nulo
    // válido; una entrada basura no llega a existir. Se comprueba que vacío
    // significa «sin tope» (nulo).
    await tester.enterText(
      find.widgetWithText(TextField, 'Máximo de ediciones por boleto'),
      '',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(api.puts, hasLength(1));
    expect(api.puts.single['max_ediciones_boleto'], isNull);
  });
}
