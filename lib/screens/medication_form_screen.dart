import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_lang.dart';
import '../models/medication.dart';
import '../services/notification_service.dart';
import '../services/photo_service.dart';
import '../state/pets_state.dart';
import '../widgets/medication_photo.dart';
import '../widgets/photo_source_sheet.dart';

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
  late final String _medId =
      widget.medication?.id ?? context.read<PetsState>().newId();
  late String? _photoPath = widget.medication?.photoPath;
  bool _saved = false;

  Future<void> _choosePhoto() async {
    final choice = await showPhotoSourceSheet(context, hasPhoto: _photoPath != null);
    switch (choice) {
      case PickPhoto(:final source):
        final path = await PhotoService.instance.pick(source, _medId);
        if (path == null || !mounted) return;
        await _dropUnsavedPhoto();
        setState(() => _photoPath = path);
      case RemovePhoto():
        await _dropUnsavedPhoto();
        setState(() => _photoPath = null);
      case null:
        break;
    }
  }

  /// A photo picked in this form and replaced again before saving is never used.
  Future<void> _dropUnsavedPhoto() async {
    if (_photoPath != widget.medication?.photoPath) {
      await PhotoService.instance.delete(_photoPath);
    }
  }

  @override
  void dispose() {
    // Left without saving: drop a photo that was picked but never kept.
    if (!_saved && _photoPath != widget.medication?.photoPath) {
      PhotoService.instance.delete(_photoPath);
    }
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
      id: _medId,
      name: _name.text.trim(),
      dose: _dose.text.trim(),
      everyMinutes: int.parse(_interval.text.trim()) * (_inHours ? 60 : 1),
      startsAt: _startsAt,
      endsAt: _endsAt,
      notes: _notes.text.trim(),
      photoPath: _photoPath,
      givenDoses: widget.medication?.givenDoses,
    );
    _saved = true;
    if (widget.medication?.photoPath != _photoPath) {
      await PhotoService.instance.delete(widget.medication?.photoPath);
    }
    await NotificationService.instance.requestPermission();
    await state.saveMedication(widget.petId, med);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat.yMMMd(AppLang.code).add_Hm();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.medication == null ? tr('Nueva medicación') : tr('Editar medicación'),
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
            Center(
              child: GestureDetector(
                onTap: _choosePhoto,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    MedicationPhoto(path: _photoPath, size: 96),
                    const CircleAvatar(
                      radius: 14,
                      child: Icon(Icons.photo_camera, size: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              decoration: InputDecoration(labelText: tr('Medicamento')),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? tr('Ingresá el medicamento')
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _dose,
              decoration: InputDecoration(
                labelText: tr('Dosis'),
                hintText: tr('1 comprimido, 2 ml…'),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _interval,
                    decoration: InputDecoration(labelText: tr('Repetir cada')),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final n = int.tryParse(v?.trim() ?? '');
                      return (n == null || n < 1) ? tr('Ingresá un número') : null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, label: Text(tr('min'))),
                    ButtonSegment(value: true, label: Text(tr('horas'))),
                  ],
                  selected: {_inHours},
                  onSelectionChanged: (s) => setState(() => _inHours = s.first),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Primera toma')),
              subtitle: Text(fmt.format(_startsAt)),
              onTap: () async {
                final d = await _pickDateTime(_startsAt);
                if (d != null) setState(() => _startsAt = d);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Fin del tratamiento')),
              subtitle: Text(_endsAt == null ? tr('Sin fecha') : fmt.format(_endsAt!)),
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
              decoration: InputDecoration(labelText: tr('Notas')),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _submit, child: Text(tr('Guardar'))),
          ],
        ),
      ),
    );
  }
}
