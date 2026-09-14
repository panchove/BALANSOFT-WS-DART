import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/brand_text.dart';
import '../../providers/bloc/auth/auth_bloc.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  String? _error;
  bool _enviado = false;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _enviar() {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Ingresa un correo electrónico válido');
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });
    context.read<AuthBloc>().add(ForgotPasswordEvent(email: email));
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
            } else if (state is AuthPasswordResetSent) {
              setState(() {
                _loading = false;
                _enviado = true;
              });
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
                                if (!_enviado) ...[
                                  Text(
                                    'Recuperar Contraseña',
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Te enviaremos un enlace para restablecer '
                                    'tu contraseña',
                                    style: TextStyle(
                                        color: SwsColors.gray500, fontSize: 13),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 20),
                                  TextField(
                                    controller: _email,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.done,
                                    onSubmitted: (_) => _enviar(),
                                    decoration: const InputDecoration(
                                      labelText: 'Correo electrónico',
                                      prefixIcon: Icon(Icons.mail_outline),
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
                                          : const Icon(Icons.send_outlined),
                                      label: Text(_loading
                                          ? 'Enviando...'
                                          : 'Enviar'),
                                    ),
                                  ),
                                ] else ...[
                                  const Icon(Icons.check_circle_outline,
                                      color: SwsColors.success, size: 56),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Revisa tu correo',
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Si existe una cuenta con ese correo, '
                                    'recibirás un enlace para restablecer tu '
                                    'contraseña.',
                                    style: TextStyle(
                                        color: SwsColors.gray500, fontSize: 13),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 20),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: SwsColors.accent,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 14),
                                      ),
                                      child: const Text('Volver al inicio'),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                if (!_enviado)
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