import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/medication.dart';
import '../state/pets_state.dart';
import 'medication_form_screen.dart';
import 'pet_form_screen.dart';

class PetDetailScreen extends StatelessWidget {
  const PetDetailScreen({super.key, required this.petId});

  final String petId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PetsState>();
    final pet = state.byId(petId);
    if (pet == null) return const Scaffold(body: SizedBox.shrink());

    final theme = Theme.of(context);
    final fmt = DateFormat.yMMMd('es').add_Hm();

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Text(label, style: theme.textTheme.labelLarge),
              ),
              Expanded(child: Text(value.isEmpty ? '—' : value)),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(pet.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Editar ficha',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PetFormScreen(pet: pet)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Eliminar',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('¿Eliminar a ${pet.name}?'),
                  content: const Text('Se borra la ficha y su medicación.'),
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
              if (ok == true && context.mounted) {
                await state.deletePet(pet.id);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Ficha', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          row('Especie', pet.species),
          row('Raza', pet.breed),
          row('Edad', pet.ageLabel() ?? ''),
          row('Alimento', pet.food),
          row('Notas', pet.notes),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: Text('Medicación', style: theme.textTheme.titleMedium),
              ),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Agregar'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MedicationFormScreen(petId: pet.id),
                  ),
                ),
              ),
            ],
          ),
          if (pet.medications.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Sin medicación cargada'),
            ),
          for (final Medication m in pet.medications)
            Card(
              child: ListTile(
                title: Text(m.name),
                subtitle: Text([
                  if (m.dose.isNotEmpty) m.dose,
                  'cada ${m.everyHours} h',
                  m.nextDose() == null
                      ? 'tratamiento terminado'
                      : 'próxima: ${fmt.format(m.nextDose()!)}',
                ].join(' · ')),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        MedicationFormScreen(petId: pet.id, medication: m),
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Eliminar medicación',
                  onPressed: () => state.deleteMedication(pet.id, m.id),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
