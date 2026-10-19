import 'package:flutter/material.dart';

/// Asks before deleting, so a trash button touched by mistake doesn't erase
/// anything. [what] names what goes ("el paseo del 18 oct. 2026"); [detail]
/// says what else happens.
Future<bool> confirmDelete(
  BuildContext context,
  String what, {
  String detail = 'No se puede deshacer.',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('¿Eliminar $what?'),
      content: Text(detail),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Eliminar'),
        ),
      ],
    ),
  );
  return ok == true;
}
