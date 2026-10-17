import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/pet.dart';
import '../state/pets_state.dart';

class PetFormScreen extends StatefulWidget {
  const PetFormScreen({super.key, this.pet});

  final Pet? pet;

  @override
  State<PetFormScreen> createState() => _PetFormScreenState();
}

class _PetFormScreenState extends State<PetFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.pet?.name);
  late final _species = TextEditingController(text: widget.pet?.species);
  late final _breed = TextEditingController(text: widget.pet?.breed);
  late final _food = TextEditingController(text: widget.pet?.food);
  late final _notes = TextEditingController(text: widget.pet?.notes);
  late DateTime? _birthDate = widget.pet?.birthDate;

  @override
  void dispose() {
    _name.dispose();
    _species.dispose();
    _breed.dispose();
    _food.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? now,
      firstDate: DateTime(now.year - 40),
      lastDate: now,
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final state = context.read<PetsState>();
    final existing = widget.pet;
    final pet = (existing ?? Pet(id: state.newId(), name: '')).copyWith(
      name: _name.text.trim(),
      species: _species.text.trim(),
      breed: _breed.text.trim(),
      birthDate: _birthDate,
      food: _food.text.trim(),
      notes: _notes.text.trim(),
    );
    await state.savePet(pet);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pet == null ? 'Nueva mascota' : 'Editar ficha'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nombre'),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Ingresá un nombre' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _species,
              decoration:
                  const InputDecoration(labelText: 'Especie (perro, gato…)'),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _breed,
              decoration: const InputDecoration(labelText: 'Raza'),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fecha de nacimiento'),
              subtitle: Text(_birthDate == null
                  ? 'Sin definir'
                  : DateFormat.yMMMd('es').format(_birthDate!)),
              trailing: _birthDate == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _birthDate = null),
                    ),
              onTap: _pickBirthDate,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _food,
              decoration: const InputDecoration(
                labelText: 'Alimento',
                hintText: 'Marca, cantidad, horarios',
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
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
