import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_lang.dart';
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
import '../widgets/confirm_delete.dart';
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
import 'pet_tag_screen.dart';
import 'visit_form_screen.dart';

/// Builds the PDF for the vet and opens Android's share sheet (WhatsApp,
/// mail, Drive…).
Future<void> shareVetReport(BuildContext context, Pet pet) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(SnackBar(content: Text(tr('Armando la ficha…'))));
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
      subject: tr('Ficha de {name}', {'name': pet.name}),
      text: tr('Ficha de {name} para el veterinario, hecha con PetTime.', {'name': pet.name}),
    ));
  } catch (e) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(tr('No se pudo armar la ficha: {e}', {'e': e}))),
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
    final fmt = DateFormat.yMMMd(AppLang.code).add_Hm();
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
            tooltip: tr('Ficha para el veterinario'),
            onPressed: () => shareVetReport(context, pet),
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: tr('Editar ficha'),
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
              if (action == 'tag') {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => PetTagScreen(petId: pet.id)),
                );
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
                  title: Text(tr('¿Eliminar a {name}?', {'name': pet.name})),
                  content: Text(pet.share == null
                      ? tr('Se borra la ficha y su medicación.')
                      : pet.share!.isOwner
                          ? tr('Se borra la ficha y su medicación, y se deja de compartir: la familia se queda con su copia.')
                          : tr('Se borra de este celular. La familia la sigue teniendo.')),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(tr('Cancelar')),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(tr('Eliminar')),
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
                        ? tr('Mi cuidado')
                        : pet.share == null
                        ? tr('Compartir con la familia')
                        : tr('Compartida con la familia'),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (!caring)
                PopupMenuItem(
                  value: 'caregiver',
                  child: ListTile(
                    leading: Icon(Icons.volunteer_activism_outlined),
                    title: Text(tr('Dejar con un cuidador')),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              PopupMenuItem(
                value: 'lost',
                child: ListTile(
                  leading: Icon(Icons.campaign_outlined),
                  title: Text(tr('Publicar aviso: se perdió')),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text(tr('Eliminar')),
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
                title: Text(tr('Cuidás a {name}', {'name': pet.name})),
                subtitle: Text(
                  pet.careFinished(now)
                      ? tr('El cuidado terminó')
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
                title: Text(tr('La cuida {name}', {'name': c.name})),
                subtitle: Text(careUntilLabel(c.until)),
                onTap: () => showCaregiverSheet(context, pet.id),
              ),
            ),
          Center(child: PetAvatar(pet: pet, radius: 56)),
          const SizedBox(height: 16),
          SectionTitle(text: tr('Ficha'), icon: Icons.pets, color: Brand.teal),
          const SizedBox(height: 8),
          row(tr('Especie'), pet.species),
          row(tr('Raza'), pet.breed),
          row(tr('Edad'), pet.ageLabel() ?? ''),
          row(tr('Alimento'), pet.food),
          row(tr('Notas'), pet.notes),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: SectionTitle(
                  text: tr('Peso'),
                  icon: Icons.monitor_weight_outlined,
                  color: Brand.teal,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: Text(tr('Anotar peso')),
                onPressed: () => showAddWeightDialog(context, pet),
              ),
            ],
          ),
          WeightSection(pet: pet),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: SectionTitle(
                  text: tr('Paseos'),
                  icon: Icons.directions_walk,
                  color: Brand.teal,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: Text(tr('Paseo')),
                onPressed: () => showWalkDialog(context, pet),
              ),
            ],
          ),
          WalkSection(pet: pet),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: SectionTitle(
                  text: tr('Diario de salud'),
                  icon: Icons.menu_book_outlined,
                  color: Brand.red,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: Text(tr('Anotar')),
                onPressed: () => openDiaryForm(context, pet.id),
              ),
            ],
          ),
          DiarySection(pet: pet),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: SectionTitle(
                  text: tr('Reposición'),
                  icon: Icons.shopping_basket_outlined,
                  color: Brand.orange,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: Text(tr('Agregar')),
                onPressed: () => openSupplyForm(context, pet.id),
              ),
            ],
          ),
          if (pet.supplies.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                tr('Cargá el alimento o los remedios y te avisamos antes de que se terminen'),
              ),
            ),
          for (final s in pet.supplies) SupplyCard(pet: pet, supply: s),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: SectionTitle(
                  text: tr('Gastos'),
                  icon: Icons.payments_outlined,
                  color: Brand.orange,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: Text(tr('Gasto')),
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
                  text: tr('Medicación'),
                  icon: Icons.medication_outlined,
                  color: Brand.red,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: Text(tr('Agregar')),
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
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(tr('Sin medicación cargada')),
            ),
          for (final Medication m in pet.medications)
            MedicationCard(petId: pet.id, medication: m),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: SectionTitle(
                  text: tr('Vacunas y antiparasitarios'),
                  icon: Icons.vaccines_outlined,
                  color: Brand.orange,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: Text(tr('Agregar')),
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
                  text: tr('Turnos'),
                  icon: Icons.event_outlined,
                  color: Brand.teal,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: Text(tr('Turno')),
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
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(tr('Sin turnos registrados')),
            ),
          for (final (label, list) in [
            (tr('Próximas'), upcoming),
            (tr('Anteriores'), past),
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
                          tooltip: tr('Ver en Google Maps'),
                          onPressed: () => openInMaps(context, v.mapsUri),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: tr('Eliminar turno'),
                          onPressed: () async {
                            if (await confirmDelete(
                              context,
                              tr('el turno de {toLowerCase} {clinic} del {n}', {'toLowerCase': v.kind.placeLabel.toLowerCase(), 'clinic': v.clinic, 'n': fmt.format(v.date)}),
                            )) {
                              await state.deleteVisit(pet.id, v.id);
                            }
                          },
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
