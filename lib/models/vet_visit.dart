import '../l10n/app_lang.dart';
enum AppointmentKind {
  vet('Veterinaria', 'Veterinaria'),
  grooming('Peluquería / spa', 'Peluquería');

  const AppointmentKind(this._label, this._placeLabel);

  /// Name of the kind in the type selector.
  final String _label;
  String get label => tr(_label);

  /// What the place is called in the form and in titles.
  final String _placeLabel;
  String get placeLabel => tr(_placeLabel);
}

/// An appointment of a pet at the vet or at the groomer / spa.
class VetVisit {
  VetVisit({
    required this.id,
    required this.clinic,
    required this.date,
    this.kind = AppointmentKind.vet,
    this.address = '',
    this.reason = '',
    this.notes = '',
  });

  final String id;

  /// Name of the place.
  final String clinic;
  final DateTime date;
  final AppointmentKind kind;

  /// Street address, or a pasted Google Maps link.
  final String address;
  final String reason;
  final String notes;

  bool get isDone => date.isBefore(DateTime.now());

  /// Google Maps page of the place: the pasted link when [address] is one,
  /// otherwise a search for the name and address. Null when both are empty.
  Uri? get mapsUri {
    final a = address.trim();
    if (a.startsWith('http://') || a.startsWith('https://')) {
      return Uri.tryParse(a);
    }
    final query = [clinic.trim(), a].where((s) => s.isNotEmpty).join(', ');
    if (query.isEmpty) return null;
    return Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': query,
    });
  }

  /// Location text for a calendar event (a link is shown as is).
  String get locationText {
    final a = address.trim();
    if (a.startsWith('http://') || a.startsWith('https://')) return a;
    return [clinic.trim(), a].where((s) => s.isNotEmpty).join(', ');
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'clinic': clinic,
        'date': date.toIso8601String(),
        'kind': kind.name,
        'address': address,
        'reason': reason,
        'notes': notes,
      };

  factory VetVisit.fromJson(Map<String, dynamic> json) => VetVisit(
        id: json['id'] as String,
        clinic: json['clinic'] as String,
        date: DateTime.parse(json['date'] as String),
        // Visits saved before kinds existed were all at the vet.
        kind: AppointmentKind.values.asNameMap()[json['kind']] ??
            AppointmentKind.vet,
        address: json['address'] as String? ?? '',
        reason: json['reason'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
      );
}
