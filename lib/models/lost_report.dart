import 'package:intl/intl.dart';
import '../l10n/app_lang.dart';

enum ReportKind {
  lost('Se perdió', 'Perdidas'),
  found('Encontrada', 'Encontradas');

  const ReportKind(this._badge, this._plural);
  final String _badge;
  final String _plural;

  String get badge => tr(_badge);
  String get plural => tr(_plural);
}

/// A lost or found pet notice, as sixsevenweb.com publishes it.
class LostReport {
  LostReport({
    required this.id,
    required this.kind,
    required this.petName,
    required this.species,
    required this.breed,
    required this.description,
    required this.eventAt,
    required this.zone,
    required this.contactName,
    required this.contactPhone,
    required this.resolved,
    required this.photos,
    required this.webUrl,
  });

  final int id;
  final ReportKind kind;
  final String petName;
  final String species;
  final String breed;
  final String description;

  /// When it got lost or was seen.
  final DateTime eventAt;
  final String zone;
  final String contactName;

  /// Digits only, as wa.me wants it.
  final String contactPhone;

  /// It turned up (no longer shown to everyone).
  final bool resolved;
  final List<String> photos;

  /// Its page on the website, to share it.
  final String webUrl;

  String get title => petName.isNotEmpty
      ? petName
      : kind == ReportKind.lost
          ? tr('Mascota perdida')
          : tr('Mascota encontrada');

  /// "Perro · Labrador".
  String get details =>
      [species, breed].where((s) => s.isNotEmpty).join(' · ');

  /// "Se perdió el 17 oct, 18:30" / "Vista el 17 oct, 18:30".
  String whenLabel() {
    final f = DateFormat(tr("d MMM, HH:mm"), AppLang.code).format(eventAt);
    return kind == ReportKind.lost ? tr('Se perdió el {f}', {'f': f}) : tr('Vista el {f}', {'f': f});
  }

  /// The WhatsApp chat with whoever published it, with a first message. It
  /// stays in Spanish: the notices are published for people in Argentina.
  Uri whatsAppUri() {
    final text = kind == ReportKind.lost
        ? 'Hola! Vi el aviso de $title en PetTime.'
        : 'Hola! Vi en PetTime el aviso de la mascota que encontraste en $zone.';
    return Uri.https('wa.me', '/$contactPhone', {'text': text});
  }

  /// What is sent when sharing the notice.
  String shareText() {
    final head = kind == ReportKind.lost
        ? tr('¡Se perdió {title}!', {'title': title})
        : tr('Se encontró esta mascota');
    return [
      head,
      if (details.isNotEmpty) details,
      whenLabel(),
      tr('Zona: {zone}', {'zone': zone}),
      if (description.isNotEmpty) description,
      tr('Contacto por WhatsApp: https://wa.me/{contactPhone}', {'contactPhone': contactPhone}),
      webUrl,
    ].join('\n');
  }

  factory LostReport.fromJson(Map<String, dynamic> json) => LostReport(
        id: json['id'] as int,
        kind: json['kind'] == 'found' ? ReportKind.found : ReportKind.lost,
        petName: json['petName'] as String? ?? '',
        species: json['species'] as String? ?? '',
        breed: json['breed'] as String? ?? '',
        description: json['description'] as String? ?? '',
        eventAt: DateTime.parse(json['eventAt'] as String),
        zone: json['zone'] as String? ?? '',
        contactName: json['contactName'] as String? ?? '',
        contactPhone: json['contactPhone'] as String? ?? '',
        resolved: json['status'] == 'resolved',
        photos: [for (final p in json['photos'] as List? ?? []) p as String],
        webUrl: json['webUrl'] as String? ?? '',
      );
}

/// A notice being written in the app, before it is published.
class ReportDraft {
  ReportDraft({
    required this.kind,
    required this.petName,
    required this.species,
    required this.breed,
    required this.description,
    required this.eventAt,
    required this.zone,
    required this.contactName,
    required this.contactPhone,
  });

  final ReportKind kind;
  final String petName;
  final String species;
  final String breed;
  final String description;
  final DateTime eventAt;
  final String zone;
  final String contactName;
  final String contactPhone;

  Map<String, String> toFields() => {
        'kind': kind.name,
        'petName': petName,
        'species': species,
        'breed': breed,
        'description': description,
        'eventAt': DateFormat("yyyy-MM-dd'T'HH:mm").format(eventAt),
        'zone': zone,
        'contactName': contactName,
        'contactPhone': contactPhone,
      };
}
