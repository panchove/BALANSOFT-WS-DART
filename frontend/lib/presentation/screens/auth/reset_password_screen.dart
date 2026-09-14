import 'dart:core';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/brand_text.dart';
import '../../providers/bloc/auth/auth_bloc.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String? token;

  const ResetPasswordScreen({super.key, this.token});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  String? get _token {
    if (widget.token != null && widget.token!.isNotEmpty) return widget.token;
    return Uri.base.queryParameters['token'];
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _enviar() {
    final pass = _password.text;
    final pass2 = _confirm.text;
    final token = _token;

    if (token == null || token.isEmpty) {
      setState(() => _error = 'El enlace es inválido o está incompleto');
      return;
    }
    if (pass.length < 6) {
      setState(() => _error = 'La contraseña debe tener al menos 6 caracteres');
      return;
    }
    if (pass != pass2) {
      setState(() => _error = 'Las contraseñas no coinciden');
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });
    context
        .read<AuthBloc>()
        .add(ResetPasswordEvent(token: token, newPassword: pass));
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: BlocListener<AuthBloc, AuthState>(
          listener: (context, state) {
            if (!mounted) return;
            if (state is AuthLoading) {
              setState(() {
                _loading = true;
                _error = null;
              });
            } else if (state is AuthError) {
              setState(() {
                _loading = false;
                _error = state.message;
              });
            } else if (state is AuthPasswordChanged) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Contraseña actualizada, inicia sesión'),
                  backgroundColor: SwsColors.success,
                ),
              );
              Navigator.of(context).pushNamedAndRemoveUntil(
                '/login',
                (route) => false,
              );
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
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Nueva Contraseña',
                                  style:
                                      Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Crea una nueva contraseña para tu cuenta',
                                  style: TextStyle(
                                      color: SwsColors.gray500, fontSize: 13),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 20),
                                TextField(
                                  controller: _password,
                                  obscureText: _obscure,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    labelText: 'Nueva contraseña',
                                    prefixIcon:
                                        const Icon(Icons.lock_outline),
                                    border: const OutlineInputBorder(),
                                    suffixIcon: IconButton(
                                      icon: Icon(_obscure
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined),
                                      onPressed: () => setState(
                                          () => _obscure = !_obscure),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextField(
                                  controller: _confirm,
                                  obscureText: _obscure,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _enviar(),
                                  decoration: const InputDecoration(
                                    labelText: 'Confirmar contraseña',
                                    prefixIcon: Icon(Icons.lock_outline),
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
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                    onPressed: _loading ? null : _enviar,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: SwsColors.accent,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                    ),
                                    icon: _loading
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child:
                                                CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: Colors.white))
                                        : const Icon(Icons.save_outlined),
                                    label: Text(_loading
                                        ? 'Guardando...'
                                        : 'Restablecer contraseña'),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextButton.icon(
                                  onPressed: () =>
                                      Navigator.of(context).pop(),
                                  icon: const Icon(
                                      Icons.arrow_back_outlined, size: 18),
                                  label: const Text('Volver'),
                                ),
                              ],
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