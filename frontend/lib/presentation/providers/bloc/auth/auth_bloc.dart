import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../core/utils/mensaje_error.dart';
import '../../../../domain/entities/user.dart';
import '../../../../domain/repositories/i_auth_repository.dart';
import '../../../../domain/usecases/auth_usecases.dart';
import '../../../../core/security/device_info.dart';
part 'auth_event.dart';
part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final LoginUseCase _loginUseCase;
  final RegisterUseCase _registerUseCase;
  final LogoutUseCase _logoutUseCase;
  final GetCachedUserUseCase _getCachedUserUseCase;
  final RestoreSessionUseCase _restoreSessionUseCase;
  final ForgotPasswordUseCase _forgotPasswordUseCase;
  final ResetPasswordUseCase _resetPasswordUseCase;

  AuthBloc({
    required LoginUseCase loginUseCase,
    required RegisterUseCase registerUseCase,
    required LogoutUseCase logoutUseCase,
    required GetCachedUserUseCase getCachedUserUseCase,
    required RestoreSessionUseCase restoreSessionUseCase,
    required ForgotPasswordUseCase forgotPasswordUseCase,
    required ResetPasswordUseCase resetPasswordUseCase,
  })  : _loginUseCase = loginUseCase,
        _registerUseCase = registerUseCase,
        _logoutUseCase = logoutUseCase,
        _getCachedUserUseCase = getCachedUserUseCase,
        _restoreSessionUseCase = restoreSessionUseCase,
        _forgotPasswordUseCase = forgotPasswordUseCase,
        _resetPasswordUseCase = resetPasswordUseCase,
        super(AuthInitial()) {
    on<LoginEvent>(_onLogin);
    on<RegisterEvent>(_onRegister);
    on<LogoutEvent>(_onLogout);
    on<CheckAuthStatusEvent>(_onCheckAuthStatus);
    on<ForgotPasswordEvent>(_onForgotPassword);
    on<ResetPasswordEvent>(_onResetPassword);
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
      emit(AuthError(mensajeDeError(e)));
    }
  }

  Future<void> _onRegister(RegisterEvent event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      final user = await _registerUseCase.execute(
        empresaNombre: event.empresaNombre,
        empresaRif: event.empresaRif,
        usuarioNombre: event.usuarioNombre,
        email: event.email,
        password: event.password,
        licenciaKey: event.licenciaKey,
      );
      emit(AuthAuthenticated(user));
    } catch (e) {
      emit(AuthError(mensajeDeError(e)));
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
}
