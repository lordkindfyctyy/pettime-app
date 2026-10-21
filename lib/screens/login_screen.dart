import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_lang.dart';
import '../state/auth_state.dart';
import '../theme.dart';

/// Sign in or create an account. It is the first screen when the build has a
/// login ([asGate]), or opens from the menu to sign in later.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.asGate = false});

  final bool asGate;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _creating = false;
  bool _hidePassword = true;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _done(bool ok) {
    if (ok && mounted && !widget.asGate) Navigator.pop(context);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthState>();
    setState(() => _notice = null);
    final ok = _creating
        ? await auth.register(_email.text, _password.text)
        : await auth.signInWithEmail(_email.text, _password.text);
    _done(ok);
  }

  Future<void> _google() async {
    setState(() => _notice = null);
    _done(await context.read<AuthState>().signInWithGoogle());
  }

  Future<void> _forgot() async {
    final auth = context.read<AuthState>();
    final sent = await auth.sendPasswordReset(_email.text);
    if (sent && mounted) {
      setState(() => _notice = tr('Te mandamos un email para elegir otra contraseña.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final theme = Theme.of(context);
    final busy = auth.busy;
    return Scaffold(
      appBar: widget.asGate ? null : AppBar(title: Text(tr('Cuenta'))),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.asGate) ...[
                      const Icon(Icons.pets, size: 56, color: Brand.red),
                      const SizedBox(height: 8),
                      Text(
                        tr('PetTime'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    Text(
                      _creating ? tr('Crear cuenta') : tr('Iniciar sesión'),
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(
                        labelText: tr('Email'),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) => (v ?? '').contains('@')
                          ? null
                          : tr('Ingresá tu email'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: _hidePassword,
                      autofillHints: [
                        _creating
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      decoration: InputDecoration(
                        labelText: tr('Contraseña'),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _hidePassword
                              ? tr('Mostrar contraseña')
                              : tr('Ocultar contraseña'),
                          icon: Icon(
                            _hidePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () =>
                              setState(() => _hidePassword = !_hidePassword),
                        ),
                      ),
                      validator: (v) => (v ?? '').length >= 6
                          ? null
                          : tr('Usá al menos 6 caracteres'),
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    if (auth.error != null || _notice != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        auth.error ?? _notice!,
                        style: TextStyle(
                          color: auth.error != null
                              ? theme.colorScheme.error
                              : Brand.teal,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: busy ? null : _submit,
                      child: busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _creating ? tr('Crear cuenta') : tr('Entrar'),
                            ),
                    ),
                    if (!_creating)
                      TextButton(
                        onPressed: busy ? null : _forgot,
                        child: Text(tr('Olvidé mi contraseña')),
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: busy ? null : _google,
                      icon: const Icon(Icons.account_circle_outlined),
                      label: Text(tr('Continuar con Google')),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () {
                              context.read<AuthState>().clearError();
                              setState(() {
                                _creating = !_creating;
                                _notice = null;
                              });
                            },
                      child: Text(
                        _creating
                            ? tr('Ya tengo cuenta: iniciar sesión')
                            : tr('No tengo cuenta: crear una'),
                      ),
                    ),
                    if (widget.asGate)
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => context.read<AuthState>().skip(),
                        child: Text(tr('Continuar sin cuenta')),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
