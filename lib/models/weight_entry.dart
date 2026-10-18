/// One weighing of a pet.
class WeightEntry {
  WeightEntry({required this.id, required this.date, required this.kg});

  final String id;
  final DateTime date;
  final double kg;

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'kg': kg,
      };

  factory WeightEntry.fromJson(Map<String, dynamic> json) => WeightEntry(
        id: json['id'] as String,
        date: DateTime.parse(json['date'] as String),
        kg: (json['kg'] as num).toDouble(),
      );
}

/// Reads a weight typed the Argentine way ("32,5" or "32.5"), or null when it
/// is not a sensible weight.
double? parseKg(String text) {
  final value = double.tryParse(text.trim().replaceAll(',', '.'));
  if (value == null || value <= 0 || value > 500) return null;
  return value;
}

/// "32,5 kg", "4 kg", "0,85 kg".
String formatKg(double kg) {
  var s = kg.toStringAsFixed(2);
  s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return '${s.replaceAll('.', ',')} kg';
}
