// lib/presentation/screens/auth/widgets/register_form_content.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../providers/bloc/auth/auth_bloc.dart';

class RegisterFormContent extends StatefulWidget {
  final VoidCallback onBackToLogin;

  const RegisterFormContent({super.key, required this.onBackToLogin});

  @override
  State<RegisterFormContent> createState() => _RegisterFormContentState();
}

class _RegisterFormContentState extends State<RegisterFormContent> {
  final _formKey = GlobalKey<FormState>();
  final _empresaNombreCtrl = TextEditingController();
  final _empresaRifCtrl = TextEditingController();
  final _usuarioNombreCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _licenciaCtrl = TextEditingController();
  bool _obscurePassword = true;

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

  InputDecoration _buildInputDecoration(String label, IconData icon, {String? hintText, Widget? suffixIcon}) {
    return InputDecoration(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.06),
      labelText: label,
      hintText: hintText,
      hintStyle: const TextStyle(color: Colors.white38),
      labelStyle: const TextStyle(color: Colors.white60),
      prefixIcon: Icon(icon, color: Colors.white60),
      suffixIcon: suffixIcon,
      enabledBorder: const UnderlineInputBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        borderSide: BorderSide(color: Colors.white30, width: 1.5),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        borderSide: BorderSide(color: SwsColors.accent, width: 2.0),
      ),
      border: const UnderlineInputBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Crear Cuenta',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Registra tu empresa y primer usuario',
            style: TextStyle(color: Colors.white60, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          TextFormField(
            controller: _empresaNombreCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: _buildInputDecoration('Nombre de la Empresa', Icons.business_outlined),
            validator: (v) => v == null || v.trim().isEmpty ? 'Ingresa el nombre de la empresa' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _empresaRifCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: _buildInputDecoration('RIF / NIT', Icons.badge_outlined),
            validator: (v) => v == null || v.trim().isEmpty ? 'Ingresa el RIF' : null,
          ),

          const SizedBox(height: 20),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Usuario Administrador',
              style: TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 8),

          TextFormField(
            controller: _usuarioNombreCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: _buildInputDecoration('Nombre del Usuario', Icons.person_outline),
            validator: (v) => v == null || v.trim().isEmpty ? 'Ingresa tu nombre' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: Colors.white),
            decoration: _buildInputDecoration('Correo electrónico', Icons.mail_outline),
            validator: (v) => v == null || !v.contains('@') ? 'Ingresa un correo válido' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordCtrl,
            obscureText: _obscurePassword,
            style: const TextStyle(color: Colors.white),
            decoration: _buildInputDecoration(
              'Contraseña',
              Icons.lock_outline,
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.white60),
              ),
            ),
            validator: (v) => v != null && v.length >= 6 ? null : 'Mínimo 6 caracteres',
          ),

          const SizedBox(height: 20),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Licencia (opcional)',
              style: TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 8),

          TextFormField(
            controller: _licenciaCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: _buildInputDecoration('Clave de Licencia', Icons.vpn_key_outlined, hintText: 'WS-XXXX-XXXX-XXXX-XXXX'),
          ),
          const SizedBox(height: 28),

          BlocBuilder<AuthBloc, AuthState>(
            builder: (context, state) {
              final loading = state is AuthLoading;
              return SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: loading ? null : _onRegister,
                  style: FilledButton.styleFrom(
                    backgroundColor: SwsColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: loading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.person_add),
                  label: Text(loading ? 'Registrando...' : 'Registrarse', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          TextButton.icon(
            onPressed: widget.onBackToLogin,
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
            icon: const Icon(Icons.arrow_back_outlined, size: 18),
            label: const Text('Volver a Iniciar Sesión'),
          ),
        ],
      ),
    );
  }
}