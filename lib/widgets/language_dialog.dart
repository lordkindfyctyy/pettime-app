import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_lang.dart';
import '../state/language_state.dart';

/// Lets the user pick the language of the app, or follow the phone's.
Future<void> showLanguageDialog(BuildContext context) async {
  final state = context.read<LanguageState>();
  final options = <(String?, String)>[
    (null, tr('Automático (idioma del celular)')),
    ('es', 'Español'),
    ('en', 'English'),
  ];
  final picked = await showDialog<(String?,)>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(tr('Idioma')),
      children: [
        for (final (code, label) in options)
          ListTile(
            leading: Icon(
              code == state.choice
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
            ),
            title: Text(label),
            onTap: () => Navigator.pop(ctx, (code,)),
          ),
      ],
    ),
  );
  if (picked != null) await state.setChoice(picked.$1);
}
