import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_lang.dart';
import '../models/vet_visit.dart';
import '../services/maps_service.dart';
import '../state/pets_state.dart';

class VisitFormScreen extends StatefulWidget {
  const VisitFormScreen({super.key, required this.petId, this.visit});

  final String petId;
  final VetVisit? visit;

  @override
  State<VisitFormScreen> createState() => _VisitFormScreenState();
}

class _VisitFormScreenState extends State<VisitFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _clinic = TextEditingController(text: widget.visit?.clinic);
  late final _reason = TextEditingController(text: widget.visit?.reason);
  late final _notes = TextEditingController(text: widget.visit?.notes);
  late final _address = TextEditingController(text: widget.visit?.address);
  late DateTime _date = widget.visit?.date ?? DateTime.now();
  late AppointmentKind _kind = widget.visit?.kind ?? AppointmentKind.vet;

  /// The appointment as currently typed, to build the Maps link from.
  VetVisit get _draft => VetVisit(
        id: widget.visit?.id ?? '',
        clinic: _clinic.text,
        date: _date,
        kind: _kind,
        address: _address.text,
      );

  @override
  void dispose() {
    _address.dispose();
    _clinic.dispose();
    _reason.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 20)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    if (time == null) return;
    setState(() {
      _date = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final state = context.read<PetsState>();
    await state.saveVisit(
      widget.petId,
      VetVisit(
        id: widget.visit?.id ?? state.newId(),
        clinic: _clinic.text.trim(),
        date: _date,
        kind: _kind,
        address: _address.text.trim(),
        reason: _reason.text.trim(),
        notes: _notes.text.trim(),
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.visit == null ? tr('Nuevo turno') : tr('Editar turno')),
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
            SegmentedButton<AppointmentKind>(
              segments: [
                for (final k in AppointmentKind.values)
                  ButtonSegment(value: k, label: Text(k.label)),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _clinic,
              decoration: InputDecoration(labelText: _kind.placeLabel),
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? tr('Ingresá el nombre del lugar')
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              decoration: InputDecoration(
                labelText: tr('Dirección o link de Google Maps'),
                hintText: tr('Calle y número, o pegá el link del lugar'),
              ),
              keyboardType: TextInputType.streetAddress,
              textCapitalization: TextCapitalization.sentences,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.map_outlined),
                label: Text(tr('Ver en Google Maps')),
                onPressed: () => openInMaps(context, _draft.mapsUri),
              ),
            ),
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Fecha y hora')),
              subtitle: Text(DateFormat.yMMMd(AppLang.code).add_Hm().format(_date)),
              onTap: _pickDate,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _reason,
              decoration: InputDecoration(
                labelText: tr('Motivo'),
                hintText: tr('Control, vacuna, baño y corte…'),
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              decoration: InputDecoration(labelText: tr('Notas')),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _submit, child: Text(tr('Guardar'))),
          ],
        ),
      ),
    );
  }
}
