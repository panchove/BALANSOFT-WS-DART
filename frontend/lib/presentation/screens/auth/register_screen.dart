import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/brand_text.dart';
import '../../providers/bloc/auth/auth_bloc.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _empresaNombreCtrl = TextEditingController();
  final _empresaRifCtrl = TextEditingController();
  final _usuarioNombreCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _licenciaCtrl = TextEditingController();
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _empresaNombreCtrl.dispose();
    _empresaRifCtrl.dispose();
    _usuarioNombreCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _licenciaCtrl.dispose();
    super.dispose();
  }

  void _onRegister() {
    if (_formKey.currentState?.validate() ?? false) {
      setState(() => _error = null);
      context.read<AuthBloc>().add(RegisterEvent(
            empresaNombre: _empresaNombreCtrl.text.trim(),
            empresaRif: _empresaRifCtrl.text.trim(),
            usuarioNombre: _usuarioNombreCtrl.text.trim(),
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
            licenciaKey: _licenciaCtrl.text.trim().isNotEmpty
                ? _licenciaCtrl.text.trim()
                : null,
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: BlocListener<AuthBloc, AuthState>(
          listener: (context, state) {
            if (state is AuthError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: SwsColors.danger,
                ),
              );
            } else if (state is AuthAuthenticated) {
              Navigator.pushReplacementNamed(context, '/dashboard');
            }
          },
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [SwsColors.gradientStart, SwsColors.gradientEnd],
              ),
            ),
            child: SafeArea(
              top: true,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const BrandText(size: 44, withTagline: true),
                        const SizedBox(height: 24),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Crear Cuenta',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Registra tu empresa y primer usuario',
                                    style: TextStyle(
                                        color: SwsColors.gray500,
                                        fontSize: 13),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 20),
                                  TextFormField(
                                    controller: _empresaNombreCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Nombre de la Empresa',
                                      prefixIcon: Icon(Icons.business_outlined),
                                      border: OutlineInputBorder(),
                                    ),
                                    validator: (v) =>
                                        v == null || v.trim().isEmpty
                                            ? 'Ingresa el nombre de la empresa'
                                            : null,
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _empresaRifCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'RIF / NIT',
                                      prefixIcon: Icon(Icons.badge_outlined),
                                      border: OutlineInputBorder(),
                                    ),
                                    validator: (v) =>
                                        v == null || v.trim().isEmpty
                                            ? 'Ingresa el RIF'
                                            : null,
                                  ),
                                  const SizedBox(height: 20),
                                  const Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'Usuario Administrador',
                                      style: TextStyle(
                                        color: SwsColors.gray600,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: _usuarioNombreCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Nombre del Usuario',
                                      prefixIcon: Icon(Icons.person_outline),
                                      border: OutlineInputBorder(),
                                    ),
                                    validator: (v) =>
                                        v == null || v.trim().isEmpty
                                            ? 'Ingresa tu nombre'
                                            : null,
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _emailCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Correo electrónico',
                                      prefixIcon: Icon(Icons.mail_outline),
                                      border: OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.emailAddress,
                                    validator: (v) =>
                                        v == null || !v.contains('@')
                                            ? 'Ingresa un correo válido'
                                            : null,
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _passwordCtrl,
                                    obscureText: _obscurePassword,
                                    decoration: InputDecoration(
                                      labelText: 'Contraseña',
                                      prefixIcon:
                                          const Icon(Icons.lock_outline),
                                      border: const OutlineInputBorder(),
                                      suffixIcon: IconButton(
                                        onPressed: () => setState(() =>
                                            _obscurePassword =
                                                !_obscurePassword),
                                        icon: Icon(_obscurePassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined),
                                      ),
                                    ),
                                    validator: (v) =>
                                        v != null && v.length >= 6
                                            ? null
                                            : 'Mínimo 6 caracteres',
                                  ),
                                  const SizedBox(height: 20),
                                  const Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'Licencia (opcional)',
                                      style: TextStyle(
                                        color: SwsColors.gray600,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: _licenciaCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Clave de Licencia',
                                      hintText: 'WS-XXXX-XXXX-XXXX-XXXX',
                                      prefixIcon:
                                          Icon(Icons.vpn_key_outlined),
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  if (_error != null) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      _error!,
                                      style: const TextStyle(
                                          color: SwsColors.danger),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                  const SizedBox(height: 20),
                                  BlocBuilder<AuthBloc, AuthState>(
                                    builder: (context, state) {
                                      final loading = state is AuthLoading;
                                      return SizedBox(
                                        width: double.infinity,
                                        child: FilledButton.icon(
                                          onPressed:
                                              loading ? null : _onRegister,
                                          style: FilledButton.styleFrom(
                                            backgroundColor: SwsColors.accent,
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 14),
                                          ),
                                          icon: loading
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: Colors.white))
                                              : const Icon(Icons.person_add),
                                          label: Text(loading
                                              ? 'Registrando...'
                                              : 'Registrarse'),
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  TextButton.icon(
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    icon: const Icon(
                                        Icons.arrow_back_outlined,
                                        size: 18),
                                    label: const Text('Volver'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
