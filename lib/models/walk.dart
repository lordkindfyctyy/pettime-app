import '../l10n/app_lang.dart';
/// One walk of a pet.
class Walk {
  Walk({
    required this.id,
    required this.date,
    required this.minutes,
    this.km,
    this.note = '',
  });

  final String id;

  /// When it went out.
  final DateTime date;
  final int minutes;

  /// Distance, when it was known.
  final double? km;
  final String note;

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'minutes': minutes,
    'km': km,
    'note': note,
  };

  factory Walk.fromJson(Map<String, dynamic> json) => Walk(
    id: json['id'] as String,
    date: DateTime.parse(json['date'] as String),
    minutes: json['minutes'] as int? ?? 0,
    km: (json['km'] as num?)?.toDouble(),
    note: json['note'] as String? ?? '',
  );
}

/// The daily "¿ya salió a pasear?" reminder: at [hour]:[minute] of every day
/// it hasn't been walked yet.
class WalkReminder {
  const WalkReminder({required this.hour, this.minute = 0});

  final int hour;
  final int minute;

  /// "18:30".
  String get label =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {'hour': hour, 'minute': minute};

  factory WalkReminder.fromJson(Map<String, dynamic> json) => WalkReminder(
    hour: json['hour'] as int? ?? 18,
    minute: json['minute'] as int? ?? 0,
  );
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Walks of the day of [day].
List<Walk> walksOn(Iterable<Walk> walks, DateTime day) =>
    walks.where((w) => _sameDay(w.date, day)).toList();

/// Minutes walked on each of the 7 days ending on [today], oldest first.
List<int> minutesLast7Days(Iterable<Walk> walks, DateTime today) => [
  for (var i = 6; i >= 0; i--)
    walksOn(
      walks,
      DateTime(today.year, today.month, today.day - i),
    ).fold(0, (sum, w) => sum + w.minutes),
];

/// Days in a row, up to [today], with at least one walk. Today without a walk
/// yet doesn't break the streak (it can still go out).
int walkStreak(Iterable<Walk> walks, DateTime today) {
  final days = {
    for (final w in walks) DateTime(w.date.year, w.date.month, w.date.day),
  };
  var day = DateTime(today.year, today.month, today.day);
  if (!days.contains(day)) day = DateTime(day.year, day.month, day.day - 1);
  var streak = 0;
  while (days.contains(day)) {
    streak++;
    day = DateTime(day.year, day.month, day.day - 1);
  }
  return streak;
}

/// "45 min", "1 h", "1 h 20 min".
String formatMinutes(int minutes) {
  if (minutes < 60) return tr('{minutes} min', {'minutes': minutes});
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? tr('{h} h', {'h': h}) : tr('{h} h {m} min', {'h': h, 'm': m});
}

/// Reads a distance typed "2,5" or "2.5", or null when it isn't sensible.
double? parseKm(String text) {
  final value = double.tryParse(text.trim().replaceAll(',', '.'));
  if (value == null || value <= 0 || value > 100) return null;
  return value;
}

/// "2,5 km", "3 km".
String formatKm(double km) {
  var s = km.toStringAsFixed(1);
  if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
  return '${localizedDecimal(s)} km';
}
