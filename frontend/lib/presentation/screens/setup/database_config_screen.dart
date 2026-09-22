import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/services/wserver_manager.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../injection.dart' as di;
import 'setup_layout_wrapper.dart';

class DatabaseConfigScreen extends StatefulWidget {
  const DatabaseConfigScreen({super.key});

  @override
  State<DatabaseConfigScreen> createState() => _DatabaseConfigScreenState();
}

class _DatabaseConfigScreenState extends State<DatabaseConfigScreen> {
  final _formKey = GlobalKey<FormState>();

  final _hostCtrl = TextEditingController(text: 'localhost');
  final _portCtrl = TextEditingController(text: '5432');
  final _dbNameCtrl = TextEditingController(text: 'balansoft_ws_local');
  final _userCtrl = TextEditingController(text: 'balansoft');
  final _passCtrl = TextEditingController();
  final _apiPortCtrl = TextEditingController(text: '8000');

  bool _isConnecting = false;
  bool _obscurePass = true;
  String? _error;

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _dbNameCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _apiPortCtrl.dispose();
    super.dispose();
  }

  Future<void> _conectar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isConnecting = true;
      _error = null;
    });

    try {
      // Si el WServer ya está activo (p. ej. lo arrancó la verificación de
      // entorno con la config anterior), se detiene y reinicia para que
      // `ensureRunning` aplique las credenciales nuevas (los args --db-* solo
      // surten efecto al lanzar el proceso).
      WServerManager.reset();
      try {
        await WServerManager.detener();
      } catch (_) {}

      final success = await WServerManager.ensureRunning(
        dbHost: _hostCtrl.text.trim(),
        dbPort: _portCtrl.text.trim(),
        dbUser: _userCtrl.text.trim(),
        dbPass: _passCtrl.text,
        dbName: _dbNameCtrl.text.trim(),
        apiPort: _apiPortCtrl.text.trim(),
      );

      if (success) {
        await AppConfig.init();
        // Persistir la URL de la API local para que en el próximo arranque la
        // app recuerde la conexión (main.dart decide '/login' con esto).
        final apiPort = _apiPortCtrl.text.trim();
        final apiUrl = 'http://localhost:${apiPort.isEmpty ? '8000' : apiPort}';
        await AppConfig.setApiBaseUrl(apiUrl);
        di.sl<ApiClient>().setBaseUrl(apiUrl);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Conexión exitosa. Base de datos inicializada.'),
              backgroundColor: SwsColors.success,
            ),
          );
          Navigator.of(context).pushReplacementNamed('/login');
        }
      } else {
        setState(() {
          _error =
              'El servidor local no respondió a tiempo. Verifica los logs.';
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SetupLayoutWrapper(
      onBack: () => Navigator.of(context).pushReplacementNamed('/setup'),
      children: [
        // ─── Encabezado ───────────────────────────────────────────────
        const Row(
          children: [
            Icon(Icons.storage_outlined, size: 32, color: SwsColors.accentLight),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                'Conexión al Servidor Local',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: SwsColors.white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Ingresa las credenciales del motor PostgreSQL (rol SuperAdmin o propietario) para que el sistema pueda crear la estructura inicial de la base de datos.',
          style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 28),

        // ─── Formulario en Card translúcida ──────────────────────────
        Card(
          color: SwsColors.surfaceGlass,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: SwsColors.surfaceGlassBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Host y Puerto DB
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _hostCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration(
                            label: 'Host de PostgreSQL',
                            icon: Icons.computer_outlined,
                          ),
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'Requerido' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 1,
                        child: TextFormField(
                          controller: _portCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration(
                            label: 'Puerto DB',
                            icon: Icons.numbers_outlined,
                          ),
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'Requerido' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Base de datos y Puerto API
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _dbNameCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration(
                            label: 'Nombre de la BD',
                            icon: Icons.source_outlined,
                          ),
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'Requerido' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 1,
                        child: TextFormField(
                          controller: _apiPortCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration(
                            label: 'Puerto API',
                            icon: Icons.cloud_outlined,
                          ),
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'Requerido' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Usuario y Contraseña
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _userCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration(
                            label: 'Usuario PostgreSQL',
                            icon: Icons.person_outline,
                          ),
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'Requerido' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _passCtrl,
                          obscureText: _obscurePass,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration(
                            label: 'Contraseña PostgreSQL',
                            icon: Icons.lock_outline,
                          ).copyWith(
                            suffixIcon: IconButton(
                              onPressed: () => setState(
                                  () => _obscurePass = !_obscurePass),
                              icon: Icon(
                                _obscurePass
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: Colors.white60,
                              ),
                            ),
                          ),
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'Requerido' : null,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // ─── Mensaje de error ────────────────────────────────────────
        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: SwsColors.danger.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: SwsColors.danger.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline,
                    color: SwsColors.danger, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // ─── Botón "Verificar y Conectar" ────────────────────────────
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _isConnecting ? null : _conectar,
            style: FilledButton.styleFrom(
              backgroundColor: SwsColors.accent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.white.withValues(alpha: 0.08),
              disabledForegroundColor: Colors.white.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: _isConnecting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.cable),
            label: Text(
              _isConnecting
                  ? 'Verificando y Conectando...'
                  : 'Verificar y Conectar',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ─── Decoración compartida para todos los inputs ────────────────────
  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
  }) {
    return InputDecoration(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.06),
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white60),
      floatingLabelStyle: const TextStyle(color: SwsColors.accentLight),
      prefixIcon: Icon(icon, color: Colors.white60),
      enabledBorder: const UnderlineInputBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        borderSide: BorderSide(color: Colors.white30, width: 1.5),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        borderSide: BorderSide(color: SwsColors.accentLight, width: 2.0),
      ),
      errorBorder: const UnderlineInputBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        borderSide: BorderSide(color: SwsColors.danger, width: 1.5),
      ),
      focusedErrorBorder: const UnderlineInputBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        borderSide: BorderSide(color: SwsColors.danger, width: 2.0),
      ),
      border: const UnderlineInputBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
    );
  }
}