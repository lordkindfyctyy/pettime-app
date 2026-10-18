import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/health_record.dart';
import '../state/pets_state.dart';

/// Adds or edits an entry of the health booklet. With [repeatOf] it registers
/// a new application of that vaccine or antiparasitic: same kind and name,
/// applied today and due again after the same interval.
class HealthRecordFormScreen extends StatefulWidget {
  const HealthRecordFormScreen({
    super.key,
    required this.petId,
    this.record,
    this.repeatOf,
  });

  final String petId;
  final HealthRecord? record;
  final HealthRecord? repeatOf;

  @override
  State<HealthRecordFormScreen> createState() => _HealthRecordFormScreenState();
}

class _HealthRecordFormScreenState extends State<HealthRecordFormScreen> {
  static const _shortcuts = [
    ('1 mes', 1),
    ('3 meses', 3),
    ('6 meses', 6),
    ('1 año', 12),
  ];

  final _formKey = GlobalKey<FormState>();
  late HealthKind _kind;
  late final TextEditingController _name;
  late final TextEditingController _notes;
  late DateTime _appliedOn;
  DateTime? _nextDue;

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    final repeat = widget.repeatOf;
    final base = r ?? repeat;
    _kind = base?.kind ?? HealthKind.vaccine;
    _name = TextEditingController(text: base?.name);
    _notes = TextEditingController(text: r?.notes);
    final today = DateUtils.dateOnly(DateTime.now());
    _appliedOn = r?.appliedOn ?? today;
    _nextDue = r?.nextDue;
    if (repeat != null && repeat.nextDue != null) {
      _nextDue = today.add(repeat.nextDue!.difference(repeat.appliedOn));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  DateTime _addMonths(DateTime from, int months) =>
      DateTime(from.year, from.month + months, from.day);

  Future<DateTime?> _pick(DateTime initial) => showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime.now().subtract(const Duration(days: 365 * 25)),
        lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      );

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final state = context.read<PetsState>();
    await state.saveRecord(
      widget.petId,
      HealthRecord(
        id: widget.record?.id ?? state.newId(),
        kind: _kind,
        name: _name.text.trim(),
        appliedOn: _appliedOn,
        nextDue: _nextDue,
        notes: _notes.text.trim(),
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Eliminar ${widget.record!.name}?'),
        content: const Text('Se borra de la libreta y deja de avisar.'),
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
    if (ok != true || !mounted) return;
    await context.read<PetsState>().deleteRecord(widget.petId, widget.record!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat.yMMMd('es');
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.record == null ? 'Nueva aplicación' : 'Editar'),
        actions: [
          if (widget.record != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Eliminar',
              onPressed: _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          children: [
            DropdownButtonFormField<HealthKind>(
              initialValue: _kind,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: [
                for (final k in HealthKind.values)
                  DropdownMenuItem(value: k, child: Text(k.label)),
              ],
              onChanged: (k) => setState(() => _kind = k ?? _kind),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              decoration: InputDecoration(
                labelText: 'Nombre',
                hintText: _kind.hint,
              ),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Ingresá el nombre' : null,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final s in _kind.suggestions)
                  ActionChip(
                    label: Text(s),
                    onPressed: () => setState(() => _name.text = s),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Aplicada el'),
              subtitle: Text(fmt.format(_appliedOn)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: () async {
                final d = await _pick(_appliedOn);
                if (d != null) setState(() => _appliedOn = d);
              },
            ),
            const Divider(),
            Text('Próxima dosis', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final (label, months) in _shortcuts)
                  ChoiceChip(
                    label: Text(label),
                    selected: _nextDue == _addMonths(_appliedOn, months),
                    onSelected: (_) => setState(
                      () => _nextDue = _addMonths(_appliedOn, months),
                    ),
                  ),
                ChoiceChip(
                  label: const Text('Sin próxima'),
                  selected: _nextDue == null,
                  onSelected: (_) => setState(() => _nextDue = null),
                ),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _nextDue == null ? 'Sin próxima dosis' : fmt.format(_nextDue!),
              ),
              subtitle: _nextDue == null
                  ? null
                  : Text('Te avisamos 3 días antes y el mismo día · '
                      '${dueLabel(_nextDue!)}'),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: () async {
                final d = await _pick(
                  _nextDue ?? _addMonths(_appliedOn, 12),
                );
                if (d != null) setState(() => _nextDue = d);
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(
                labelText: 'Notas',
                hintText: 'Marca, lote, veterinaria…',
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _submit, child: const Text('Guardar')),
          ],
        ),
      ),
    );
  }
}
