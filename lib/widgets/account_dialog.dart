import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_lang.dart';
import '../screens/login_screen.dart';
import '../state/auth_state.dart';

/// The account from the menu: who is signed in with the way out, or the way in.
Future<void> showAccountDialog(BuildContext context) async {
  final auth = context.read<AuthState>();
  if (!auth.signedIn) {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    return;
  }
  final action = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Cuenta')),
      content: Text(auth.user!.label),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'delete'),
          child: Text(tr('Borrar cuenta')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(tr('Cerrar')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, 'out'),
          child: Text(tr('Cerrar sesión')),
        ),
      ],
    ),
  );
  if (action == 'out') {
    final ok = await auth.signOut();
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.error ?? tr('No se pudo cerrar la sesión.'))),
      );
    }
  }
  if (action == 'delete' && context.mounted) await _deleteAccount(context);
}

Future<void> _deleteAccount(BuildContext context) async {
  final auth = context.read<AuthState>();
  final sure = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('¿Borrar tu cuenta?')),
      content: Text(tr('Se borra la cuenta {email}. Tus mascotas y sus datos '
          'siguen en este celular.', {'email': auth.user!.label})),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(tr('Cancelar')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tr('Borrar cuenta')),
        ),
      ],
    ),
  );
  if (sure != true) return;
  final ok = await auth.deleteAccount();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(ok ? tr('Cuenta borrada.') : auth.error ?? ''),
  ));
}
