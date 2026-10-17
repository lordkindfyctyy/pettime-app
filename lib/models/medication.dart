class Medication {
  Medication({
    required this.id,
    required this.name,
    this.dose = '',
    required this.everyMinutes,
    required this.startsAt,
    this.endsAt,
    this.notes = '',
    List<DateTime>? givenDoses,
  }) : givenDoses = givenDoses ?? [];

  final String id;
  final String name;
  final String dose;
  final int everyMinutes;

  /// Interval as a short Spanish label: "cada 8 h", "cada 30 min", "cada 1 h 30 min".
  String get intervalLabel {
    final h = everyMinutes ~/ 60;
    final m = everyMinutes % 60;
    if (h == 0) return 'cada $m min';
    if (m == 0) return 'cada $h h';
    return 'cada $h h $m min';
  }
  final DateTime startsAt;
  final DateTime? endsAt;
  final String notes;

  /// When each dose was actually given, oldest first.
  final List<DateTime> givenDoses;

  DateTime? get lastGiven => givenDoses.isEmpty ? null : givenDoses.last;

  /// Next dose strictly after [from], or null when the treatment has ended.
  DateTime? nextDose([DateTime? from]) =>
      doseTimeIfActive(nextDoseIndex(from ?? DateTime.now()));

  /// Doses are numbered from 0 (the first dose at [startsAt]); the number of a
  /// dose never changes, so it can identify its alarm.
  DateTime doseTime(int index) =>
      startsAt.add(Duration(minutes: everyMinutes * index));

  /// [doseTime], or null when the treatment has already ended by then.
  DateTime? doseTimeIfActive(int index) {
    final time = doseTime(index);
    return endsAt != null && time.isAfter(endsAt!) ? null : time;
  }

  /// Number of the first dose strictly after [from].
  int nextDoseIndex(DateTime from) {
    if (from.isBefore(startsAt)) return 0;
    return from.difference(startsAt).inMinutes ~/ everyMinutes + 1;
  }

  Medication copyWith({
    String? name,
    String? dose,
    int? everyMinutes,
    DateTime? startsAt,
    DateTime? endsAt,
    bool clearEndsAt = false,
    String? notes,
    List<DateTime>? givenDoses,
  }) {
    return Medication(
      id: id,
      name: name ?? this.name,
      dose: dose ?? this.dose,
      everyMinutes: everyMinutes ?? this.everyMinutes,
      startsAt: startsAt ?? this.startsAt,
      endsAt: clearEndsAt ? null : (endsAt ?? this.endsAt),
      notes: notes ?? this.notes,
      givenDoses: givenDoses ?? this.givenDoses,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'dose': dose,
        'everyMinutes': everyMinutes,
        'startsAt': startsAt.toIso8601String(),
        'endsAt': endsAt?.toIso8601String(),
        'notes': notes,
        'givenDoses': givenDoses.map((d) => d.toIso8601String()).toList(),
      };

  factory Medication.fromJson(Map<String, dynamic> json) => Medication(
        id: json['id'] as String,
        name: json['name'] as String,
        dose: json['dose'] as String? ?? '',
        // Data saved before minutes were supported only has 'everyHours'.
        everyMinutes: json['everyMinutes'] as int? ??
            (json['everyHours'] as int) * 60,
        startsAt: DateTime.parse(json['startsAt'] as String),
        endsAt: json['endsAt'] == null
            ? null
            : DateTime.parse(json['endsAt'] as String),
        notes: json['notes'] as String? ?? '',
        givenDoses: (json['givenDoses'] as List? ?? [])
            .map((d) => DateTime.parse(d as String))
            .toList(),
      );
}
