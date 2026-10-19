import 'caregiver.dart';
import 'diary_entry.dart';
import 'expense.dart';
import 'health_record.dart';
import 'medication.dart';
import 'pet_share.dart';
import 'supply.dart';
import 'vet_visit.dart';
import 'walk.dart';
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
    List<Walk>? walks,
    this.walkReminder,
    List<DiaryEntry>? diary,
    List<Caregiver>? caregivers,
    this.share,
  })  : medications = medications ?? [],
        visits = visits ?? [],
        records = records ?? [],
        weights = weights ?? [],
        supplies = supplies ?? [],
        expenses = expenses ?? [],
        walks = walks ?? [],
        diary = diary ?? [],
        caregivers = caregivers ?? [];

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

  /// Walks, newest first.
  final List<Walk> walks;

  /// The daily reminder when it wasn't walked, or null when off.
  final WalkReminder? walkReminder;

  /// Health diary (symptoms, notes, photos), newest first.
  final List<DiaryEntry> diary;

  /// People who look after it for a few days (see Caregiver).
  final List<Caregiver> caregivers;

  /// Set when it is shared with the family (see FamilySync).
  final PetShare? share;

  /// On a caregiver's phone: when the care ends (or ended). Null on the
  /// family's phones. A care that is no longer listed ended already.
  DateTime? get careEndsAt {
    final id = share?.caregiverId;
    if (id == null) return null;
    final c = caregivers.where((c) => c.id == id).firstOrNull;
    return c?.endsAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// This phone looked after it and that time is over.
  bool careFinished(DateTime now) {
    final end = careEndsAt;
    return end != null && !now.isBefore(end);
  }

  /// Caregivers still looking after it.
  List<Caregiver> activeCaregivers(DateTime now) =>
      caregivers.where((c) => c.isActive(now)).toList();

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
    List<Walk>? walks,
    WalkReminder? walkReminder,
    bool clearWalkReminder = false,
    List<DiaryEntry>? diary,
    List<Caregiver>? caregivers,
    PetShare? share,
    bool clearShare = false,
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
      walks: walks ?? this.walks,
      walkReminder:
          clearWalkReminder ? null : (walkReminder ?? this.walkReminder),
      diary: diary ?? this.diary,
      caregivers: caregivers ?? this.caregivers,
      share: clearShare ? null : (share ?? this.share),
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
        'walks': walks.map((w) => w.toJson()).toList(),
        if (walkReminder != null) 'walkReminder': walkReminder!.toJson(),
        'diary': diary.map((d) => d.toJson()).toList(),
        'caregivers': caregivers.map((c) => c.toJson()).toList(),
        if (share != null) 'share': share!.toJson(),
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
        walks: (json['walks'] as List? ?? [])
            .map((w) => Walk.fromJson(w as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date)),
        walkReminder: json['walkReminder'] == null
            ? null
            : WalkReminder.fromJson(json['walkReminder'] as Map<String, dynamic>),
        diary: (json['diary'] as List? ?? [])
            .map((d) => DiaryEntry.fromJson(d as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date)),
        caregivers: (json['caregivers'] as List? ?? [])
            .map((c) => Caregiver.fromJson(c as Map<String, dynamic>))
            .toList(),
        share: json['share'] == null
            ? null
            : PetShare.fromJson(json['share'] as Map<String, dynamic>),
      );
}
