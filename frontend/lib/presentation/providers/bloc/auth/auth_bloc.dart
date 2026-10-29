import 'package:bloc/bloc.dart';
import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import '../../../../core/utils/mensaje_error.dart';
import '../../../../domain/entities/user.dart';
import '../../../../data/repositories/auth_repository.dart';
import '../../../../domain/repositories/i_auth_repository.dart';
import '../../../../domain/usecases/auth_usecases.dart';
import '../../../../core/security/device_info.dart';
part 'auth_event.dart';
part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final LoginUseCase _loginUseCase;
  final LogoutUseCase _logoutUseCase;
  final GetCachedUserUseCase _getCachedUserUseCase;
  final RestoreSessionUseCase _restoreSessionUseCase;
  final ForgotPasswordUseCase _forgotPasswordUseCase;
  final ResetPasswordUseCase _resetPasswordUseCase;
  final RefrescarEmpresaUseCase _refrescarEmpresaUseCase;
  final AuthRepository _authRepository;

  AuthBloc({
    required LoginUseCase loginUseCase,
    required LogoutUseCase logoutUseCase,
    required GetCachedUserUseCase getCachedUserUseCase,
    required RestoreSessionUseCase restoreSessionUseCase,
    required ForgotPasswordUseCase forgotPasswordUseCase,
    required ResetPasswordUseCase resetPasswordUseCase,
    required RefrescarEmpresaUseCase refrescarEmpresaUseCase,
    required AuthRepository authRepository,
  })  : _loginUseCase = loginUseCase,
        _logoutUseCase = logoutUseCase,
        _getCachedUserUseCase = getCachedUserUseCase,
        _restoreSessionUseCase = restoreSessionUseCase,
        _forgotPasswordUseCase = forgotPasswordUseCase,
        _resetPasswordUseCase = resetPasswordUseCase,
        _refrescarEmpresaUseCase = refrescarEmpresaUseCase,
        _authRepository = authRepository,
        super(AuthInitial()) {
    on<LoginEvent>(_onLogin);
    on<LogoutEvent>(_onLogout);
    on<CheckAuthStatusEvent>(_onCheckAuthStatus);
    on<ForgotPasswordEvent>(_onForgotPassword);
    on<ResetPasswordEvent>(_onResetPassword);
    on<RefreshCompanyEvent>(_onRefreshCompany);
    on<SetupAdminEvent>(_onSetupAdmin);
  }

  Future<void> _onLogin(LoginEvent event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final hwInfo = await DeviceInfo.getHardwareInfo();
      final user = await _loginUseCase.execute(
        email: event.email,
        password: event.password,
        hardwareId: event.hardwareId ?? hwInfo.hardwareId,
        deviceBrand: event.deviceBrand ?? hwInfo.brand,
        deviceModel: event.deviceModel ?? hwInfo.model,
        osVersion: event.osVersion ?? hwInfo.osVersion,
        macAddress: event.macAddress ?? hwInfo.macAddress,
      );
      emit(AuthAuthenticated(user));
    } catch (e) {
      // Si el 403 del login-central trae el equipo titular, mostramos un
      // mensaje accionable (nombre + hardware + cómo resolver); si no,
      // usamos el mensaje genérico del backend.
      final info = parsearErrorTitular(e);
      if (info.hardwareTitular != null) {
        final nombre = info.nombreEquipoTitular ?? info.hardwareTitular!;
        // La huella de ESTE equipo ayuda a soporte a reconciliar el titular
        // (incidente 2026-10-14): sin ella no se sabe qué envió la estación.
        final propio = info.hardwareRecibido == null
            ? ''
            : ' Huella de este equipo: ${info.hardwareRecibido}.';
        emit(AuthError(
          'Esta cuenta ADMIN está activada en el equipo titular "$nombre" '
          '(hardware ${info.hardwareTitular}). Para usarla desde este equipo, '
          'reasigne el titular desde el panel del servidor o contacte al '
          'distribuidor.$propio',
        ));
      } else if (esErrorEquipoSinAprobar(e)) {
        // RB-12: el equipo existe pero aún no fue aprobado por la cuenta.
        emit(AuthError(
          '${info.mensaje} Apruébelo desde el equipo titular en '
          '"Sesiones y Equipos".',
        ));
      } else {
        emit(AuthError(info.mensaje));
      }
    }
  }

  Future<void> _onLogout(LogoutEvent event, Emitter<AuthState> emit) async {
    await _logoutUseCase.execute();
    emit(AuthInitial());
  }

  Future<void> _onCheckAuthStatus(
      CheckAuthStatusEvent event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    final user = await _getCachedUserUseCase.execute();
    if (user == null) {
      emit(AuthInitial());
      return;
    }
    // Hay usuario cacheado: validar si la sesión sigue siendo válida.
    final resultado = await _restoreSessionUseCase.execute();
    if (resultado == SesionRestaurada.invalida) {
      // Token inválido (BD recién instalada/vaciada): se limpió la sesión y
      // el operador debe volver al login.
      emit(AuthInitial());
    } else {
      // online (ok) o sin red (offline-first).
      emit(AuthAuthenticated(user));
    }
  }

  Future<void> _onForgotPassword(
      ForgotPasswordEvent event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      await _forgotPasswordUseCase.execute(event.email);
      emit(AuthPasswordResetSent());
    } catch (e) {
      emit(AuthError(mensajeDeError(e)));
    }
  }

  Future<void> _onResetPassword(
      ResetPasswordEvent event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      await _resetPasswordUseCase.execute(event.token, event.newPassword);
      emit(AuthPasswordChanged());
    } catch (e) {
      emit(AuthError(mensajeDeError(e)));
    }
  }

  Future<void> _onSetupAdmin(
      SetupAdminEvent event, Emitter<AuthState> emit) async {
    emit(AuthSetupLoading());
    try {
      final ok = await _authRepository.setupCrearAdmin(event.data);
      if (!ok) {
        emit(const AuthSetupFailure('No se pudo crear la cuenta de administrador.'));
        return;
      }
      // Leer el usuario cacheado (guardado por el repositorio tras crear-admin)
      final user = await _getCachedUserUseCase.execute();
      if (user == null) {
        emit(const AuthSetupFailure('La cuenta se creó pero no se pudo leer el usuario.'));
        return;
      }
      emit(AuthSetupSuccess(user));
      // Transición directa al dashboard: emite AuthAuthenticated como el login normal.
      emit(AuthAuthenticated(user));
    } catch (e) {
      // Capturar cualquier excepción (DioException de conexión, error 409 de
      // duplicidad, etc.) y mostrar el mensaje exacto del servidor en la UI.
      final errorMsg = e is DioException
          ? _extraerMensajeDio(e)
          : e.toString();
      emit(AuthSetupFailure(errorMsg));
    }
  }

  /// Refresca la empresa del usuario en sesión sin pasar por `AuthLoading`.
  ///
  /// Si no hay sesión (`AuthInitial`) no hace nada: el refresco depende de un
  /// token válido. Si la lectura falla, el repositorio devuelve `null` y se
  /// conserva el estado actual (no es un error visible para el operador).
  Future<void> _onRefreshCompany(
      RefreshCompanyEvent event, Emitter<AuthState> emit) async {
    if (state is! AuthAuthenticated) return;
    try {
      final user = await _refrescarEmpresaUseCase.execute();
      if (user != null) emit(AuthAuthenticated(user));
    } catch (_) {
      // Best-effort: la sesión sigue válida con los datos que ya tenía. Borrar
      // al operador por no poder releer un logo sería peor que no refrescarlo.
    }
  }

  /// Extrae el mensaje legible de una DioException, mostrando el detalle del
  /// servidor cuando está disponible (p.ej. "Error de conexión rechazada").
  String _extraerMensajeDio(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['detail'] is String) {
      final detalle = (data['detail'] as String).trim();
      if (detalle.isNotEmpty) return detalle;
    }
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'Error de conexión con el servidor. Verifica que el WServer esté ejecutándose.';
      case DioExceptionType.unknown:
        if (e.response == null) return 'No se pudo conectar con el servidor.';
        break;
      default:
        break;
    }
    return mensajeDeError(e);
  }
}