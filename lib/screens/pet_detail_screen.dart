import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/medication.dart';
import '../models/vet_visit.dart';
import '../services/maps_service.dart';
import '../state/pets_state.dart';
import '../widgets/dose_history_sheet.dart';
import '../widgets/medication_photo.dart';
import '../widgets/pet_avatar.dart';
import 'medication_form_screen.dart';
import 'pet_form_screen.dart';
import 'visit_form_screen.dart';

class PetDetailScreen extends StatelessWidget {
  const PetDetailScreen({super.key, required this.petId});

  final String petId;

  void _showPhoto(BuildContext context, String title, String path) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
            ),
            Flexible(child: Image.file(File(path))),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      ),
    );
  }

  void _showHistory(BuildContext context, String petId, String medId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DoseHistorySheet(petId: petId, medId: medId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PetsState>();
    final pet = state.byId(petId);
    if (pet == null) return const Scaffold(body: SizedBox.shrink());

    final theme = Theme.of(context);
    final fmt = DateFormat.yMMMd('es').add_Hm();
    // Upcoming soonest first; past most recent first.
    final upcoming = pet.visits.where((v) => !v.isDone).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final past = pet.visits.where((v) => v.isDone).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

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
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
          Center(child: PetAvatar(pet: pet, radius: 56)),
          const SizedBox(height: 16),
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
                leading: GestureDetector(
                  onTap: m.photoPath == null
                      ? null
                      : () => _showPhoto(context, m.name, m.photoPath!),
                  child: MedicationPhoto(path: m.photoPath),
                ),
                title: Text(m.name),
                subtitle: Text([
                  if (m.dose.isNotEmpty) m.dose,
                  m.intervalLabel,
                  m.nextDose() == null
                      ? 'tratamiento terminado'
                      : 'próxima: ${fmt.format(m.nextDose()!)}',
                  if (m.lastGiven != null) 'última dada: ${fmt.format(m.lastGiven!)}',
                ].join(' · ')),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        MedicationFormScreen(petId: pet.id, medication: m),
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.check_circle),
                      tooltip: 'Registrar toma dada ahora',
                      onPressed: () async {
                        await state.logDose(pet.id, m.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Toma de ${m.name} registrada'),
                              action: SnackBarAction(
                                label: 'Historial',
                                onPressed: () => _showHistory(context, pet.id, m.id),
                              ),
                            ),
                          );
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.history),
                      tooltip: 'Historial de tomas',
                      onPressed: () => _showHistory(context, pet.id, m.id),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Eliminar medicación',
                      onPressed: () => state.deleteMedication(pet.id, m.id),
                    ),
                  ],
                ),
              ),
            ),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: Text('Turnos', style: theme.textTheme.titleMedium),
              ),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Turno'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VisitFormScreen(petId: pet.id),
                  ),
                ),
              ),
            ],
          ),
          if (pet.visits.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Sin turnos registrados'),
            ),
          for (final (label, list) in [
            ('Próximas', upcoming),
            ('Anteriores', past),
          ])
            if (list.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(label, style: theme.textTheme.labelLarge),
              ),
              for (final VetVisit v in list)
                Card(
                  child: ListTile(
                    leading: Icon(
                      v.kind == AppointmentKind.vet
                          ? Icons.local_hospital_outlined
                          : Icons.content_cut,
                    ),
                    title: Text('${v.kind.placeLabel}: ${v.clinic}'),
                    subtitle: Text([
                      fmt.format(v.date),
                      if (v.reason.isNotEmpty) v.reason,
                      if (v.address.isNotEmpty && !v.address.startsWith('http'))
                        v.address,
                    ].join(' · ')),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            VisitFormScreen(petId: pet.id, visit: v),
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.map_outlined),
                          tooltip: 'Ver en Google Maps',
                          onPressed: () => openInMaps(context, v.mapsUri),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Eliminar turno',
                          onPressed: () => state.deleteVisit(pet.id, v.id),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
        ],
      ),
    );
  }
}
