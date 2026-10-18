import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/medication.dart';
import '../models/pet.dart';
import '../models/vet_visit.dart';
import '../services/maps_service.dart';
import '../services/shop_settings.dart';
import '../services/vet_report.dart';
import '../state/pets_state.dart';
import '../theme.dart';
import '../widgets/expense_section.dart';
import '../widgets/health_booklet.dart';
import '../widgets/medication_card.dart';
import '../widgets/pet_avatar.dart';
import '../widgets/supply_section.dart';
import '../widgets/weight_section.dart';
import 'medication_form_screen.dart';
import 'pet_form_screen.dart';
import 'visit_form_screen.dart';

/// Builds the PDF for the vet and opens Android's share sheet (WhatsApp,
/// mail, Drive…).
Future<void> shareVetReport(BuildContext context, Pet pet) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Armando la ficha…')));
  try {
    final now = DateTime.now();
    final bytes = await VetReport.build(
      pet,
      assets: await VetReportAssets.load(),
      now: now,
      shopName: ShopSettings.instance.name,
    );
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${VetReport.fileName(pet, now)}');
    await file.writeAsBytes(bytes);
    messenger.hideCurrentSnackBar();
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/pdf')],
      subject: 'Ficha de ${pet.name}',
      text: 'Ficha de ${pet.name} para el veterinario, hecha con PetTime.',
    ));
  } catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text('No se pudo armar la ficha: $e')),
    );
  }
}

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
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Ficha para el veterinario',
            onPressed: () => shareVetReport(context, pet),
          ),
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
          const SectionTitle(text: 'Ficha', icon: Icons.pets, color: Brand.teal),
          const SizedBox(height: 8),
          row('Especie', pet.species),
          row('Raza', pet.breed),
          row('Edad', pet.ageLabel() ?? ''),
          row('Alimento', pet.food),
          row('Notas', pet.notes),
          const Divider(height: 32),
          Row(
            children: [
              const Expanded(
                child: SectionTitle(
                  text: 'Peso',
                  icon: Icons.monitor_weight_outlined,
                  color: Brand.teal,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Anotar peso'),
                onPressed: () => showAddWeightDialog(context, pet),
              ),
            ],
          ),
          WeightSection(pet: pet),
          const Divider(height: 32),
          Row(
            children: [
              const Expanded(
                child: SectionTitle(
                  text: 'Reposición',
                  icon: Icons.shopping_basket_outlined,
                  color: Brand.orange,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Agregar'),
                onPressed: () => openSupplyForm(context, pet.id),
              ),
            ],
          ),
          if (pet.supplies.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Cargá el alimento o los remedios y te avisamos antes de que se terminen',
              ),
            ),
          for (final s in pet.supplies) SupplyCard(pet: pet, supply: s),
          const Divider(height: 32),
          Row(
            children: [
              const Expanded(
                child: SectionTitle(
                  text: 'Gastos',
                  icon: Icons.payments_outlined,
                  color: Brand.orange,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Gasto'),
                onPressed: () => showExpenseDialog(context, pet),
              ),
            ],
          ),
          ExpenseSection(pet: pet),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: SectionTitle(
                  text: 'Medicación',
                  icon: Icons.medication_outlined,
                  color: Brand.red,
                ),
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
            MedicationCard(petId: pet.id, medication: m),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: SectionTitle(
                  text: 'Vacunas y antiparasitarios',
                  icon: Icons.vaccines_outlined,
                  color: Brand.orange,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Agregar'),
                onPressed: () => openRecordForm(context, pet.id),
              ),
            ],
          ),
          HealthBooklet(pet: pet),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: SectionTitle(
                  text: 'Turnos',
                  icon: Icons.event_outlined,
                  color: Brand.teal,
                ),
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
