import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_lang.dart';
import '../models/pet.dart';
import '../models/walk.dart';
import '../state/pets_state.dart';
import '../theme.dart';
import 'confirm_delete.dart';

/// Asks for a walk (how long, optionally how far) and saves it. With [walk],
/// edits it.
Future<void> showWalkDialog(BuildContext context, Pet pet, {Walk? walk}) async {
  final state = context.read<PetsState>();
  final result = await showDialog<Walk>(
    context: context,
    builder: (_) => _WalkDialog(pet: pet, walk: walk, newId: state.newId),
  );
  if (result != null) await state.saveWalk(pet.id, result);
}

class _WalkDialog extends StatefulWidget {
  const _WalkDialog({required this.pet, this.walk, required this.newId});

  final Pet pet;
  final Walk? walk;
  final String Function() newId;

  @override
  State<_WalkDialog> createState() => _WalkDialogState();
}

class _WalkDialogState extends State<_WalkDialog> {
  static const _quick = [15, 20, 30, 45, 60];

  final _formKey = GlobalKey<FormState>();
  late final _minutes = TextEditingController(
    text: '${widget.walk?.minutes ?? _lastMinutes ?? 30}',
  );
  late final _km = TextEditingController(
    text: widget.walk?.km == null
        ? ''
        : formatKm(widget.walk!.km!).replaceAll(' km', ''),
  );
  late final _note = TextEditingController(text: widget.walk?.note ?? '');
  late DateTime _date = widget.walk?.date ?? DateTime.now();

  /// The last walk is usually as long as the next one.
  int? get _lastMinutes =>
      widget.pet.walks.isEmpty ? null : widget.pet.walks.first.minutes;

  @override
  void dispose() {
    _minutes.dispose();
    _km.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    setState(() {
      _date = DateTime(
        d.year,
        d.month,
        d.day,
        t?.hour ?? _date.hour,
        t?.minute ?? _date.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final minutes = int.tryParse(_minutes.text.trim());
    return AlertDialog(
      title: Text(tr('Paseo de {name}', {'name': widget.pet.name})),
      scrollable: true,
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final m in _quick)
                  ChoiceChip(
                    label: Text(formatMinutes(m)),
                    selected: minutes == m,
                    onSelected: (_) => setState(() => _minutes.text = '$m'),
                  ),
              ],
            ),
            TextFormField(
              controller: _minutes,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: tr('Duración'),
                suffixText: tr('min'),
              ),
              onChanged: (_) => setState(() {}),
              validator: (v) {
                final n = int.tryParse(v?.trim() ?? '');
                return n == null || n <= 0 || n > 600
                    ? tr('Ingresá los minutos')
                    : null;
              },
            ),
            TextFormField(
              controller: _km,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: tr('Distancia (opcional)'),
                suffixText: tr('km'),
                hintText: '2,5',
              ),
              validator: (v) => (v ?? '').trim().isEmpty || parseKm(v!) != null
                  ? null
                  : tr('Ingresá los km, por ejemplo 2,5'),
            ),
            TextFormField(
              controller: _note,
              decoration: InputDecoration(
                labelText: tr('Nota (opcional)'),
                hintText: tr('Plaza, con la correa nueva…'),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Cuándo')),
              subtitle: Text(DateFormat.yMMMd(AppLang.code).add_Hm().format(_date)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: _pickDate,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Cancelar')),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              Walk(
                id: widget.walk?.id ?? widget.newId(),
                date: _date,
                minutes: int.parse(_minutes.text.trim()),
                km: parseKm(_km.text),
                note: _note.text.trim(),
              ),
            );
          },
          child: Text(tr('Guardar')),
        ),
      ],
    );
  }
}

/// Turns the daily walk reminder on (asking the time) or off.
Future<void> toggleWalkReminder(BuildContext context, Pet pet, bool on) async {
  final state = context.read<PetsState>();
  if (!on) {
    await state.setWalkReminder(pet.id, null);
    return;
  }
  final current = pet.walkReminder;
  final t = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(
      hour: current?.hour ?? 18,
      minute: current?.minute ?? 0,
    ),
    helpText: tr('Si a esta hora no salió, te avisamos'),
  );
  if (t == null) return;
  await state.setWalkReminder(
    pet.id,
    WalkReminder(hour: t.hour, minute: t.minute),
  );
}

/// The pet's walks in its profile: today, the last 7 days as bars, the
/// streak and the daily reminder.
class WalkSection extends StatelessWidget {
  const WalkSection({super.key, required this.pet, this.now});

  final Pet pet;

  /// Current time; tests pass a fixed one.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = now ?? DateTime.now();
    final todays = walksOn(pet.walks, today);
    final todayMinutes = todays.fold(0, (sum, w) => sum + w.minutes);
    final week = minutesLast7Days(pet.walks, today);
    final weekTotal = week.fold(0, (a, b) => a + b);
    final streak = walkStreak(pet.walks, today);
    final reminder = pet.walkReminder;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              todays.isEmpty
                  ? tr('Hoy todavía no salió')
                  : todays.length == 1
                      ? tr('Hoy: {count} paseo · {time}', {
                          'count': 1,
                          'time': formatMinutes(todayMinutes),
                        })
                      : tr('Hoy: {count} paseos · {time}', {
                          'count': todays.length,
                          'time': formatMinutes(todayMinutes),
                        }),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: todays.isEmpty ? Brand.orange : Brand.teal,
              ),
            ),
            if (pet.walks.isNotEmpty)
              Text(
                [
                  tr('Últimos 7 días: {time}', {'time': formatMinutes(weekTotal)}),
                  if (streak > 1) tr('{streak} días seguidos', {'streak': streak}),
                ].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
            if (weekTotal > 0) ...[
              const SizedBox(height: 12),
              WalkWeekBars(minutes: week, today: today),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Avisarme si no salió')),
              subtitle: Text(
                reminder == null
                    ? tr('Un aviso por día, si no anotaste ningún paseo')
                    : tr('Todos los días a las {label}', {'label': reminder.label}),
              ),
              value: reminder != null,
              onChanged: (on) => toggleWalkReminder(context, pet, on),
            ),
            if (reminder != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.schedule),
                  label: Text(tr('Cambiar la hora')),
                  onPressed: () => toggleWalkReminder(context, pet, true),
                ),
              ),
            if (pet.walks.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.history),
                  label: Text(tr('Historial ({length})', {'length': pet.walks.length})),
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => WalkHistorySheet(petId: pet.id),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Minutes walked on each of the last 7 days, as bars with the day's letter.
class WalkWeekBars extends StatelessWidget {
  const WalkWeekBars({super.key, required this.minutes, required this.today});

  /// Oldest first; the last one is [today].
  final List<int> minutes;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = math.max(minutes.reduce(math.max), 1);
    final letter = DateFormat.E(AppLang.code);
    return SizedBox(
      height: 96,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (i, m) in minutes.indexed)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      height: m == 0 ? 3 : 4 + 60 * m / top,
                      decoration: BoxDecoration(
                        color: m == 0
                            ? theme.colorScheme.outlineVariant
                            : i == minutes.length - 1
                            ? Brand.teal
                            : Brand.teal.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      child: Text(
                        letter
                            .format(
                              DateTime(
                                today.year,
                                today.month,
                                today.day - 6 + i,
                              ),
                            )
                            .substring(0, 1)
                            .toUpperCase(),
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Every walk, newest first, to edit or delete one.
class WalkHistorySheet extends StatelessWidget {
  const WalkHistorySheet({super.key, required this.petId});

  final String petId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PetsState>();
    final pet = state.byId(petId);
    if (pet == null) return const SizedBox.shrink();
    final fmt = DateFormat.yMMMd(AppLang.code).add_Hm();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                tr('Paseos de {name}', {'name': pet.name}),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final w in pet.walks)
                    ListTile(
                      leading: const Icon(Icons.directions_walk),
                      title: Text(
                        [
                          formatMinutes(w.minutes),
                          if (w.km != null) formatKm(w.km!),
                        ].join(' · '),
                      ),
                      subtitle: Text(
                        [
                          fmt.format(w.date),
                          if (w.note.isNotEmpty) w.note,
                        ].join(' · '),
                      ),
                      onTap: () => showWalkDialog(context, pet, walk: w),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: tr('Borrar'),
                        onPressed: () async {
                          if (await confirmDelete(
                            context,
                            tr('el paseo de {n} del {n2}', {'n': formatMinutes(w.minutes), 'n2': fmt.format(w.date)}),
                          )) {
                            await state.deleteWalk(petId, w.id);
                          }
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
