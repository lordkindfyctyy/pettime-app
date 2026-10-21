import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_lang.dart';
import '../models/expense.dart';
import '../models/pet.dart';
import '../state/pets_state.dart';
import '../theme.dart';
import 'confirm_delete.dart';

IconData expenseIcon(ExpenseCategory c) => switch (c) {
      ExpenseCategory.food => Icons.set_meal_outlined,
      ExpenseCategory.vet => Icons.local_hospital_outlined,
      ExpenseCategory.medicine => Icons.medication_outlined,
      ExpenseCategory.grooming => Icons.content_cut,
      ExpenseCategory.accessories => Icons.toys_outlined,
      ExpenseCategory.other => Icons.receipt_long_outlined,
    };

/// Asks for an expense (a new one, or [expense] to edit it) and saves it.
/// [category] and [note] prefill a new one, e.g. after restocking food.
Future<void> showExpenseDialog(
  BuildContext context,
  Pet pet, {
  Expense? expense,
  ExpenseCategory? category,
  String note = '',
}) async {
  final state = context.read<PetsState>();
  final result = await showDialog<_DialogResult>(
    context: context,
    builder: (_) => _ExpenseDialog(
      pet: pet,
      expense: expense,
      category: category,
      note: note,
    ),
  );
  if (result == null) return;
  if (result.delete) {
    if (!context.mounted) return;
    final ok = await confirmDelete(
      context,
      tr('el gasto de {n} ({label})', {'n': formatMoney(expense!.amount), 'label': expense.category.label}),
    );
    if (ok) await state.deleteExpense(pet.id, expense.id);
  } else {
    await state.saveExpense(
      pet.id,
      Expense(
        id: expense?.id ?? state.newId(),
        date: result.date,
        category: result.category,
        amount: result.amount,
        note: result.note,
      ),
    );
  }
}

class _DialogResult {
  _DialogResult({
    required this.amount,
    required this.category,
    required this.date,
    required this.note,
  }) : delete = false;

  _DialogResult.delete()
      : amount = 0,
        category = ExpenseCategory.other,
        date = DateTime(0),
        note = '',
        delete = true;

  final double amount;
  final ExpenseCategory category;
  final DateTime date;
  final String note;
  final bool delete;
}

class _ExpenseDialog extends StatefulWidget {
  const _ExpenseDialog({
    required this.pet,
    this.expense,
    this.category,
    this.note = '',
  });

  final Pet pet;
  final Expense? expense;
  final ExpenseCategory? category;
  final String note;

  @override
  State<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<_ExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: widget.expense == null
        ? ''
        : formatMoney(widget.expense!.amount).replaceAll(r'$ ', ''),
  );
  late final _note =
      TextEditingController(text: widget.expense?.note ?? widget.note);
  late ExpenseCategory _category = widget.expense?.category ??
      widget.category ??
      ExpenseCategory.food;
  late DateTime _date =
      widget.expense?.date ?? DateUtils.dateOnly(DateTime.now());

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.expense != null;
    return AlertDialog(
      title: Text(editing ? tr('Gasto') : tr('Gasto en {name}', {'name': widget.pet.name})),
      scrollable: true,
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _amount,
              autofocus: !editing,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: tr('Monto'),
                prefixText: r'$ ',
                hintText: '45.300',
              ),
              validator: (v) =>
                  parseMoney(v ?? '') == null ? tr('Ingresá cuánto gastaste') : null,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in ExpenseCategory.values)
                  ChoiceChip(
                    avatar: Icon(expenseIcon(c), size: 18),
                    label: Text(c.label),
                    selected: _category == c,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _category = c),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: tr('Detalle (opcional)'),
                hintText: tr('Royal Canin 15 kg, consulta, vacuna…'),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Fecha')),
              subtitle: Text(DateFormat.yMMMd(AppLang.code).format(_date)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (d != null) setState(() => _date = d);
              },
            ),
          ],
        ),
      ),
      actions: [
        if (editing)
          TextButton(
            onPressed: () => Navigator.pop(context, _DialogResult.delete()),
            child: Text(tr('Eliminar')),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Cancelar')),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _DialogResult(
                amount: parseMoney(_amount.text)!,
                category: _category,
                date: _date,
                note: _note.text.trim(),
              ),
            );
          },
          child: Text(tr('Guardar')),
        ),
      ],
    );
  }
}

String _monthName(DateTime month) {
  final s = DateFormat.yMMMM(AppLang.code).format(month);
  return s[0].toUpperCase() + s.substring(1);
}

/// One expense in a list; tapping it edits it.
class ExpenseTile extends StatelessWidget {
  const ExpenseTile({super.key, required this.pet, required this.expense});

  final Pet pet;
  final Expense expense;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: Brand.orange.withValues(alpha: 0.15),
        child: Icon(expenseIcon(expense.category), color: Brand.orange),
      ),
      title: Text(expense.note.isEmpty ? expense.category.label : expense.note),
      subtitle: Text(
        '${expense.category.label} · '
        '${DateFormat.yMMMd(AppLang.code).format(expense.date)}',
      ),
      trailing: Text(
        formatMoney(expense.amount),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      onTap: () => showExpenseDialog(context, pet, expense: expense),
    );
  }
}

/// Expenses in the pet's profile: this month's total compared with last
/// month, what it went on, and the latest ones.
class ExpenseSection extends StatelessWidget {
  const ExpenseSection({super.key, required this.pet, this.now});

  final Pet pet;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final at = now ?? DateTime.now();
    final theme = Theme.of(context);
    if (pet.expenses.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          tr('Anotá lo que gastás en {name}: alimento, veterinaria, remedios… y te mostramos cuánto es por mes.', {'name': pet.name}),
        ),
      );
    }
    final thisMonth = totalOfMonth(pet.expenses, at);
    final lastMonth = totalOfMonth(pet.expenses, DateTime(at.year, at.month - 1));
    final categories = byCategory(pet.expenses, at);
    final top = categories.isEmpty ? 0.0 : categories.first.$2;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Este mes'), style: theme.textTheme.labelLarge),
            Text(
              formatMoney(thisMonth),
              style: theme.textTheme.headlineMedium?.copyWith(
                color: Brand.orange,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              tr('El mes pasado: {n}', {'n': formatMoney(lastMonth)}),
              style: theme.textTheme.bodySmall,
            ),
            if (categories.isNotEmpty) const SizedBox(height: 12),
            for (final (category, total) in categories)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                // Name and amount on one line and the bar under them, so
                // "Peluquería" fits whole even with a big font.
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(expenseIcon(category), size: 18, color: Brand.teal),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            category.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(formatMoney(total)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: total / top,
                        minHeight: 8,
                        color: Brand.teal,
                        backgroundColor: Brand.teal.withValues(alpha: 0.12),
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 24),
            for (final e in pet.expenses.take(3))
              ExpenseTile(pet: pet, expense: e),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.history),
                label: Text(tr('Ver todos ({length})', {'length': pet.expenses.length})),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ExpensesScreen(petId: pet.id),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Every expense of a pet, by month, with each month's total.
class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key, required this.petId});

  final String petId;

  @override
  Widget build(BuildContext context) {
    final pet = context.watch<PetsState>().byId(petId);
    if (pet == null) return const Scaffold(body: SizedBox.shrink());
    final theme = Theme.of(context);
    final months = <DateTime>[];
    for (final e in pet.expenses) {
      final m = DateTime(e.date.year, e.date.month);
      if (!months.contains(m)) months.add(m);
    }
    return Scaffold(
      appBar: AppBar(title: Text(tr('Gastos de {name}', {'name': pet.name}))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showExpenseDialog(context, pet),
        icon: const Icon(Icons.add),
        label: Text(tr('Gasto')),
      ),
      body: pet.expenses.isEmpty
          ? Center(child: Text(tr('Todavía no anotaste gastos')))
          : ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                88 + MediaQuery.viewPaddingOf(context).bottom,
              ),
              children: [
                for (final m in months) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _monthName(m),
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        Text(
                          formatMoney(totalOfMonth(pet.expenses, m)),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Brand.orange,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final e in pet.expenses.where(
                    (e) => e.date.year == m.year && e.date.month == m.month,
                  ))
                    ExpenseTile(pet: pet, expense: e),
                ],
              ],
            ),
    );
  }
}
