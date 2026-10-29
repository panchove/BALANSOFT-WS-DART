import 'dart:async';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/security/device_info.dart';
import '../../../core/widgets/brand_text.dart';
import '../../../data/datasources/remote/api_client.dart';
import '../../../injection.dart' as di;
import '../../providers/bloc/auth/auth_bloc.dart';

/// Pantalla de configuración inicial de estación (100% local).
///
/// Flujo:
/// 1. Valida la licencia contra el LM (`POST /api/v1/setup/validar-licencia`)
///    para obtener email y razón social del cliente (bloqueados en el formulario).
/// 2. Muestra el formulario de empresa con los datos del cliente precargados:
///    - Email: solo lectura (del LM, será el usuario de login).
///    - Razón Social: solo lectura (del LM, `client_name` → `nombre_comercial`).
///    - RIF/NIT: editable y obligatorio (el LM no lo provee por API).
///    - Dirección y Teléfono: editables y opcionales.
/// 3. Pide contraseña y confirmación para el primer usuario ADMIN.
/// 4. Llama a `POST /api/v1/setup/crear-admin` y, al éxito, emite
///    `AuthAuthenticated` para entrar directo al Dashboard.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _rifNitCtrl = TextEditingController(); // Editable, obligatorio
  final _direccionCtrl = TextEditingController(); // Editable, opcional
  final _telefonoCtrl = TextEditingController(); // Editable, opcional
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _licenseKeyCtrl = TextEditingController();

  // Datos del cliente obtenidos del LM (bloqueados en el formulario).
  String? _clientEmail;
  String? _clientName; // Razón Social del LM

  String? _storedLicenseKey;

  bool _cargando = true; // validando licencia al abrir
  bool _enviando = false; // creando cuenta
  String? _error;
  int _paso = 1; // 1 = licencia, 2 = empresa, 3 = credenciales

  @override
  void initState() {
    super.initState();
    _validarLicenciaInicial();
  }

  @override
  void dispose() {
    _rifNitCtrl.dispose();
    _direccionCtrl.dispose();
    _telefonoCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _licenseKeyCtrl.dispose();
    super.dispose();
  }

  /// Paso 1: valida la licencia contra el LM al abrir la pantalla.
  Future<void> _validarLicenciaInicial() async {
    final storedKey = await _leerLicenciaKey();
    _storedLicenseKey = storedKey;
    if (storedKey != null && storedKey.trim().isNotEmpty) {
      _licenseKeyCtrl.text = storedKey.trim();
      await _validarLicencia(storedKey.trim());
    } else {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<String?> _leerLicenciaKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('licencia_key');
    } catch (_) {
      return null;
    }
  }

  Future<void> _validarLicencia(String licenseKey) async {
    if (!mounted) return;
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final api = di.sl<ApiClient>();
      final hwId = await _obtenerHardwareId();
      final response = await api.setupValidarLicencia({
        'license_key': licenseKey,
        'hardware_id': hwId,
      });

      if (response.statusCode == 200 && mounted) {
        final data = response.data as Map<String, dynamic>;
        setState(() {
          _clientEmail = data['client_email'] as String?;
          _clientName = data['client_name'] as String?;
          _paso = 2;
          _cargando = false;
        });
      } else if (mounted) {
        setState(() {
          _cargando = false;
          _error = response.data?['detail'] ?? 'Licencia inválida o expirada.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = _mensajeDeError(e);
        });
      }
    }
  }

  Future<String?> _obtenerHardwareId() async {
    try {
      final info = await DeviceInfo.getHardwareInfo();
      return info.hardwareId;
    } catch (_) {
      return null;
    }
  }

  /// Paso 3: crea la cuenta de administrador y entra al sistema.
  Future<void> _crearCuenta() async {
    if (!_formKey.currentState!.validate()) return;

    if (!mounted) return;
    setState(() {
      _enviando = true;
      _error = null;
    });

    try {
      final licenseKey = _licenseKeyCtrl.text.trim().isNotEmpty
          ? _licenseKeyCtrl.text.trim()
          : (_storedLicenseKey ?? '');

      context.read<AuthBloc>().add(SetupAdminEvent(data: {
        'license_key': licenseKey,
        'password': _passwordCtrl.text.trim(),
        'nombre_comercial': (_clientName ?? '').trim(), // Razón Social del LM
        'rif_nit': _rifNitCtrl.text.trim(), // RIF/NIT escrito por el usuario
        'direccion': _direccionCtrl.text.trim().isNotEmpty
            ? _direccionCtrl.text.trim()
            : null,
        'telefono': _telefonoCtrl.text.trim().isNotEmpty
            ? _telefonoCtrl.text.trim()
            : null,
        'logo_url': null,
      }));
      if (!mounted) return;
    } catch (e) {
      if (mounted) {
        setState(() => _enviando = false);
        final msg = _mensajeDeError(e);
        _error = msg;
        debugPrint('ERROR SETUP: $e');
        _mostrarSnackBarError(msg);
      }
    }
  }

  void _mostrarSnackBarError(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  /// Valida campos básicos antes de pasar al paso 3 (credenciales).
  void _irACredenciales() {
    if ((_clientName ?? '').trim().isEmpty) {
      setState(() => _error = 'La razón social es obligatoria.');
      return;
    }
    if (_rifNitCtrl.text.trim().isEmpty) {
      setState(() => _error = 'El RIF/NIT es obligatorio.');
      return;
    }
    setState(() {
      _paso = 3;
      _error = null;
    });
  }

  String _mensajeDeError(dynamic e) {
    if (e is DioException) {
      return e.response?.data?['detail'] ?? e.message ?? 'Error del servidor.';
    }
    return e.toString();
  }

  Widget _campoSoloLectura(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
                color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: TextEditingController(text: valor),
            enabled: false,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.5),
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _campoEditable({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool obligatorio = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label${obligatorio ? ' *' : ''}',
            style: const TextStyle(
                color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white54),
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.5),
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _campoPassword({
    required TextEditingController controller,
    required String label,
    required String hint,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
                color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            obscureText: true,
            style: const TextStyle(color: Colors.white),
            validator: validator,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white54),
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.5),
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mensajeErrorWidget() {
    if (_error == null) return const SizedBox.shrink();
    return Column(
      children: [
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.redAccent),
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline,
                  color: Colors.redAccent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _error!,
                  style: const TextStyle(
                      color: Colors.redAccent, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (!mounted) return;
        if (state is AuthSetupLoading) {
          setState(() => _enviando = true);
        } else if (state is AuthSetupSuccess) {
          setState(() => _enviando = false);
          // Navegar al dashboard tras crear la cuenta exitosamente
          Navigator.of(context).pushReplacementNamed('/dashboard');
        } else if (state is AuthAuthenticated) {
          setState(() => _enviando = false);
          Navigator.of(context).pushReplacementNamed('/dashboard');
        } else if (state is AuthSetupFailure) {
          setState(() => _enviando = false);
          _mostrarSnackBarError(state.message);
        } else if (state is AuthError) {
          setState(() => _enviando = false);
          _mostrarSnackBarError(state.message);
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Stack(
          children: [
            // Capa 1: Imagen de fondo (misma que el login)
            Image.asset(
              'assets/images/BLSWS-LOGO-LOGIN.jpeg',
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
            // Capa 2: Efecto de cristal esmerilado (blur)
            BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                color: Colors.black.withValues(alpha: 0.3),
                width: double.infinity,
                height: double.infinity,
              ),
            ),
            // Capa 3: Scaffold con contenido semi-transparente
            Scaffold(
              backgroundColor: Colors.transparent,
              body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const BrandText(size: 48, withTagline: true),
                      const SizedBox(height: 24),
                      const Text(
                        'Configuración Inicial',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Crea la cuenta de administrador de esta estación.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Paso 1: validación de licencia
                      if (_paso == 1) ...[
                        if (_cargando) ...[
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            'Validando licencia con el License Manager...',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ] else ...[
                          _mensajeErrorWidget(),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _licenseKeyCtrl,
                            decoration: const InputDecoration(
                              labelText: 'License Key',
                              hintText: 'BWS-XXXX-XXXX-XXXX-XXXX',
                              prefixIcon: Icon(Icons.vpn_key_outlined,
                                              color: Colors.white70),
                              border: OutlineInputBorder(),
                            ),
                            style: const TextStyle(color: Colors.white),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _cargando
                                  ? null
                                  : () => _validarLicencia(
                                        _licenseKeyCtrl.text.trim(),
                                      ),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Validar licencia'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _cargando ? null : _validarLicenciaInicial,
                            child: const Text('Usar clave guardada'),
                          ),
                        ],
                      ]

                      // Paso 2: datos de la empresa
                      else if (_paso == 2) ...[
                        _mensajeErrorWidget(),
                        const SizedBox(height: 16),
                        Card(
                          color: Colors.black.withValues(alpha: 0.6),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Datos del cliente (License Manager)',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 12),
                                ),
                                const SizedBox(height: 8),
                                // Email: solo lectura (del LM)
                                _campoSoloLectura(
                                    'Email', _clientEmail ?? '(sin asignar)'),
                                // Razón Social: solo lectura (del LM)
                                _campoSoloLectura(
                                    'Razón Social', _clientName ?? '(sin asignar)'),
                                // RIF/NIT: editable y obligatorio
                                _campoEditable(
                                  controller: _rifNitCtrl,
                                  label: 'RIF/NIT',
                                  hint: 'Ej. J-12345678-0',
                                  obligatorio: true,
                                ),
                                const SizedBox(height: 16),
                                const Divider(color: Colors.white24),
                                const SizedBox(height: 8),
                                const Text(
                                  'Datos de la empresa',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 12),
                                ),
                                const SizedBox(height: 8),
                                _campoEditable(
                                  controller: _direccionCtrl,
                                  label: 'Dirección',
                                  hint: 'Av. Principal, Edificio X',
                                ),
                                _campoEditable(
                                  controller: _telefonoCtrl,
                                  label: 'Teléfono',
                                  hint: '+58 212 123 4567',
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _enviando ? null : _irACredenciales,
                            icon: const Icon(Icons.arrow_forward),
                            label: const Text('Siguiente'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _enviando ? null : () => setState(() => _paso = 1),
                          child: const Text('Cambiar licencia'),
                        ),
                      ]

                      // Paso 3: credenciales
                      else if (_paso == 3) ...[
                        Card(
                          color: Colors.black.withValues(alpha: 0.6),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Credenciales de administrador',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 12),
                                ),
                                const SizedBox(height: 8),
                                _campoPassword(
                                  controller: _passwordCtrl,
                                  label: 'Contraseña',
                                  hint: 'Mínimo 8 caracteres',
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'La contraseña es obligatoria';
                                    }
                                    if (value.length < 8) {
                                      return 'Mínimo 8 caracteres';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 12),
                                _campoPassword(
                                  controller: _confirmPasswordCtrl,
                                  label: 'Confirmar contraseña',
                                  hint: 'Repite la contraseña',
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Confirma la contraseña';
                                    }
                                    if (value != _passwordCtrl.text) {
                                      return 'Las contraseñas no coinciden';
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _enviando ? null : _crearCuenta,
                            icon: const Icon(Icons.login),
                            label: const Text('Crear Cuenta e Iniciar Sesión'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _enviando ? null : () => setState(() => _paso = 2),
                          child: const Text('Volver a empresa'),
                        ),
                      ],

                      _mensajeErrorWidget(),
                    ],
                  ), // cierre de Column
                ), // cierre de Form
              ),   // cierre de SingleChildScrollView
            ),     // cierre de ConstrainedBox
          ),       // cierre de Center
        ),         // cierre de SafeArea
      ),           // cierre de Scaffold
    ],             // cierre de children del Stack
  ),               // cierre de Stack
  ),               // cierre de AnnotatedRegion
);                 // cierre de BlocListener
  }
}
