import '../l10n/app_lang.dart';
enum HealthKind {
  vaccine('Vacuna', 'Antirrábica, séxtuple, triple felina…'),
  deworming('Desparasitario interno', 'Pastilla o jarabe para parásitos internos'),
  fleaTick('Pulgas y garrapatas', 'Pipeta, collar o pastilla');

  const HealthKind(this._label, this._hint);

  final String _label;
  final String _hint;

  String get label => tr(_label);
  String get hint => tr(_hint);

  /// Common names offered as shortcuts in the form.
  List<String> get suggestions => switch (this) {
        HealthKind.vaccine => [
            tr('Antirrábica'),
            tr('Séxtuple'),
            tr('Quíntuple'),
            tr('Triple felina'),
            tr('Leucemia felina'),
            tr('Tos de las perreras'),
          ],
        HealthKind.deworming => [tr('Desparasitario interno')],
        HealthKind.fleaTick => [tr('Pipeta'), tr('Collar'), tr('Pastilla antipulgas')],
      };
}

/// One entry of the pet's health booklet: a vaccine or an antiparasitic that
/// was applied, and optionally when the next one is due.
class HealthRecord {
  HealthRecord({
    required this.id,
    required this.kind,
    required this.name,
    required this.appliedOn,
    this.nextDue,
    this.notes = '',
  });

  final String id;
  final HealthKind kind;
  final String name;
  final DateTime appliedOn;

  /// When the next application is due, or null when none is planned.
  final DateTime? nextDue;
  final String notes;

  /// Records of the same thing (kind and name, ignoring case), so a newer one
  /// replaces the reminder of an older one.
  bool sameAs(HealthRecord other) =>
      kind == other.kind &&
      name.trim().toLowerCase() == other.name.trim().toLowerCase();

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        'appliedOn': appliedOn.toIso8601String(),
        'nextDue': nextDue?.toIso8601String(),
        'notes': notes,
      };

  factory HealthRecord.fromJson(Map<String, dynamic> json) => HealthRecord(
        id: json['id'] as String,
        kind: HealthKind.values.asNameMap()[json['kind']] ?? HealthKind.vaccine,
        name: json['name'] as String,
        appliedOn: DateTime.parse(json['appliedOn'] as String),
        nextDue: json['nextDue'] == null
            ? null
            : DateTime.parse(json['nextDue'] as String),
        notes: json['notes'] as String? ?? '',
      );
}

/// Records whose next application is still pending: the latest one of each
/// vaccine or antiparasitic that has a due date. Older applications of the
/// same thing don't count (the newer one replaced them).
List<HealthRecord> pendingRecords(List<HealthRecord> records) {
  final latest = <HealthRecord>[];
  for (final r in records) {
    final i = latest.indexWhere((l) => l.sameAs(r));
    if (i == -1) {
      latest.add(r);
    } else if (r.appliedOn.isAfter(latest[i].appliedOn)) {
      latest[i] = r;
    }
  }
  return latest.where((r) => r.nextDue != null).toList()
    ..sort((a, b) => a.nextDue!.compareTo(b.nextDue!));
}

/// Days from [now] (by calendar date) until [date]; negative when overdue.
int daysUntil(DateTime date, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(date.year, date.month, date.day);
  return (day.difference(today).inHours / 24).round();
}

/// "Hoy", "Mañana", "En 5 días", "Vencida hace 2 días".
String dueLabel(DateTime date, [DateTime? now]) {
  final d = daysUntil(date, now);
  if (d == 0) return tr('Hoy');
  if (d == 1) return tr('Mañana');
  if (d > 1) return tr('En {d} días', {'d': d});
  if (d == -1) return tr('Vencida ayer');
  return tr('Vencida hace {n} días', {'n': -d});
}
