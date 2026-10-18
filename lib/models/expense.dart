import 'package:intl/intl.dart';

import 'supply.dart';

enum ExpenseCategory {
  food('Alimento'),
  vet('Veterinaria'),
  medicine('Remedios'),
  grooming('Peluquería'),
  accessories('Accesorios'),
  other('Otros');

  const ExpenseCategory(this.label);
  final String label;

  /// Category of what is bought when restocking a [SupplyKind].
  static ExpenseCategory ofSupply(SupplyKind kind) => switch (kind) {
        SupplyKind.food => food,
        SupplyKind.medicine => medicine,
        SupplyKind.other => other,
      };
}

/// Money spent on a pet.
class Expense {
  Expense({
    required this.id,
    required this.date,
    required this.category,
    required this.amount,
    this.note = '',
  });

  final String id;
  final DateTime date;
  final ExpenseCategory category;

  /// In pesos.
  final double amount;

  /// What it was, e.g. "Royal Canin 15 kg".
  final String note;

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'category': category.name,
        'amount': amount,
        'note': note,
      };

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        id: json['id'] as String,
        date: DateTime.parse(json['date'] as String),
        category: ExpenseCategory.values.asNameMap()[json['category']] ??
            ExpenseCategory.other,
        amount: (json['amount'] as num).toDouble(),
        note: json['note'] as String? ?? '',
      );
}

/// Reads an amount typed the Argentine way: "45.300", "45300", "1.250,50",
/// "$ 800". Null when it isn't a positive amount.
double? parseMoney(String text) {
  var s = text.replaceAll(RegExp(r'[\s$]'), '');
  if (s.isEmpty) return null;
  if (s.contains(',')) {
    // The comma is the decimal separator; dots group thousands.
    s = s.replaceAll('.', '').replaceAll(',', '.');
  } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(s)) {
    s = s.replaceAll('.', '');
  }
  final value = double.tryParse(s);
  if (value == null || value <= 0 || value > 100000000) return null;
  return value;
}

/// "$ 45.300", "$ 1.250,50".
String formatMoney(double amount) {
  final cents = (amount * 100).round() % 100 != 0;
  // The es_AR currency pattern puts the sign after the number ("45.300 $");
  // in Argentina it goes before.
  final f = NumberFormat(cents ? '#,##0.00' : '#,##0', 'es_AR');
  return '\$ ${f.format(amount)}';
}

/// Total spent from [expenses] in the month of [month].
double totalOfMonth(Iterable<Expense> expenses, DateTime month) => expenses
    .where((e) => e.date.year == month.year && e.date.month == month.month)
    .fold(0, (sum, e) => sum + e.amount);

/// Total by category in the month of [month], biggest first, without the
/// categories with nothing spent.
List<(ExpenseCategory, double)> byCategory(
  Iterable<Expense> expenses,
  DateTime month,
) {
  final totals = <ExpenseCategory, double>{};
  for (final e in expenses) {
    if (e.date.year != month.year || e.date.month != month.month) continue;
    totals[e.category] = (totals[e.category] ?? 0) + e.amount;
  }
  return totals.entries.map((e) => (e.key, e.value)).toList()
    ..sort((a, b) => b.$2.compareTo(a.$2));
}
