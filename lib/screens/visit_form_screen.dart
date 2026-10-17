import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/vet_visit.dart';
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
  late DateTime _date = widget.visit?.date ?? DateTime.now();

  @override
  void dispose() {
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
        title: Text(widget.visit == null ? 'Nueva visita' : 'Editar visita'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _clinic,
              decoration: const InputDecoration(labelText: 'Veterinaria'),
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Ingresá la veterinaria'
                  : null,
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fecha y hora'),
              subtitle: Text(DateFormat.yMMMd('es').add_Hm().format(_date)),
              onTap: _pickDate,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _reason,
              decoration: const InputDecoration(
                labelText: 'Motivo',
                hintText: 'Control, vacuna, cirugía…',
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notas'),
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
