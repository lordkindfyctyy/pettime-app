import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/caregiver.dart';
import '../models/medication.dart';
import '../models/pet.dart';
import '../models/vet_visit.dart';
import '../services/family_sync.dart';
import '../services/maps_service.dart';
import '../services/shop_settings.dart';
import '../services/vet_report.dart';
import '../state/pets_state.dart';
import '../theme.dart';
import '../widgets/caregiver_sheet.dart';
import '../widgets/diary_section.dart';
import '../widgets/expense_section.dart';
import '../widgets/family_share.dart';
import '../widgets/health_booklet.dart';
import '../widgets/medication_card.dart';
import '../widgets/pet_avatar.dart';
import '../widgets/supply_section.dart';
import '../widgets/walk_section.dart';
import '../widgets/weight_section.dart';
import 'lost_report_form_screen.dart';
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
    final now = DateTime.now();
    final caring = pet.share?.isCaregiver ?? false;
    final caregivers = caring ? const <Caregiver>[] : pet.activeCaregivers(now);
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
          PopupMenuButton<String>(
            onSelected: (action) async {
              if (action == 'family') {
                await showFamilyShareSheet(context, pet.id);
                return;
              }
              if (action == 'caregiver') {
                await showCaregiverSheet(context, pet.id);
                return;
              }
              if (action == 'lost') {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => LostReportFormScreen(pet: pet)),
                );
                return;
              }
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('¿Eliminar a ${pet.name}?'),
                  content: Text(pet.share == null
                      ? 'Se borra la ficha y su medicación.'
                      : pet.share!.isOwner
                          ? 'Se borra la ficha y su medicación, y se deja de '
                              'compartir: la familia se queda con su copia.'
                          : 'Se borra de este celular. La familia la sigue teniendo.'),
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
                if (pet.share?.isOwner ?? false) {
                  try {
                    await FamilySync.instance.stop(pet);
                  } catch (e) {
                    // Offline: the code stays on the server; the pet is
                    // deleted here anyway.
                    debugPrint('Could not stop sharing: $e');
                  }
                }
                await state.deletePet(pet.id);
                if (context.mounted) Navigator.pop(context);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'family',
                child: ListTile(
                  leading: const Icon(Icons.family_restroom),
                  title: Text(
                    caring
                        ? 'Mi cuidado'
                        : pet.share == null
                        ? 'Compartir con la familia'
                        : 'Compartida con la familia',
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (!caring)
                const PopupMenuItem(
                  value: 'caregiver',
                  child: ListTile(
                    leading: Icon(Icons.volunteer_activism_outlined),
                    title: Text('Dejar con un cuidador'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuItem(
                value: 'lost',
                child: ListTile(
                  leading: Icon(Icons.campaign_outlined),
                  title: Text('Publicar aviso: se perdió'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('Eliminar'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
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
          if (caring)
            Card(
              color: Brand.teal.withValues(alpha: 0.12),
              child: ListTile(
                leading: const Icon(Icons.volunteer_activism_outlined),
                title: Text('Cuidás a ${pet.name}'),
                subtitle: Text(
                  pet.careFinished(now)
                      ? 'El cuidado terminó'
                      : careUntilLabel(pet.careEndsAt!),
                ),
                onTap: () => showFamilyShareSheet(context, pet.id),
              ),
            ),
          for (final c in caregivers)
            Card(
              color: Brand.teal.withValues(alpha: 0.12),
              child: ListTile(
                leading: const Icon(Icons.volunteer_activism_outlined),
                title: Text('La cuida ${c.name}'),
                subtitle: Text(careUntilLabel(c.until)),
                onTap: () => showCaregiverSheet(context, pet.id),
              ),
            ),
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
                  text: 'Paseos',
                  icon: Icons.directions_walk,
                  color: Brand.teal,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Paseo'),
                onPressed: () => showWalkDialog(context, pet),
              ),
            ],
          ),
          WalkSection(pet: pet),
          const Divider(height: 32),
          Row(
            children: [
              const Expanded(
                child: SectionTitle(
                  text: 'Diario de salud',
                  icon: Icons.menu_book_outlined,
                  color: Brand.red,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Anotar'),
                onPressed: () => openDiaryForm(context, pet.id),
              ),
            ],
          ),
          DiarySection(pet: pet),
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
