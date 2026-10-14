import 'dart:async';

import 'package:bloc/bloc.dart';

import '../../../../domain/entities/notification.dart';
import '../../../../data/repositories/notification_repository.dart';

/// Estado del centro de notificaciones (campana + bandeja).
class NotificationsState {
  /// Contadores del badge del *navbar*.
  final NotificationSummary resumen;

  /// Bandeja cargada (puede venir filtrada).
  final List<AppNotification> items;

  /// Carga de la bandeja en curso.
  final bool cargando;

  /// Operación puntual en curso (marcar leída / archivar / probar).
  final bool procesando;

  /// Filtro activo de la bandeja: `null` = todas.
  final String? filtro;

  final String? error;

  const NotificationsState({
    this.resumen = const NotificationSummary(),
    this.items = const [],
    this.cargando = false,
    this.procesando = false,
    this.filtro,
    this.error,
  });

  NotificationsState copyWith({
    NotificationSummary? resumen,
    List<AppNotification>? items,
    bool? cargando,
    bool? procesando,
    String? filtro,
    bool limpiarFiltro = false,
    String? error,
  }) {
    return NotificationsState(
      resumen: resumen ?? this.resumen,
      items: items ?? this.items,
      cargando: cargando ?? this.cargando,
      procesando: procesando ?? this.procesando,
      filtro: limpiarFiltro ? null : (filtro ?? this.filtro),
      error: error,
    );
  }

  /// Avisos no leídos presentes en la bandeja cargada.
  List<AppNotification> get noLeidas =>
      items.where((n) => n.estado == AppNotification.estadoNoLeida).toList();
}

/// Centro de notificaciones de la estación.
///
/// La bandeja y los avisos **los genera el WServer** (residente, aunque esta
/// app esté cerrada); el cubit solo los lee y refresca el contador. El
/// temporizador vive aquí y se cancela en [close] para no dejar timers vivos al
/// cerrar la sesión o en los tests.
class NotificationsCubit extends Cubit<NotificationsState> {
  final NotificationRepository _repo;
  final Duration intervalo;

  Timer? _timer;

  NotificationsCubit({
    required NotificationRepository repo,
    Duration? intervalo,
  })  : _repo = repo,
        intervalo = intervalo ?? const Duration(seconds: 60),
        super(const NotificationsState());

  /// Primer refresco del badge + sondeo periódico. Idempotente.
  Future<void> iniciar() async {
    await refrescarResumen();
    _timer?.cancel();
    _timer = Timer.periodic(intervalo, (_) => refrescarResumen());
  }

  /// Refresca solo el contador (barato: lo llama el sondeo).
  Future<void> refrescarResumen() async {
    try {
      final resumen = await _repo.resumen();
      emit(state.copyWith(resumen: resumen, error: null));
    } catch (_) {
      // Offline o backend caído: el badge conserva el último valor conocido.
    }
  }

  /// Carga la bandeja (opcionalmente filtrando por estado).
  Future<void> cargar({String? filtro, bool soloNoLeidas = false}) async {
    emit(state.copyWith(
      cargando: true,
      filtro: filtro,
      limpiarFiltro: filtro == null && !soloNoLeidas,
      error: null,
    ));
    try {
      final items = await _repo.listar(
        estado: filtro,
        soloNoLeidas: soloNoLeidas,
        limit: 100,
      );
      final resumen = await _repo.resumen();
      emit(state.copyWith(items: items, resumen: resumen, cargando: false));
    } catch (e) {
      emit(state.copyWith(cargando: false, error: 'No se pudo cargar: $e'));
    }
  }

  Future<void> marcarLeida(String id) async {
    emit(state.copyWith(procesando: true, error: null));
    try {
      final actualizada = await _repo.marcarLeida(id);
      _reemplazar(actualizada);
      emit(state.copyWith(procesando: false));
      await refrescarResumen();
    } catch (e) {
      emit(state.copyWith(procesando: false, error: 'No se pudo marcar: $e'));
    }
  }

  Future<void> archivar(String id) async {
    emit(state.copyWith(procesando: true, error: null));
    try {
      final actualizada = await _repo.archivar(id);
      _reemplazar(actualizada);
      emit(state.copyWith(procesando: false));
      await refrescarResumen();
    } catch (e) {
      emit(state.copyWith(procesando: false, error: 'No se pudo archivar: $e'));
    }
  }

  Future<void> marcarTodasLeidas() async {
    emit(state.copyWith(procesando: true, error: null));
    try {
      await _repo.marcarTodasLeidas();
      emit(state.copyWith(
        procesando: false,
        items: [
          for (final n in state.items)
            n.estado == AppNotification.estadoNoLeida
                ? _comoLeida(n)
                : n,
        ],
      ));
      await refrescarResumen();
    } catch (e) {
      emit(state.copyWith(procesando: false, error: 'No se pudo actualizar: $e'));
    }
  }

  /// Genera un aviso de prueba (ADMIN). Devuelve `true` si se creó.
  Future<bool> probar() async {
    emit(state.copyWith(procesando: true, error: null));
    try {
      await _repo.probar();
      emit(state.copyWith(procesando: false));
      await cargar(filtro: state.filtro);
      return true;
    } catch (e) {
      emit(state.copyWith(procesando: false, error: 'No se pudo probar: $e'));
      return false;
    }
  }

  void _reemplazar(AppNotification actualizada) {
    final items = [
      for (final n in state.items) n.id == actualizada.id ? actualizada : n,
    ];
    emit(state.copyWith(items: items));
  }

  AppNotification _comoLeida(AppNotification n) {
    return AppNotification(
      id: n.id,
      tipo: n.tipo,
      severidad: n.severidad,
      titulo: n.titulo,
      mensaje: n.mensaje,
      estado: AppNotification.estadoLeida,
      leida: true,
      origen: n.origen,
      acciones: n.acciones,
      idReferencia: n.idReferencia,
      idRecordatorio: n.idRecordatorio,
      programadaPara: n.programadaPara,
      createdAt: n.createdAt,
      leidaEn: n.leidaEn ?? DateTime.now(),
    );
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    _timer = null;
    return super.close();
  }
}
