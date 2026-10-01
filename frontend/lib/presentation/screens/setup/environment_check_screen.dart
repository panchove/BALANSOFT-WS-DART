import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/i18n/translations.dart';
import '../../../core/config/app_config.dart';
import '../../../core/services/wserver_manager.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/datasources/remote/api_client.dart';
import 'setup_layout_wrapper.dart';

/// Pantalla de verificación de entorno (primera ejecución, modo instalación).
///
/// Comprueba 4 cosas independientes:
///
/// 1. API local (WServer): binario arrancado y `/health` OK.
/// 2. PostgreSQL instalado: servicio/binario presente en el SO.
/// 3. Conexión a la BD local: el WServer puede conectar y el esquema existe.
/// 4. Drivers de balanza (HAL / pyserial).
///
/// El servidor central (cuenta/licencia) NO se verifica ni se muestra aquí:
/// su URL es fija y se resuelve en el login y en el repositorio de auth.
class EnvironmentCheckScreen extends StatefulWidget {
  const EnvironmentCheckScreen({super.key, this.setupMode = true});

  final bool setupMode;

  @override
  State<EnvironmentCheckScreen> createState() => _EnvironmentCheckScreenState();
}

enum _EstadoCheck { cargando, ok, error, info, opcional }

class _CheckItem {
  _CheckItem({
    required this.id,
    required this.titulo,
    required this.estado,
  });

  final String id;
  final String titulo;
  _EstadoCheck estado;
  final bool obligatorio = true;
  String detalle = '';
}

class _EnvironmentCheckScreenState extends State<EnvironmentCheckScreen> {
  final List<_CheckItem> _items = [
    _CheckItem(
      id: 'wserver',
      titulo: 'API local (WServer)',
      estado: _EstadoCheck.cargando,
    ),
    _CheckItem(
      id: 'postgres_instalado',
      titulo: 'PostgreSQL instalado',
      estado: _EstadoCheck.cargando,
    ),
    _CheckItem(
      id: 'postgres_conexion',
      titulo: 'Conexión a base de datos',
      estado: _EstadoCheck.cargando,
    ),
    _CheckItem(
      id: 'drivers',
      titulo: 'Drivers de balanza (HAL)',
      estado: _EstadoCheck.cargando,
    ),
  ];

  bool _verificando = false;

  String get _baseLocal =>
      (AppConfig.apiBaseUrl?.trim() ?? AppConfig.defaultApiBaseUrl)
          .replaceAll(RegExp(r'/$'), '');

  int get _erroresObligatorios => _items
      .where((i) => i.obligatorio && i.estado == _EstadoCheck.error)
      .length;

  /// ¿PostgreSQL está instalado y el resto del entorno obligatorio funciona?
  bool get _postgresInstaladoOk =>
      _items.firstWhere((i) => i.id == 'postgres_instalado').estado ==
      _EstadoCheck.ok;

  /// La BD aún no conecta pero el WServer, PostgreSQL y los drivers ya están
  /// OK: solo falta configurar las credenciales de la BD, y el sistema la crea
  /// automáticamente (bootstrap de `wserver.py`). Con eso se desbloquea el
  /// paso a "Configuración de la base de datos".
  bool get _dbPreparable {
    const ok = _EstadoCheck.ok;
    final ws = _items.firstWhere((i) => i.id == 'wserver');
    final pg = _items.firstWhere((i) => i.id == 'postgres_instalado');
    final bd = _items.firstWhere((i) => i.id == 'postgres_conexion');
    final drv = _items.firstWhere((i) => i.id == 'drivers');
    return ws.estado == ok &&
        pg.estado == ok &&
        drv.estado == ok &&
        bd.estado == _EstadoCheck.error;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _verificarTodo());
  }

  void _actualizar(String id, _EstadoCheck estado, String detalle) {
    final item = _items.firstWhere((i) => i.id == id);
    item.estado = estado;
    item.detalle = detalle;
  }

  Future<void> _verificarTodo() async {
    if (_verificando) return;
    setState(() {
      _verificando = true;
      for (final item in _items) {
        item.estado = _EstadoCheck.cargando;
        item.detalle = '';
      }
    });

    // Cada comprobación es independiente: un fallo puntual (binario ausente,
    // proceso sin permisos, WServer caído) no puede abortar el resto ni dejar
    // la pantalla en "verificando" para siempre.
    try {
      await _verificarWServer();
      await _verificarPostgresInstalado();
      await _verificarEntorno(); // conexión BD + drivers
    } catch (e) {
      if (mounted) {
        setState(() {
          for (final item in _items) {
            if (item.estado == _EstadoCheck.cargando) {
              item.estado = _EstadoCheck.error;
              item.detalle = 'No se pudo completar la verificación: $e';
            }
          }
        });
      }
    } finally {
      if (mounted) setState(() => _verificando = false);
    }
  }

  // ─── 1. API local (WServer) ────────────────────────────────────────────
  Future<void> _verificarWServer() async {
    if (widget.setupMode) {
      // Solo en instalación se permite arrancar el backend local.
      final ok = await WServerManager.ensureRunning();
      if (!mounted) return;
      setState(() {
        _actualizar(
          'wserver',
          ok ? _EstadoCheck.ok : _EstadoCheck.error,
          ok
              ? 'Respondiendo en $_baseLocal'
              : 'No se detecta el WServer local en $_baseLocal. '
                  'Verifica que el binario WServer esté junto a la app o '
                  'definido en WSERVER_PATH.',
        );
      });
      return;
    }

    // Verificación de integridad desde Ajustes: es un DIAGNÓSTICO de solo
    // lectura. Arrancar procesos, pedir privilegios (pkexec) o reiniciar el
    // servicio desde aquí congelaba la sesión del operador.
    final ok = await WServerManager.isOnline();
    if (!mounted) return;
    setState(() {
      _actualizar(
        'wserver',
        ok ? _EstadoCheck.ok : _EstadoCheck.error,
        ok
            ? 'Respondiendo en $_baseLocal'
            : 'La API local no responde en $_baseLocal. Revisa que el WServer '
                'esté ejecutándose y que la URL de Ajustes → Conexiones sea '
                'correcta.',
      );
    });
  }

  // ─── 2. PostgreSQL instalado en el SO ──────────────────────────────────
  Future<void> _verificarPostgresInstalado() async {
    if (!Platform.isLinux && !Platform.isWindows) {
      if (!mounted) return;
      setState(() {
        _actualizar('postgres_instalado', _EstadoCheck.info,
            'Verificación no soportada en esta plataforma.');
      });
      return;
    }

    bool instalado = false;
    String detalle = '';

    if (Platform.isLinux) {
      // 1) systemctl is-active postgresql
      try {
        final r = await Process.run('systemctl', ['is-active', 'postgresql']);
        if (r.stdout.toString().trim() == 'active') {
          instalado = true;
          detalle = 'Servicio systemd activo (systemctl is-active postgresql).';
        }
      } catch (_) {}

      // 2) Fallback: ¿existe el binario psql?
      if (!instalado) {
        try {
          final r = await Process.run('which', ['psql']);
          if (r.exitCode == 0) {
            instalado = true;
            detalle =
                'Binario psql encontrado en ${r.stdout.toString().trim()} '
                '(servicio systemd no activo, pero PostgreSQL está instalado).';
          }
        } catch (_) {}
      }

      if (!instalado) {
        detalle = 'PostgreSQL no está instalado. Instálalo con: '
            'sudo apt install postgresql postgresql-contrib';
      }
    } else if (Platform.isWindows) {
      try {
        final r = await Process.run('sc', ['query', 'postgresql-x64-14']);
        instalado = r.exitCode == 0;
        detalle = instalado
            ? 'Servicio postgresql-x64-14 detectado.'
            : 'No se detectó el servicio de PostgreSQL.';
      } catch (_) {
        detalle = 'No se pudo consultar el servicio de PostgreSQL.';
      }
    }

    if (!mounted) return;
    setState(() {
      _actualizar(
        'postgres_instalado',
        instalado ? _EstadoCheck.ok : _EstadoCheck.error,
        detalle,
      );
    });
  }

  // ─── 3. Conexión a la BD + 5. Drivers (vienen del mismo endpoint) ──────
  Future<void> _verificarEntorno() async {
    final client = ApiClient(baseUrl: _baseLocal);
    final env = await client.environment(baseUrl: _baseLocal);

    if (env == null) {
      if (!mounted) return;
      setState(() {
        _actualizar('postgres_conexion', _EstadoCheck.error,
            'La API local no respondió al diagnóstico (/api/v1/environment).');
        _actualizar('drivers', _EstadoCheck.error,
            'No se pudo consultar el hardware de la estación.');
      });
      return;
    }

    debugPrint(
        '🔍 [DEBUG] env["postgres"].runtimeType = ${env['postgres'].runtimeType}');
    debugPrint(
        '🔍 [DEBUG] env["postgres"] is Map = ${env['postgres'] is Map}');
    debugPrint(
        '🔍 [DEBUG] env["hardware"] is Map = ${env['hardware'] is Map}');

    // --- Conexión a la BD ---
    final postgresRaw = env['postgres'];
    final postgres = postgresRaw is Map
        ? Map<String, dynamic>.from(postgresRaw)
        : <String, dynamic>{};
    final conectado = postgres['conectado'] == true;
    final esquemaListo = postgres['esquema_listo'] == true;
    final nTablas = postgres['n_tablas'];
    final bd = postgres['bd'] ?? '';
    final sufijoBd = bd.isEmpty ? '' : ' «$bd»';


    if (!mounted) return;
    setState(() {
      if (conectado && esquemaListo) {
        _actualizar('postgres_conexion', _EstadoCheck.ok,
            'Conectado a «$bd» ($nTablas tablas).');
      } else if (conectado && !esquemaListo) {
        _actualizar('postgres_conexion', _EstadoCheck.error,
            'Conectado pero esquema vacío$sufijoBd. '
            'Ejecuta el bootstrap de la base de datos.');
      } else {
        _actualizar('postgres_conexion', _EstadoCheck.error,
            'La BD «$bd» no está creada o las credenciales no son válidas. '
            'Configura las credenciales en el siguiente paso y el sistema la '
            'crea con su esquema automáticamente.');
      }
    });

    // --- Drivers ---
    final hardwareRaw = env['hardware'];
    final hardware = hardwareRaw is Map
        ? Map<String, dynamic>.from(hardwareRaw)
        : <String, dynamic>{};
    final pyserial = hardware['pyserial'] == true;
    final nBalanza = hardware['balanzas_configuradas'];
    final puertos = hardware['puertos_serial'];
    final puertosTexto = puertos is List && puertos.isNotEmpty
        ? puertos.take(5).join(', ')
        : 'ninguno detectado';

    if (!mounted) return;
    setState(() {
      _actualizar(
        'drivers',
        pyserial ? _EstadoCheck.ok : _EstadoCheck.error,
        pyserial
            ? 'HAL disponible (pyserial). Puertos: $puertosTexto. '
                'Balanzas configuradas: $nBalanza.'
            : 'Driver de balanza (pyserial) no disponible.',
      );
    });
  }

  void _continuar() {
    if (widget.setupMode) {
      Navigator.of(context).pushReplacementNamed('/db_config');
    } else {
      Navigator.of(context).pop();
    }
  }

  /// Va directo a la configuración de credenciales, desde donde el WServer
  /// crea la base de datos y su esquema automáticamente.
  void _irAConfigurarBd() {
    Navigator.of(context).pushReplacementNamed('/db_config');
  }

  void _descargarDependencias() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SwsColors.darkCard,
        title: Text('install_requirements'.tr(),
            style: const TextStyle(color: SwsColors.white)),
content: Text(
          'Para que esta máquina funcione como Servidor Principal, debes instalar '
          'PostgreSQL (versión 14 o superior).\n\n'
          'En Linux (Debian/Ubuntu):\n'
          '  sudo apt install postgresql postgresql-contrib\n\n'
          'En Windows: descarga el instalador oficial.\n\n'
          'Luego vuelve a ejecutar la verificación.',
          style: TextStyle(color: SwsColors.white.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('close'.tr()),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SetupLayoutWrapper(
      onBack: () {
        if (widget.setupMode) {
          Navigator.of(context).pushReplacementNamed('/mode_selection');
        } else {
          Navigator.of(context).pop();
        }
      },
      children: [
        _bannerIntro(context),
        const SizedBox(height: 16),
        for (final item in _items) ...[
          _checkTile(context, item),
          const SizedBox(height: 10),
        ],
        if (!_verificando && _erroresObligatorios == 0) ...[
          const SizedBox(height: 8),
          Card(
            color: SwsColors.success.withValues(alpha: 0.12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: SwsColors.success.withValues(alpha: 0.35),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline,
                      color: SwsColors.success, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'env_ready_db'.tr(),
                      style: const TextStyle(fontSize: 13, color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ] else if (!_verificando && widget.setupMode && _dbPreparable) ...[
          const SizedBox(height: 8),
          Card(
            color: SwsColors.warning.withValues(alpha: 0.10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: SwsColors.warning.withValues(alpha: 0.4),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.flag_outlined,
                          color: SwsColors.warning, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'ready_to_install_desc'.tr(),
                          style: const TextStyle(
                              fontSize: 13, color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonalIcon(
                      onPressed: _irAConfigurarBd,
                      icon: const Icon(Icons.login_outlined, size: 18),
                      label: Text('enter_credentials'.tr()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ] else if (!_verificando && _erroresObligatorios > 0) ...[
          const SizedBox(height: 8),
          Card(
            color: SwsColors.danger.withValues(alpha: 0.12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: SwsColors.danger.withValues(alpha: 0.35),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.report_problem_outlined,
                          color: SwsColors.danger, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _postgresInstaladoOk
                              ? 'La base de datos local no está lista.'
                                  ' Configura las credenciales y el sistema la '
                                  'crea con su esquema automáticamente.'
                              : 'Faltan componentes en el sistema. Instala '
                                  'lo necesario para continuar.',
                          style: const TextStyle(
                              fontSize: 13, color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _postgresInstaladoOk && widget.setupMode
                        ? FilledButton.tonalIcon(
                            onPressed: _irAConfigurarBd,
                            icon: const Icon(Icons.storage_outlined, size: 18),
                            label: Text('configure_db'.tr()),
                          )
                        : FilledButton.tonalIcon(
                            onPressed: _descargarDependencias,
                            icon: const Icon(Icons.build_outlined, size: 18),
                            label: Text('view_installers'.tr()),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _verificando ? null : _verificarTodo,
                icon: _verificando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text('verify_again'.tr()),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                key: const Key('entorno_continuar_btn'),
                onPressed: _verificando ||
                        (_erroresObligatorios > 0 && !_dbPreparable)
                    ? null
                    : _continuar,
                icon: const Icon(Icons.arrow_forward),
                label: Text('continue'.tr()),
                style: FilledButton.styleFrom(
                  backgroundColor: SwsColors.accent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      Colors.white.withValues(alpha: 0.08),
                  disabledForegroundColor:
                      Colors.white.withValues(alpha: 0.3),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _bannerIntro(BuildContext context) {
    return Card(
      color: SwsColors.surfaceGlass,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: SwsColors.surfaceGlassBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.verified_outlined, color: SwsColors.accentLight),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.setupMode
                        ? 'Instalación de Balansoft-WS'
                        : 'Verificación de integridad del sistema',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: SwsColors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'env_check_intro'.tr(),
              style: const TextStyle(fontSize: 13, color: Colors.white60),
            ),
            const SizedBox(height: 10),
            Text(
              'API local: $_baseLocal',
              style: const TextStyle(fontSize: 12, color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkTile(BuildContext context, _CheckItem item) {
    final (IconData icono, Color color) = switch (item.estado) {
      _EstadoCheck.cargando => (Icons.hourglass_top, Colors.white54),
      _EstadoCheck.ok => (Icons.check_circle, SwsColors.success),
      _EstadoCheck.error => (Icons.cancel, SwsColors.danger),
      _EstadoCheck.info => (Icons.info_outline, SwsColors.info),
      _EstadoCheck.opcional => (Icons.help_outline, SwsColors.warning),
    };

    return Card(
      margin: EdgeInsets.zero,
      color: SwsColors.surfaceGlass,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: SwsColors.surfaceGlassBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            item.estado == _EstadoCheck.cargando
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white54,
                    ),
                  )
                : Icon(icono, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.titulo,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: SwsColors.white,
                          ),
                        ),
                      ),
                      if (!item.obligatorio)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'optional'.tr(),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (item.detalle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.detalle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}