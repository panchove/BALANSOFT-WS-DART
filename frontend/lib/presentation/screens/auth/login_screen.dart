import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/brand_text.dart';
import '../../providers/bloc/auth/auth_bloc.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    context.read<AuthBloc>().add(LoginEvent(
          email: _email.text.trim(),
          password: _password.text,
        ));
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
                        const BrandText(size: 56, withTagline: true),
                        const SizedBox(height: 32),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Iniciar Sesión',
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Accede a tu estación de pesaje',
                                    style: TextStyle(
                                        color: SwsColors.gray500, fontSize: 13),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 20),
                                  TextFormField(
                                    key: const Key('email_field'),
                                    controller: _email,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.next,
                                    validator: Validators.email,
                                    decoration: const InputDecoration(
                                      labelText: 'Correo electrónico',
                                      prefixIcon: Icon(Icons.mail_outline),
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    key: const Key('password_field'),
                                    controller: _password,
                                    obscureText: _obscure,
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) => _submit(),
                                    validator: Validators.password,
                                    decoration: InputDecoration(
                                      labelText: 'Contraseña',
                                      prefixIcon: const Icon(Icons.lock_outline),
                                      border: const OutlineInputBorder(),
                                      suffixIcon: IconButton(
                                        onPressed: () => setState(
                                            () => _obscure = !_obscure),
                                        icon: Icon(_obscure
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined),
                                      ),
                                    ),
                                  ),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: () => Navigator.pushNamed(
                                          context, '/forgot-password'),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4, vertical: 4),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: const Text(
                                        '¿Olvidaste tu contraseña?',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  BlocBuilder<AuthBloc, AuthState>(
                                    builder: (context, state) {
                                      final loading = state is AuthLoading;
                                      return SizedBox(
                                        width: double.infinity,
                                        child: FilledButton.icon(
                                          key: const Key('login_button'),
                                          onPressed: loading ? null : _submit,
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
                                              : const Icon(Icons.login),
                                          label: Text(loading
                                              ? 'Ingresando...'
                                              : 'Iniciar Sesión'),
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    '¿No tienes una cuenta?',
                                    style: TextStyle(
                                        color: SwsColors.gray500, fontSize: 13),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 4),
                                  TextButton.icon(
                                    onPressed: () => Navigator.pushNamed(
                                        context, '/register'),
                                    icon: const Icon(Icons.person_add_outlined,
                                        size: 18),
                                    label: const Text('Crear cuenta nueva'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Funciona sin conexión',
                          style: TextStyle(
                              color: SwsColors.gray500, fontSize: 12),
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
