import 'package:flutter/material.dart';
import '../l10n/app_lang.dart';

/// Asks before deleting, so a trash button touched by mistake doesn't erase
/// anything. [what] names what goes ("el paseo del 18 oct. 2026"); [detail]
/// says what else happens.
Future<bool> confirmDelete(
  BuildContext context,
  String what, {
  String? detail,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('¿Eliminar {what}?', {'what': what})),
      content: Text(detail ?? tr('No se puede deshacer.')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(tr('Cancelar')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tr('Eliminar')),
        ),
      ],
    ),
  );
  return ok == true;
}
