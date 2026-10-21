import '../l10n/app_lang.dart';
enum SupplyKind {
  food('Alimento'),
  medicine('Remedio'),
  other('Otro');

  const SupplyKind(this._label);
  final String _label;

  String get label => tr(_label);
}

/// Something that runs out and has to be bought again: a bag of food, a box
/// of pills… It knows how much a package brings and how much is used per day,
/// so it can tell when it will run out.
class Supply {
  Supply({
    required this.id,
    required this.name,
    required this.kind,
    required this.packageAmount,
    required this.unit,
    required this.perDay,
    required this.openedOn,
    this.warnDaysBefore = 5,
  });

  final String id;

  /// What to ask for at the shop, e.g. "Royal Canin Fit 15 kg".
  final String name;
  final SupplyKind kind;

  /// How much a package brings and how much is used per day, in [unit].
  final double packageAmount;
  final String unit;
  final double perDay;

  /// When the current package was opened.
  final DateTime openedOn;

  /// How many days before running out to warn.
  final int warnDaysBefore;

  static const units = ['kg', 'g', 'comprimidos', 'ml', 'unidades', 'pipetas'];

  /// Day the current package runs out.
  DateTime get runsOutOn {
    final days = (packageAmount / perDay).floor();
    return DateTime(openedOn.year, openedOn.month, openedOn.day + days);
  }

  /// Day to warn that it's running out.
  DateTime get warnOn => DateTime(
        runsOutOn.year,
        runsOutOn.month,
        runsOutOn.day - warnDaysBefore,
      );

  /// Whole days left at [now] (negative when it already ran out).
  int daysLeft(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return (runsOutOn.difference(today).inHours / 24).round();
  }

  /// Share of the package still left at [now], from 0 to 1.
  double fractionLeft(DateTime now) {
    final total = runsOutOn.difference(openedOn).inHours;
    if (total <= 0) return 0;
    final left = runsOutOn.difference(now).inHours;
    return (left / total).clamp(0.0, 1.0);
  }

  /// Within the warning days or already out.
  bool needsRestock(DateTime now) => daysLeft(now) <= warnDaysBefore;

  Supply copyWith({DateTime? openedOn}) => Supply(
        id: id,
        name: name,
        kind: kind,
        packageAmount: packageAmount,
        unit: unit,
        perDay: perDay,
        openedOn: openedOn ?? this.openedOn,
        warnDaysBefore: warnDaysBefore,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'packageAmount': packageAmount,
        'unit': unit,
        'perDay': perDay,
        'openedOn': openedOn.toIso8601String(),
        'warnDaysBefore': warnDaysBefore,
      };

  factory Supply.fromJson(Map<String, dynamic> json) => Supply(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: SupplyKind.values.asNameMap()[json['kind']] ?? SupplyKind.other,
        packageAmount: (json['packageAmount'] as num).toDouble(),
        unit: json['unit'] as String? ?? 'unidades',
        perDay: (json['perDay'] as num).toDouble(),
        openedOn: DateTime.parse(json['openedOn'] as String),
        warnDaysBefore: json['warnDaysBefore'] as int? ?? 5,
      );
}

/// "Quedan 12 días", "Se termina mañana", "Se terminó hace 2 días".
String daysLeftLabel(int days) {
  if (days > 1) return tr('Quedan {days} días', {'days': days});
  if (days == 1) return tr('Se termina mañana');
  if (days == 0) return tr('Se termina hoy');
  if (days == -1) return tr('Se terminó ayer');
  return tr('Se terminó hace {n} días', {'n': -days});
}

/// Number typed with comma or dot ("0,3"), or null when it isn't positive.
double? parseAmount(String text) {
  final value = double.tryParse(text.trim().replaceAll(',', '.'));
  if (value == null || value <= 0) return null;
  return value;
}

/// "0,3", "15", "2,5".
String formatAmount(double value) {
  var s = value.toStringAsFixed(2);
  s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return s.replaceAll('.', ',');
}

/// WhatsApp message to order [supply] for [petName]. It stays in Spanish: the
/// shop answers in Spanish.
String orderMessage(Supply supply, String petName) =>
    'Hola! Quiero pedir ${supply.name} para $petName. ¡Gracias!';

/// wa.me link with the message; to [phone] when given (any format, only the
/// digits are kept), otherwise WhatsApp lets you choose the contact.
Uri whatsAppUri(String message, {String? phone}) {
  final digits = (phone ?? '').replaceAll(RegExp(r'\D'), '');
  return Uri.https('wa.me', digits.isEmpty ? '/' : '/$digits', {'text': message});
}
