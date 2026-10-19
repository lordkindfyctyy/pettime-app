/// What can be ticked in the diary instead of writing it.
enum Symptom {
  vomit('Vómitos'),
  diarrhea('Diarrea'),
  noAppetite('No come'),
  lethargy('Decaído'),
  cough('Tos'),
  sneeze('Estornudos'),
  itching('Picazón'),
  limping('Renguea'),
  wound('Herida'),
  drinksMuch('Toma mucha agua');

  const Symptom(this.label);

  final String label;

  static Symptom? byName(String name) {
    for (final s in values) {
      if (s.name == name) return s;
    }
    return null;
  }
}

/// One entry of the pet's health diary: what was seen that day (symptoms,
/// notes and photos), to show the vet.
class DiaryEntry {
  DiaryEntry({
    required this.id,
    required this.date,
    this.symptoms = const [],
    this.text = '',
    this.photos = const [],
  });

  final String id;
  final DateTime date;
  final List<Symptom> symptoms;
  final String text;

  /// Absolute paths of the photos inside the app's own storage. They stay on
  /// this phone: they are not sent to the family.
  final List<String> photos;

  /// "Vómitos, Decaído".
  String get symptomsLabel => symptoms.map((s) => s.label).join(', ');

  DiaryEntry copyWith({
    DateTime? date,
    List<Symptom>? symptoms,
    String? text,
    List<String>? photos,
  }) => DiaryEntry(
    id: id,
    date: date ?? this.date,
    symptoms: symptoms ?? this.symptoms,
    text: text ?? this.text,
    photos: photos ?? this.photos,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'symptoms': [for (final s in symptoms) s.name],
    'text': text,
    'photos': photos,
  };

  factory DiaryEntry.fromJson(Map<String, dynamic> json) => DiaryEntry(
    id: json['id'] as String,
    date: DateTime.parse(json['date'] as String),
    symptoms: [
      for (final s in json['symptoms'] as List? ?? const [])
        if (Symptom.byName(s as String) != null) Symptom.byName(s)!,
    ],
    text: json['text'] as String? ?? '',
    photos: [for (final p in json['photos'] as List? ?? const []) p as String],
  );
}
