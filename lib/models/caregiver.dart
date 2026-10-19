import 'dart:math';

/// Someone who looks after the pet for a few days (a vacation, a trip): they
/// join with their own code, see and mark everything like the family, and
/// the pet leaves their phone by itself when the time is up.
class Caregiver {
  Caregiver({
    required this.id,
    required this.name,
    required this.until,
    this.endedAt,
  });

  /// 4 letters and numbers, part of the caregiver's code.
  final String id;
  final String name;

  /// Until when they look after it.
  final DateTime until;

  /// Set when the family ended it before [until].
  final DateTime? endedAt;

  bool isActive(DateTime now) => endedAt == null && now.isBefore(until);

  /// When it ended or ends.
  DateTime get endsAt =>
      endedAt != null && endedAt!.isBefore(until) ? endedAt! : until;

  Caregiver end(DateTime now) =>
      Caregiver(id: id, name: name, until: until, endedAt: now);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'until': until.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
  };

  factory Caregiver.fromJson(Map<String, dynamic> json) => Caregiver(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    until: DateTime.parse(json['until'] as String),
    endedAt: json['endedAt'] == null
        ? null
        : DateTime.parse(json['endedAt'] as String),
  );
}

/// The caregiver's code mixes the family code (8) with the caregiver's id
/// (4), so the family code can't be read from it.
class CaregiverCode {
  CaregiverCode._();

  static const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const _order = [3, 9, 0, 6, 11, 1, 8, 4, 10, 2, 7, 5];

  static String newId([Random? random]) {
    final r = random ?? Random.secure();
    return String.fromCharCodes([
      for (var i = 0; i < 4; i++)
        _alphabet.codeUnitAt(r.nextInt(_alphabet.length)),
    ]);
  }

  /// The 12 characters the caregiver types.
  static String encode(String familyCode, String caregiverId) {
    final plain = familyCode + caregiverId;
    return String.fromCharCodes([for (final i in _order) plain.codeUnitAt(i)]);
  }

  /// (family code, caregiver id) of a 12-character code.
  static (String, String) decode(String code) {
    final plain = List.filled(12, 0);
    for (final (pos, i) in _order.indexed) {
      plain[i] = code.codeUnitAt(pos);
    }
    final s = String.fromCharCodes(plain);
    return (s.substring(0, 8), s.substring(8));
  }

  /// "AB3D-EF5H-JK7M", easier to read and dictate.
  static String display(String code) => [
    for (var i = 0; i < code.length; i += 4)
      code.substring(i, min(i + 4, code.length)),
  ].join('-');
}

/// Joins both phones' caregivers: nobody is lost, and one ended on either
/// phone stays ended.
List<Caregiver> mergeCaregivers(List<Caregiver> mine, List<Caregiver> theirs) {
  final byId = {for (final c in theirs) c.id: c};
  return [
    for (final c in mine)
      c.endedAt == null && byId[c.id]?.endedAt != null ? byId[c.id]! : c,
    ...theirs.where((t) => !mine.any((m) => m.id == t.id)),
  ];
}
