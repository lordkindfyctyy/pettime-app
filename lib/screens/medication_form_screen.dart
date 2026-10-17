import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/medication.dart';
import '../services/notification_service.dart';
import '../state/pets_state.dart';

class MedicationFormScreen extends StatefulWidget {
  const MedicationFormScreen({super.key, required this.petId, this.medication});

  final String petId;
  final Medication? medication;

  @override
  State<MedicationFormScreen> createState() => _MedicationFormScreenState();
}

class _MedicationFormScreenState extends State<MedicationFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.medication?.name);
  late final _dose = TextEditingController(text: widget.medication?.dose);
  // The interval is entered as an amount plus a unit, shown in hours when it
  // is a whole number of hours and in minutes otherwise.
  late bool _inHours = (widget.medication?.everyMinutes ?? 60) % 60 == 0;
  late final _interval = TextEditingController(
    text: widget.medication == null
        ? ''
        : (_inHours
                ? widget.medication!.everyMinutes ~/ 60
                : widget.medication!.everyMinutes)
            .toString(),
  );
  late final _notes = TextEditingController(text: widget.medication?.notes);
  late DateTime _startsAt = widget.medication?.startsAt ?? DateTime.now();
  late DateTime? _endsAt = widget.medication?.endsAt;

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    _interval.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final state = context.read<PetsState>();
    final med = Medication(
      id: widget.medication?.id ?? state.newId(),
      name: _name.text.trim(),
      dose: _dose.text.trim(),
      everyMinutes: int.parse(_interval.text.trim()) * (_inHours ? 60 : 1),
      startsAt: _startsAt,
      endsAt: _endsAt,
      notes: _notes.text.trim(),
      givenDoses: widget.medication?.givenDoses,
    );
    await NotificationService.instance.requestPermission();
    await state.saveMedication(widget.petId, med);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat.yMMMd('es').add_Hm();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.medication == null ? 'Nueva medicación' : 'Editar medicación',
        ),
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
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Medicamento'),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Ingresá el medicamento'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _dose,
              decoration: const InputDecoration(
                labelText: 'Dosis',
                hintText: '1 comprimido, 2 ml…',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _interval,
                    decoration: const InputDecoration(labelText: 'Repetir cada'),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final n = int.tryParse(v?.trim() ?? '');
                      return (n == null || n < 1) ? 'Ingresá un número' : null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('min')),
                    ButtonSegment(value: true, label: Text('horas')),
                  ],
                  selected: {_inHours},
                  onSelectionChanged: (s) => setState(() => _inHours = s.first),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Primera toma'),
              subtitle: Text(fmt.format(_startsAt)),
              onTap: () async {
                final d = await _pickDateTime(_startsAt);
                if (d != null) setState(() => _startsAt = d);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fin del tratamiento'),
              subtitle: Text(_endsAt == null ? 'Sin fecha' : fmt.format(_endsAt!)),
              trailing: _endsAt == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _endsAt = null),
                    ),
              onTap: () async {
                final d = await _pickDateTime(_endsAt ?? _startsAt);
                if (d != null) setState(() => _endsAt = d);
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notas'),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _submit, child: const Text('Guardar')),
          ],
        ),
      ),
    );
  }
}
