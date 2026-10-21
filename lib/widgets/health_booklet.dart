import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_lang.dart';
import '../models/health_record.dart';
import '../models/pet.dart';
import '../screens/health_record_form_screen.dart';

IconData healthIcon(HealthKind kind) => switch (kind) {
      HealthKind.vaccine => Icons.vaccines_outlined,
      HealthKind.deworming => Icons.medication_liquid_outlined,
      HealthKind.fleaTick => Icons.bug_report_outlined,
    };

/// Color of the "next dose" label: red when overdue, orange within a week.
Color dueColor(BuildContext context, DateTime due) {
  final d = daysUntil(due);
  final scheme = Theme.of(context).colorScheme;
  if (d < 0) return scheme.error;
  if (d <= 7) return Colors.orange.shade800;
  return scheme.onSurfaceVariant;
}

void openRecordForm(
  BuildContext context,
  String petId, {
  HealthRecord? record,
  HealthRecord? repeatOf,
}) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => HealthRecordFormScreen(
        petId: petId,
        record: record,
        repeatOf: repeatOf,
      ),
    ),
  );
}

/// The pet's health booklet in its profile: every application, newest first.
/// The ones still pending show when the next dose is due and a button to
/// register that it was applied again.
class HealthBooklet extends StatelessWidget {
  const HealthBooklet({super.key, required this.pet});

  final Pet pet;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat.yMMMd(AppLang.code);
    final pending = pendingRecords(pet.records);
    final records = [...pet.records]
      ..sort((a, b) => b.appliedOn.compareTo(a.appliedOn));

    if (records.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(tr('Sin vacunas ni antiparasitarios cargados')),
      );
    }
    return Column(
      children: [
        for (final r in records)
          Card(
            child: ListTile(
              leading: Icon(healthIcon(r.kind)),
              title: Text(r.name),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('{label} · aplicada {n}', {'label': r.kind.label, 'n': fmt.format(r.appliedOn)})),
                  if (pending.contains(r))
                    Text(
                      tr('Próxima: {n} · {n2}', {'n': fmt.format(r.nextDue!), 'n2': dueLabel(r.nextDue!)}),
                      style: TextStyle(
                        color: dueColor(context, r.nextDue!),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              isThreeLine: pending.contains(r),
              onTap: () => openRecordForm(context, pet.id, record: r),
              trailing: pending.contains(r)
                  ? IconButton(
                      icon: const Icon(Icons.check_circle_outline),
                      tooltip: tr('Registrar que se aplicó'),
                      onPressed: () =>
                          openRecordForm(context, pet.id, repeatOf: r),
                    )
                  : null,
            ),
          ),
      ],
    );
  }
}
