import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_lang.dart';
import '../models/caregiver.dart';
import '../models/pet.dart';
import '../services/family_sync.dart';
import '../state/pets_state.dart';
import '../theme.dart';
import 'copyable_code.dart';

DateFormat get _untilFmt => DateFormat(tr("EEEE d 'de' MMMM"), AppLang.code);

/// "hasta el sábado 25 de octubre".
String careUntilLabel(DateTime until) => tr('hasta el {n}', {'n': _untilFmt.format(until)});

/// The 12 characters [c] types to join, as "ABCD-EFGH-JKLM".
String caregiverCode(Pet pet, Caregiver c) =>
    CaregiverCode.display(CaregiverCode.encode(pet.share!.code, c.id));

/// What is sent to the caregiver so they can join.
String caregiverInviteText(Pet pet, Caregiver c) {
  final code = caregiverCode(pet, c);
  return tr('Te dejo a {name} en PetTime {n}: vas a ver sus remedios, vacunas, turnos y paseos, y te avisa cuándo darle cada cosa.\n\n1. Instalá PetTime: https://sixsevenweb.com/pettime/\n2. En "Mascotas" tocá ⋮ → "Unirme con un código"\n3. Copiá este mensaje y tocá "Pegar", o escribí el código: {code}\n\nCuando termine, {name2} desaparece de tu PetTime.', {'name': pet.name, 'n': careUntilLabel(c.until), 'code': code, 'name2': pet.name});
}

/// Leaves the pet with someone for a few days, or shows who has it.
Future<void> showCaregiverSheet(BuildContext context, String petId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CaregiverSheet(petId: petId),
  );
}

class _CaregiverSheet extends StatefulWidget {
  const _CaregiverSheet({required this.petId});

  final String petId;

  @override
  State<_CaregiverSheet> createState() => _CaregiverSheetState();
}

class _CaregiverSheetState extends State<_CaregiverSheet> {
  bool _busy = false;

  Future<void> _sendCode(Pet pet, Caregiver c) =>
      SharePlus.instance.share(ShareParams(text: caregiverInviteText(pet, c)));

  Future<void> _add() async {
    final state = context.read<PetsState>();
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<(String, DateTime)>(
      context: context,
      builder: (_) => const _NewCaregiverDialog(),
    );
    if (result == null) return;
    final (name, until) = result;
    setState(() => _busy = true);
    try {
      final sync = FamilySync.instance;
      if (state.byId(widget.petId)!.share == null) {
        await sync.share(state.byId(widget.petId)!);
      }
      final c = Caregiver(id: CaregiverCode.newId(), name: name, until: until);
      await state.saveCaregiver(widget.petId, c);
      if (!await sync.sendNow(widget.petId)) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              tr('No hay internet: el código va a funcionar cuando PetTime se sincronice.'),
            ),
          ),
        );
      }
      await _sendCode(state.byId(widget.petId)!, c);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _end(Pet pet, Caregiver c) async {
    final state = context.read<PetsState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('¿Terminar el cuidado de {name}?', {'name': c.name})),
        content: Text(
          tr('{name} sale del celular de {name2} la próxima vez que se conecte. Lo que anotó queda acá.', {'name': pet.name, 'name2': c.name}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Cancelar')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Terminar')),
          ),
        ],
      ),
    );
    if (ok == true) await state.endCaregiver(pet.id, c.id);
  }

  @override
  Widget build(BuildContext context) {
    final pet = context.watch<PetsState>().byId(widget.petId);
    if (pet == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final active = pet.activeCaregivers(DateTime.now());

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.volunteer_activism_outlined,
                  color: Brand.teal,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr('Dejar a {name} con un cuidador', {'name': pet.name}),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              tr('Para cuando te vas unos días: quien la cuida se suma con su propio código, ve todo y recibe los avisos de los remedios. Al terminar, {name} desaparece de su celular.', {'name': pet.name}),
            ),
            if (pet.share == null) ...[
              const SizedBox(height: 8),
              Text(
                tr('Para eso la mascota se guarda en sixsevenweb.com, como al compartirla con la familia.'),
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            for (final c in active)
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(c.name),
                      subtitle: Text(careUntilLabel(c.until)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.send_outlined),
                            tooltip: tr('Mandar el código'),
                            onPressed: () => _sendCode(pet, c),
                          ),
                          IconButton(
                            icon: const Icon(Icons.block),
                            tooltip: tr('Terminar ahora'),
                            onPressed: () => _end(pet, c),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: CopyableCode(
                        code: caregiverCode(pet, c),
                        large: false,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: Text(_busy ? tr('Preparando el código…') : tr('Agregar cuidador')),
              onPressed: _busy ? null : _add,
            ),
          ],
        ),
      ),
    );
  }
}

class _NewCaregiverDialog extends StatefulWidget {
  const _NewCaregiverDialog();

  @override
  State<_NewCaregiverDialog> createState() => _NewCaregiverDialogState();
}

class _NewCaregiverDialogState extends State<_NewCaregiverDialog> {
  final _name = TextEditingController();
  String? _error;
  late DateTime _day = () {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + 7);
  }();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    return AlertDialog(
      title: Text(tr('Nuevo cuidador')),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: tr('Nombre'),
              hintText: tr('Ana, la vecina…'),
              errorText: _error,
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('La cuida hasta')),
            subtitle: Text(_untilFmt.format(_day)),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _day,
                firstDate: today,
                lastDate: today.add(const Duration(days: 365)),
                helpText: tr('Último día del cuidado'),
              );
              if (d != null) setState(() => _day = d);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Cancelar')),
        ),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) {
              setState(() => _error = tr('Escribí su nombre'));
              return;
            }
            // Until the end of the last day.
            Navigator.pop(context, (
              name,
              DateTime(_day.year, _day.month, _day.day, 23, 59),
            ));
          },
          child: Text(tr('Crear código')),
        ),
      ],
    );
  }
}
