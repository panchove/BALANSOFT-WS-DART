import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:balansoft_ws/core/config/app_config.dart';
import 'package:balansoft_ws/core/config/cuenta_activada.dart';
import 'package:balansoft_ws/core/i18n/locale_controller.dart';
import 'package:balansoft_ws/core/i18n/translations.dart';
import 'package:balansoft_ws/core/security/secure_storage_service.dart';
import 'package:balansoft_ws/data/datasources/local/local_storage.dart';
import 'package:balansoft_ws/data/datasources/remote/api_client.dart';
import 'package:balansoft_ws/data/repositories/activacion_repository.dart';
import 'package:balansoft_ws/domain/entities/user.dart';
import 'package:balansoft_ws/domain/repositories/i_auth_repository.dart';
import 'package:balansoft_ws/domain/usecases/auth_usecases.dart';
import 'package:balansoft_ws/presentation/providers/bloc/auth/auth_bloc.dart';
import 'package:balansoft_ws/presentation/screens/setup/activation_screen.dart';

/// Monta la pantalla de activación (paso 3 del modo servidor) con un
/// repositorio doble que simula la respuesta del servidor central.
Future<void> _montar(
  WidgetTester tester,
  ActivacionRepository repository, {
  void Function(String ruta)? onRuta,
}) async {
  // La pantalla es de instalación: se monta al tamaño real de las estaciones.
  tester.view.physicalSize = const Size(1366, 768);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final repo = _FakeAuthRepository();
  final authBloc = AuthBloc(
    loginUseCase: LoginUseCase(repo),
    registerUseCase: RegisterUseCase(repo),
    logoutUseCase: LogoutUseCase(repo),
    getCachedUserUseCase: GetCachedUserUseCase(repo),
    restoreSessionUseCase: RestoreSessionUseCase(repo),
    forgotPasswordUseCase: ForgotPasswordUseCase(repo),
    resetPasswordUseCase: ResetPasswordUseCase(repo),
  );

  await tester.pumpWidget(
    BlocProvider<AuthBloc>.value(
      value: authBloc,
      child: MaterialApp(
        home: ActivationScreen(repository: repository),
        onGenerateRoute: (settings) {
          onRuta?.call(settings.name ?? '');
          return MaterialPageRoute<void>(
            builder: (_) => Scaffold(body: Text(settings.name ?? '')),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocaleController localeController;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppConfig.init();
    localeController = LocaleController();
    await localeController.load();
    AppTranslations.setController(localeController);
  });

  tearDown(() async {
    await CuentaActivadaTestHelper.limpiar();
  });

  group('Paso 3 · activación de la cuenta', () {
    testWidgets('valida el correo antes de llamar al servidor central',
        (tester) async {
      final repo = ActivacionRepository(
        apiClient: ApiClient(baseUrl: 'http://localhost:8000'),
        localStorage: LocalStorage(),
        secureStorage: SecureStorageService(),
      );
      await _montar(tester, repo);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'activation_email'.tr()),
        'no-es-un-correo',
      );
      await tester.ensureVisible(find.text('activation_submit'.tr()));
      await tester.tap(find.text('activation_submit'.tr()));
      await tester.pumpAndSettle();

      // Ni el error de formato ni la llamada: sigue en la pantalla.
      expect(find.text('activation_email_invalid'.tr()), findsOneWidget);
      expect(find.byType(ActivationScreen), findsOneWidget);
    });

    testWidgets('exige correo y contraseña', (tester) async {
      final repo = ActivacionRepository(
        apiClient: ApiClient(baseUrl: 'http://localhost:8000'),
        localStorage: LocalStorage(),
        secureStorage: SecureStorageService(),
      );
      await _montar(tester, repo);

      await tester.ensureVisible(find.text('activation_submit'.tr()));
      await tester.tap(find.text('activation_submit'.tr()));
      await tester.pumpAndSettle();

      expect(find.text('activation_required'.tr()), findsNWidgets(2));
    });

    testWidgets('muestra el 403 cuando la licencia ya está en otra máquina',
        (tester) async {
      final repo = _repoCon(
        const ActivacionResultado(
          exito: false,
          error: 'Esta licencia ya está activa en otro equipo. '
              'Instale esta estación como Trabajador.',
        ),
      );
      await _montar(tester, repo);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'activation_email'.tr()),
        'titular@empresa.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'activation_password'.tr()),
        'clave-del-proveedor',
      );
      await tester.ensureVisible(find.text('activation_submit'.tr()));
      await tester.tap(find.text('activation_submit'.tr()));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Instale esta estación como Trabajador'),
        findsOneWidget,
      );
      // No se avanza al formulario de empresa.
      expect(find.byType(ActivationScreen), findsOneWidget);
    });

    testWidgets('con la cuenta validada sigue a la empresa precargada',
        (tester) async {
      final repo = _repoCon(
        const ActivacionResultado(
          exito: true,
          titular: true,
          cuenta: CuentaActivada(
            rifNit: 'J-31234567-8',
            nombreFiscal: 'TRANSPORTES DEL CENTRO C.A.',
            direccion: 'Av. Principal, Caracas',
            telefono: '02121234567',
            email: 'titular@empresa.com',
            titular: true,
          ),
        ),
      );
      String? ruta;
      await _montar(tester, repo, onRuta: (r) => ruta ??= r);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'activation_email'.tr()),
        'titular@empresa.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'activation_password'.tr()),
        'clave-del-proveedor',
      );
      await tester.ensureVisible(find.text('activation_submit'.tr()));
      await tester.tap(find.text('activation_submit'.tr()));
      await tester.pumpAndSettle();

      expect(ruta, '/company_setup');
    });
  });
}

/// Fábrica de repositorio que devuelve el resultado sin tocar la red.
ActivacionRepository _repoCon(ActivacionResultado resultado) =>
    _RepoDoble(resultado);

/// Implementa solo lo que la pantalla necesita; el resto lanza por si se usa.
class _RepoDoble implements ActivacionRepository {
  final ActivacionResultado resultado;

  _RepoDoble(this.resultado);

  @override
  Future<ActivacionResultado> activar({
    required String email,
    required String password,
  }) async {
    if (resultado.exito && resultado.cuenta != null) {
      await CuentaActivada.guardar(resultado.cuenta!);
      await AppConfig.setLicenciaVerificada(
        verificada: true,
        titular: resultado.titular,
      );
    }
    return resultado;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} no se usa en el test');
}

/// Utilidad de test para no arrastrar la cuenta entre casos.
abstract final class CuentaActivadaTestHelper {
  static Future<void> limpiar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cuenta.activada');
    await AppConfig.setLicenciaVerificada(verificada: false, titular: false);
  }
}

class _FakeAuthRepository implements IAuthRepository {
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
      _admin;

  @override
  Future<User> register({
    required String empresaNombre,
    required String empresaRif,
    required String usuarioNombre,
    required String email,
    required String password,
    String? licenciaKey,
  }) async =>
      _admin;

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
  Future<User?> getCachedUser() async => null;

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
  email: 'admin@empresa.com',
  rol: 'ADMIN',
  idEmpresa: 'emp-1',
);
