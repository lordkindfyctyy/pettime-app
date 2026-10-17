class VetVisit {
  VetVisit({
    required this.id,
    required this.clinic,
    required this.date,
    this.reason = '',
    this.notes = '',
  });

  final String id;
  final String clinic;
  final DateTime date;
  final String reason;
  final String notes;

  bool get isDone => date.isBefore(DateTime.now());

  Map<String, dynamic> toJson() => {
        'id': id,
        'clinic': clinic,
        'date': date.toIso8601String(),
        'reason': reason,
        'notes': notes,
      };

  factory VetVisit.fromJson(Map<String, dynamic> json) => VetVisit(
        id: json['id'] as String,
        clinic: json['clinic'] as String,
        date: DateTime.parse(json['date'] as String),
        reason: json['reason'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
      );
}
