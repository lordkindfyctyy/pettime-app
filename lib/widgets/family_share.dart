import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/pet.dart';
import '../screens/pet_detail_screen.dart';
import '../services/family_sync.dart';
import '../state/pets_state.dart';
import '../theme.dart';
import 'caregiver_sheet.dart';
import 'copyable_code.dart';

/// What is sent to the family so they can join.
String familyInviteText(Pet pet) =>
    'Sumate a ${pet.name} en PetTime: así los dos vemos y marcamos sus '
    'remedios, vacunas y turnos.\n\n'
    '1. Instalá PetTime: https://sixsevenweb.com/pettime/\n'
    '2. En "Mascotas" tocá ⋮ → "Unirme con un código"\n'
    '3. Copiá este mensaje y tocá "Pegar", o escribí el código: '
    '${pet.share!.displayCode}';

/// The family or caregiver code in [text], which may be the whole invite
/// message pasted from WhatsApp; null when there is none.
String? findShareCode(String text) {
  final upper = text.toUpperCase();
  final grouped = RegExp(r'\b[A-Z0-9]{4}-[A-Z0-9]{4}(?:-[A-Z0-9]{4})?\b')
      .allMatches(upper)
      .map((m) => m[0]!)
      .toList();
  if (grouped.isNotEmpty) {
    return grouped.last.replaceAll('-', '');
  }
  final plain = upper.replaceAll(RegExp(r'[\s-]'), '');
  return RegExp(r'^[A-Z0-9]{8}([A-Z0-9]{4})?$').hasMatch(plain) ? plain : null;
}

/// Shares [pet] with the family, or shows its code if it already is.
Future<void> showFamilyShareSheet(BuildContext context, String petId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _FamilySheet(petId: petId),
  );
}

class _FamilySheet extends StatefulWidget {
  const _FamilySheet({required this.petId});

  final String petId;

  @override
  State<_FamilySheet> createState() => _FamilySheetState();
}

class _FamilySheetState extends State<_FamilySheet> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() task, {String? done}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await task();
      if (done != null) messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String text, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(action),
            ),
          ],
        ),
      ) ==
      true;

  @override
  Widget build(BuildContext context) {
    final pet = context.watch<PetsState>().byId(widget.petId);
    if (pet == null) return const SizedBox.shrink();
    final share = pet.share;
    final theme = Theme.of(context);
    final sync = FamilySync.instance;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.family_restroom, color: Brand.teal),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Compartir a ${pet.name} con la familia',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (share != null && share.isCaregiver) ...[
              Text(
                pet.careFinished(DateTime.now())
                    ? 'Terminó tu cuidado de ${pet.name}. Sale de este celular '
                          'cuando se envíen tus últimos cambios.'
                    : 'Cuidás a ${pet.name} ${careUntilLabel(pet.careEndsAt!)}. '
                          'Lo que marques le llega a su familia.',
              ),
              const SizedBox(height: 4),
              Text(
                share.dirty
                    ? 'Hay cambios por enviar (se envían al tener internet)'
                    : 'Al día con la familia',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.sync),
                label: const Text('Sincronizar ahora'),
                onPressed: _busy
                    ? null
                    : () => _run(sync.syncAll, done: 'Listo'),
              ),
              const Divider(height: 24),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                onPressed: _busy
                    ? null
                    : () async {
                        final navigator = Navigator.of(context);
                        if (await _confirm(
                          '¿Terminar el cuidado ahora?',
                          '${pet.name} sale de este celular. Lo que anotaste ya '
                              'le llegó a su familia.',
                          'Terminar',
                        )) {
                          await _run(() => sync.leave(pet));
                          navigator.popUntil((r) => r.isFirst);
                        }
                      },
                child: const Text('Terminar el cuidado ahora'),
              ),
            ] else if (share == null) ...[
              const Text(
                'Los que se sumen con el código ven a la mascota en su PetTime y '
                'pueden marcar las tomas, cargar vacunas, turnos y gastos. Los '
                'cambios de cada uno les llegan a todos, y todos reciben los avisos '
                'de los remedios.',
              ),
              const SizedBox(height: 8),
              Text(
                'Para eso la mascota se guarda en sixsevenweb.com. Pasale el '
                'código solo a quien quieras.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.group_add_outlined),
                label: Text(_busy ? 'Compartiendo…' : 'Compartir'),
                onPressed: _busy ? null : () => _run(() => sync.share(pet)),
              ),
            ] else ...[
              Text(
                share.isOwner
                    ? 'Pasale este código a tu familia:'
                    : 'Compartida con la familia. Código:',
              ),
              const SizedBox(height: 8),
              Center(child: CopyableCode(code: share.displayCode)),
              const SizedBox(height: 4),
              Text(
                share.dirty ? 'Hay cambios por enviar (se envían al tener internet)' : 'Al día con la familia',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.send_outlined),
                label: const Text('Mandar el código'),
                onPressed: () => SharePlus.instance.share(
                  ShareParams(text: familyInviteText(pet)),
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.sync),
                label: const Text('Sincronizar ahora'),
                onPressed: _busy ? null : () => _run(sync.syncAll, done: 'Listo'),
              ),
              const Divider(height: 24),
              if (share.isOwner)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                  onPressed: _busy
                      ? null
                      : () async {
                          if (await _confirm(
                            '¿Dejar de compartir?',
                            'Se borra del servidor. Los demás se quedan con su copia, '
                                'pero ya no reciben los cambios.',
                            'Dejar de compartir',
                          )) {
                            await _run(() => sync.stop(pet), done: 'Ya no se comparte');
                          }
                        },
                  child: const Text('Dejar de compartir'),
                )
              else
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                  onPressed: _busy
                      ? null
                      : () async {
                          if (await _confirm(
                            '¿Dejar de recibir cambios?',
                            '${pet.name} queda en este celular, pero ya no se '
                                'sincroniza con la familia.',
                            'Dejar de recibir',
                          )) {
                            await _run(() => sync.leave(pet));
                          }
                        },
                  child: const Text('Dejar de recibir cambios'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Asks for a family code and adds that pet to this phone.
Future<void> showJoinFamilyDialog(BuildContext context) async {
  final navigator = Navigator.of(context);
  final pet = await showDialog<Pet>(
    context: context,
    builder: (_) => const _JoinDialog(),
  );
  if (pet == null) return;
  navigator.push(
    MaterialPageRoute(builder: (_) => PetDetailScreen(petId: pet.id)),
  );
}

class _JoinDialog extends StatefulWidget {
  const _JoinDialog();

  @override
  State<_JoinDialog> createState() => _JoinDialogState();
}

class _JoinDialogState extends State<_JoinDialog> {
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  /// Pastes the code, or finds it in the whole invite message.
  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final code = findShareCode(data?.text ?? '');
    setState(() {
      if (code == null) {
        _error = 'No hay ningún código copiado. Copiá el mensaje que te '
            'mandaron y volvé a tocar "Pegar".';
      } else {
        _code.text = code.length == 8
            ? '${code.substring(0, 4)}-${code.substring(4)}'
            : '${code.substring(0, 4)}-${code.substring(4, 8)}-${code.substring(8)}';
        _error = null;
      }
    });
  }

  Future<void> _join() async {
    final code = findShareCode(_code.text) ??
        _code.text.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    if (code.length != 8 && code.length != 12) {
      setState(
        () => _error = 'El código de la familia tiene 8 letras y números, el de un cuidador 12',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final pet = await FamilySync.instance.join(code);
      if (mounted) Navigator.pop(context, pet);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Unirme con un código'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Copiá el mensaje que te mandaron y tocá "Pegar", o escribí el '
            'código: el de la familia o el de cuidador.',
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.content_paste),
            label: const Text('Pegar'),
            onPressed: _busy ? null : _paste,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Código',
              hintText: 'K7Q2-M9XP',
              errorText: _error,
              errorMaxLines: 3,
            ),
            onSubmitted: (_) => _join(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _busy ? null : _join,
          child: Text(_busy ? 'Buscando…' : 'Unirme'),
        ),
      ],
    );
  }
}
