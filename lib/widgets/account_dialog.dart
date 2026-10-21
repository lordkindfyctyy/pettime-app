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
  final out = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Cuenta')),
      content: Text(auth.user!.label),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(tr('Cerrar')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tr('Cerrar sesión')),
        ),
      ],
    ),
  );
  if (out == true) await auth.signOut();
}
