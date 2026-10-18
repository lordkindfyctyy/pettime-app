import 'expense.dart';
import 'health_record.dart';
import 'medication.dart';
import 'supply.dart';
import 'vet_visit.dart';
import 'weight_entry.dart';

class Pet {
  Pet({
    required this.id,
    required this.name,
    this.species = '',
    this.breed = '',
    this.birthDate,
    this.food = '',
    this.notes = '',
    this.photoPath,
    List<Medication>? medications,
    List<VetVisit>? visits,
    List<HealthRecord>? records,
    List<WeightEntry>? weights,
    List<Supply>? supplies,
    List<Expense>? expenses,
  })  : medications = medications ?? [],
        visits = visits ?? [],
        records = records ?? [],
        weights = weights ?? [],
        supplies = supplies ?? [],
        expenses = expenses ?? [];

  final String id;
  final String name;
  final String species;
  final String breed;
  final DateTime? birthDate;
  final String food;
  final String notes;

  /// Absolute path of the photo inside the app's own storage, if any.
  final String? photoPath;
  final List<Medication> medications;
  final List<VetVisit> visits;

  /// Health booklet: vaccines and antiparasitics applied.
  final List<HealthRecord> records;

  /// Weighings, oldest first.
  final List<WeightEntry> weights;

  /// The latest weighing, or null when it was never weighed.
  WeightEntry? get currentWeight => weights.isEmpty ? null : weights.last;

  /// Food, medicines… that run out and have to be bought again.
  final List<Supply> supplies;

  /// Money spent on it, newest first.
  final List<Expense> expenses;

  /// Age as a short Spanish label, or null when the birth date is unknown.
  String? ageLabel([DateTime? now]) {
    final b = birthDate;
    if (b == null) return null;
    final today = now ?? DateTime.now();
    var months = (today.year - b.year) * 12 + today.month - b.month;
    if (today.day < b.day) months--;
    if (months < 0) months = 0;
    final years = months ~/ 12;
    final rest = months % 12;
    if (years == 0) return rest == 1 ? '1 mes' : '$rest meses';
    final y = years == 1 ? '1 año' : '$years años';
    if (rest == 0) return y;
    return '$y y ${rest == 1 ? '1 mes' : '$rest meses'}';
  }

  Pet copyWith({
    String? name,
    String? species,
    String? breed,
    DateTime? birthDate,
    bool clearBirthDate = false,
    String? food,
    String? notes,
    String? photoPath,
    bool clearPhoto = false,
    List<Medication>? medications,
    List<VetVisit>? visits,
    List<HealthRecord>? records,
    List<WeightEntry>? weights,
    List<Supply>? supplies,
    List<Expense>? expenses,
  }) {
    return Pet(
      id: id,
      name: name ?? this.name,
      species: species ?? this.species,
      breed: breed ?? this.breed,
      birthDate: clearBirthDate ? null : (birthDate ?? this.birthDate),
      food: food ?? this.food,
      notes: notes ?? this.notes,
      photoPath: clearPhoto ? null : (photoPath ?? this.photoPath),
      medications: medications ?? this.medications,
      visits: visits ?? this.visits,
      records: records ?? this.records,
      weights: weights ?? this.weights,
      supplies: supplies ?? this.supplies,
      expenses: expenses ?? this.expenses,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'species': species,
        'breed': breed,
        'birthDate': birthDate?.toIso8601String(),
        'food': food,
        'notes': notes,
        'photoPath': photoPath,
        'medications': medications.map((m) => m.toJson()).toList(),
        'visits': visits.map((v) => v.toJson()).toList(),
        'records': records.map((r) => r.toJson()).toList(),
        'weights': weights.map((w) => w.toJson()).toList(),
        'supplies': supplies.map((s) => s.toJson()).toList(),
        'expenses': expenses.map((e) => e.toJson()).toList(),
      };

  factory Pet.fromJson(Map<String, dynamic> json) => Pet(
        id: json['id'] as String,
        name: json['name'] as String,
        species: json['species'] as String? ?? '',
        breed: json['breed'] as String? ?? '',
        birthDate: json['birthDate'] == null
            ? null
            : DateTime.parse(json['birthDate'] as String),
        food: json['food'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        photoPath: json['photoPath'] as String?,
        medications: (json['medications'] as List? ?? [])
            .map((m) => Medication.fromJson(m as Map<String, dynamic>))
            .toList(),
        visits: (json['visits'] as List? ?? [])
            .map((v) => VetVisit.fromJson(v as Map<String, dynamic>))
            .toList(),
        records: (json['records'] as List? ?? [])
            .map((r) => HealthRecord.fromJson(r as Map<String, dynamic>))
            .toList(),
        weights: (json['weights'] as List? ?? [])
            .map((w) => WeightEntry.fromJson(w as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date)),
        supplies: (json['supplies'] as List? ?? [])
            .map((s) => Supply.fromJson(s as Map<String, dynamic>))
            .toList(),
        expenses: (json['expenses'] as List? ?? [])
            .map((e) => Expense.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date)),
      );
}
