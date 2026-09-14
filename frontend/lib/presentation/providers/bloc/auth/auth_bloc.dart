import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../../domain/entities/user.dart';
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
      emit(AuthError(e.toString()));
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
      emit(AuthError(e.toString()));
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
    if (user != null) {
      await _restoreSessionUseCase.execute();
      emit(AuthAuthenticated(user));
    } else {
      emit(AuthInitial());
    }
  }

  Future<void> _onForgotPassword(
      ForgotPasswordEvent event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      await _forgotPasswordUseCase.execute(event.email);
      emit(AuthPasswordResetSent());
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  Future<void> _onResetPassword(
      ResetPasswordEvent event, Emitter<AuthState> emit) async {
    emit(AuthLoading());
    try {
      await _resetPasswordUseCase.execute(event.token, event.newPassword);
      emit(AuthPasswordChanged());
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }
}
