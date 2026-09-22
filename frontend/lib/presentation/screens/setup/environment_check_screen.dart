import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/services/wserver_manager.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/datasources/remote/api_client.dart';

/// Pantalla de verificación de entorno que se muestra en la PRIMERA ejecución
/// (modo instalación). Comprueba, en forma de checklist:
///
/// 1. API local (WServer): binario localizado, arrancado y con `/health` OK.
/// 2. Base de datos PostgreSQL local: alcanzable y con esquema creado.
/// 3. Drivers de balanza (HAL / pyserial) y balanzas configuradas.
/// 4. Conexión con el servidor central (cuenta y licencia).
///
/// Al terminar con todo OK permite continuar a "Conexiones" (modo instalación),
/// donde se guarda la URL de la API local y se accede al login.
class EnvironmentCheckScreen extends StatefulWidget {
  const EnvironmentCheckScreen({super.key, this.setupMode = true});

  /// true = primera ejecución (se llega al pulsar "Reintentar"/seguir y se
  /// navega a Conexiones). false = consulta manual desde Ajustes.
  final bool setupMode;

  @override
  State<EnvironmentCheckScreen> createState() => _EnvironmentCheckScreenState();
}

enum _EstadoCheck { cargando, ok, error, info }

class _CheckItem {
  _CheckItem({
    required this.id,
    required this.titulo,
    required this.estado,
  });

  final String id;
  final String titulo;
  _EstadoCheck estado;
  String detalle = '';
}

class _EnvironmentCheckScreenState extends State<EnvironmentCheckScreen> {
  final List<_CheckItem> _items = [
    _CheckItem(id: 'wserver', titulo: 'API local (WServer)', estado: _EstadoCheck.cargando),
    _CheckItem(
      id: 'postgres',
      titulo: 'Base de datos local (PostgreSQL)',
      estado: _EstadoCheck.cargando,
    ),
    _CheckItem(
      id: 'drivers',
      titulo: 'Drivers de balanza (HAL)',
      estado: _EstadoCheck.cargando,
    ),
    _CheckItem(
      id: 'servidor',
      titulo: 'Servidor central (cuenta y licencia)',
      estado: _EstadoCheck.cargando,
    ),
  ];

  bool _verificando = false;

  String get _baseLocal =>
      (AppConfig.apiBaseUrl?.trim() ?? AppConfig.defaultApiBaseUrl)
          .replaceAll(RegExp(r'/$'), '');

  int get _errores =>
      _items.where((i) => i.estado == _EstadoCheck.error).length;

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

    await _verificarWServer();
    await _verificarEntorno();
    await _verificarServidor();

    if (!mounted) return;
    setState(() => _verificando = false);
  }

  Future<void> _verificarWServer() async {
    // ensureRunning arranca el binario si hace falta y espera a /health.
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
  }

  Future<Map<String, dynamic>?> _verificarEntorno() async {
    final client = ApiClient(baseUrl: _baseLocal);
    final env = await client.environment(baseUrl: _baseLocal);

    if (env == null) {
      if (!mounted) return null;
      setState(() {
        _actualizar(
          'postgres',
          _EstadoCheck.error,
          'La API local no respondió al diagnóstico de entorno '
              '(/api/v1/environment).',
        );
        _actualizar(
          'drivers',
          _EstadoCheck.error,
          'No se pudo consultar el hardware de la estación.',
        );
      });
      return null;
    }

    // --- PostgreSQL ---
    final postgres = env['postgres'] is Map
        ? Map<String, dynamic>.from(env['postgres'] as Map)
        : <String, dynamic>{};
    final conectado = postgres['conectado'] == true;
    final esquemaListo = postgres['esquema_listo'] == true;
    final nTablas = postgres['n_tablas'];
    final bd = postgres['bd'] ?? '';
    if (!mounted) return env;
    setState(() {
      _actualizar(
        'postgres',
        conectado && esquemaListo
            ? _EstadoCheck.ok
            : _EstadoCheck.error,
        conectado
            ? (esquemaListo
                ? 'Conectado a la BD «$bd» con $nTablas tablas del esquema público.'
                : 'PostgreSQL responde pero el esquema está vacío '
                    '(0 tablas): ejecuta el WServer/bootstrap de BD.')
            : 'No se pudo conectar a PostgreSQL local. Revisa que el '
                'servicio esté iniciado y las credenciales de .env.',
      );
    });

    // --- Drivers / hardware ---
    final hardware = env['hardware'] is Map
        ? Map<String, dynamic>.from(env['hardware'] as Map)
        : <String, dynamic>{};
    final pyserial = hardware['pyserial'] == true;
    final nBalanza = hardware['balanzas_configuradas'];
    final puertos = hardware['puertos_serial'];
    final puertosTexto = puertos is List && puertos.isNotEmpty
        ? puertos.take(5).join(', ')
        : 'ninguno detectado';
    if (!mounted) return env;
    setState(() {
      _actualizar(
        'drivers',
        pyserial ? _EstadoCheck.ok : _EstadoCheck.error,
        pyserial
            ? 'HAL de balanza disponible (pyserial). Puertos serie: '
                '$puertosTexto. Balanzas configuradas: $nBalanza.'
            : 'Driver de balanza (pyserial) no disponible en esta estación.',
      );
    });

    return env;
  }

  Future<void> _verificarServidor() async {
    final ok = await ApiClient(baseUrl: _baseLocal)
        .serverHealth(serverUrl: AppConfig.serverApiUrl);
    if (!mounted) return;
    setState(() {
      _actualizar(
        'servidor',
        ok ? _EstadoCheck.ok : _EstadoCheck.error,
        ok
            ? 'Servidor central accesible en ${AppConfig.serverApiUrl}.'
            : 'No se pudo conectar al servidor central '
                '(${AppConfig.serverApiUrl}). Verifica la URL o que el '
                'servicio central esté iniciado.',
      );
    });
  }

  void _continuar() {
    if (widget.setupMode) {
      Navigator.of(context).pushReplacementNamed('/connections');
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verificación de entorno'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _bannerIntro(context),
          const SizedBox(height: 16),
          for (final item in _items) ...[
            _checkTile(context, item),
            const SizedBox(height: 10),
          ],
          if (!_verificando && _errores == 0) ...[
            const SizedBox(height: 8),
            const Card(
              color: SwsColors.blue100,
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline,
                        color: SwsColors.success, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Entorno listo. Continúa para indicar la URL de la API '
                        'local y acceder al sistema.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else if (!_verificando && _errores > 0) ...[
            const SizedBox(height: 8),
            const Card(
              color: SwsColors.light,
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.report_problem_outlined,
                        color: SwsColors.danger, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Hay comprobaciones fallidas. Corrige los puntos '
                        'marcados y vuelve a intentar.',
                        style: TextStyle(fontSize: 13),
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
                  label: const Text('Verificar de nuevo'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      _verificando || _errores > 0 ? null : _continuar,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Continuar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bannerIntro(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.verified_outlined, color: SwsColors.accent),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Instalación de Balansoft-WS',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Antes de usar la estación verificamos que el entorno esté listo: '
              'API local (WServer), base de datos PostgreSQL, drivers de la '
              'balanza y conexión con el servidor central.',
              style: TextStyle(fontSize: 13, color: SwsColors.gray500),
            ),
            const SizedBox(height: 10),
            Text(
              'API local: $_baseLocal · '
              'Servidor central: ${AppConfig.serverApiUrl}',
              style: const TextStyle(fontSize: 12, color: SwsColors.gray500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkTile(BuildContext context, _CheckItem item) {
    final (IconData icono, Color color) = switch (item.estado) {
      _EstadoCheck.cargando => (
          Icons.hourglass_top,
          SwsColors.gray500,
        ),
      _EstadoCheck.ok => (Icons.check_circle, SwsColors.success),
      _EstadoCheck.error => (Icons.cancel, SwsColors.danger),
      _EstadoCheck.info => (Icons.info_outline, SwsColors.info),
    };

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            item.estado == _EstadoCheck.cargando
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(icono, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.titulo,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  if (item.detalle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.detalle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: SwsColors.gray500,
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