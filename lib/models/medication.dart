class Medication {
  Medication({
    required this.id,
    required this.name,
    this.dose = '',
    required this.everyHours,
    required this.startsAt,
    this.endsAt,
    this.notes = '',
  });

  final String id;
  final String name;
  final String dose;
  final int everyHours;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String notes;

  /// Next dose strictly after [from], or null when the treatment has ended.
  DateTime? nextDose([DateTime? from]) {
    final now = from ?? DateTime.now();
    final step = Duration(hours: everyHours);
    var next = startsAt;
    if (!now.isBefore(startsAt)) {
      final elapsed = now.difference(startsAt);
      next = startsAt.add(step * (elapsed.inMinutes ~/ step.inMinutes + 1));
    }
    if (endsAt != null && next.isAfter(endsAt!)) return null;
    return next;
  }

  Medication copyWith({
    String? name,
    String? dose,
    int? everyHours,
    DateTime? startsAt,
    DateTime? endsAt,
    bool clearEndsAt = false,
    String? notes,
  }) {
    return Medication(
      id: id,
      name: name ?? this.name,
      dose: dose ?? this.dose,
      everyHours: everyHours ?? this.everyHours,
      startsAt: startsAt ?? this.startsAt,
      endsAt: clearEndsAt ? null : (endsAt ?? this.endsAt),
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'dose': dose,
        'everyHours': everyHours,
        'startsAt': startsAt.toIso8601String(),
        'endsAt': endsAt?.toIso8601String(),
        'notes': notes,
      };

  factory Medication.fromJson(Map<String, dynamic> json) => Medication(
        id: json['id'] as String,
        name: json['name'] as String,
        dose: json['dose'] as String? ?? '',
        everyHours: json['everyHours'] as int,
        startsAt: DateTime.parse(json['startsAt'] as String),
        endsAt: json['endsAt'] == null
            ? null
            : DateTime.parse(json['endsAt'] as String),
        notes: json['notes'] as String? ?? '',
      );
}
