import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_lang.dart';
import '../models/medication.dart';
import '../screens/medication_form_screen.dart';
import '../state/pets_state.dart';
import 'confirm_delete.dart';
import 'dose_history_sheet.dart';

/// One medication in the pet's profile: the photo of the medicine on top, the
/// description below, and the actions at the bottom.
class MedicationCard extends StatelessWidget {
  const MedicationCard({super.key, required this.petId, required this.medication});

  final String petId;
  final Medication medication;

  void _edit(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MedicationFormScreen(petId: petId, medication: medication),
      ),
    );
  }

  void _showHistory(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DoseHistorySheet(petId: petId, medId: medication.id),
    );
  }

  void _showPhoto(BuildContext context, String path) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                medication.name,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            Flexible(child: InteractiveViewer(child: Image.file(File(path)))),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('Cerrar')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logDose(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await context.read<PetsState>().logDose(petId, medication.id);
    messenger.showSnackBar(
      SnackBar(
        content: Text(tr('Toma de {name} registrada', {'name': medication.name})),
        action: SnackBarAction(
          label: tr('Historial'),
          onPressed: () => _showHistory(context),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = medication;
    final fmt = DateFormat.yMMMd(AppLang.code).add_Hm();
    final next = m.nextDose();
    final photo = m.photoPath;
    final hasPhoto = photo != null && File(photo).existsSync();

    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(child: Text(text)),
            ],
          ),
        );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _edit(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasPhoto)
              GestureDetector(
                onTap: () => _showPhoto(context, photo),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.file(File(photo), fit: BoxFit.cover),
                ),
              )
            else
              Container(
                height: 72,
                color: theme.colorScheme.secondaryContainer,
                child: Icon(
                  Icons.medication_outlined,
                  size: 36,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.name, style: theme.textTheme.titleLarge),
                  if (m.dose.isNotEmpty)
                    Text(m.dose, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 4),
                  line(Icons.repeat, m.intervalLabel),
                  line(
                    next == null ? Icons.event_busy_outlined : Icons.alarm,
                    next == null
                        ? tr('Tratamiento terminado')
                        : tr('Próxima toma: {n}', {'n': fmt.format(next)}),
                  ),
                  if (m.lastGiven != null)
                    line(
                      Icons.check_circle_outline,
                      tr('Última dada: {n}', {'n': fmt.format(m.lastGiven!)}),
                    ),
                  if (m.endsAt != null)
                    line(Icons.flag_outlined, tr('Hasta: {n}', {'n': fmt.format(m.endsAt!)})),
                  if (m.notes.isNotEmpty) line(Icons.notes, m.notes),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.check),
                    label: Text(tr('Dada ahora')),
                    onPressed: () => _logDose(context),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.history),
                    label: Text(tr('Historial')),
                    onPressed: () => _showHistory(context),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: tr('Eliminar medicación'),
                    onPressed: () async {
                      final state = context.read<PetsState>();
                      if (await confirmDelete(
                        context,
                        tr('la medicación {name}', {'name': m.name}),
                        detail: tr('Se borran también sus alarmas y el historial de tomas. No se puede deshacer.'),
                      )) {
                        await state.deleteMedication(petId, m.id);
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
