import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pettime_app/models/expense.dart';
import 'package:pettime_app/models/pet.dart';
import 'package:pettime_app/models/supply.dart';
import 'package:pettime_app/state/pets_state.dart';
import 'package:pettime_app/widgets/expense_section.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Expense spent(String id, DateTime date, double amount,
        [ExpenseCategory c = ExpenseCategory.food, String note = '']) =>
    Expense(id: id, date: date, category: c, amount: amount, note: note);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() => initializeDateFormatting('es'));

  test('lee montos a la argentina', () {
    expect(parseMoney('45.300'), 45300);
    expect(parseMoney('45300'), 45300);
    expect(parseMoney(r'$ 1.250,50'), 1250.5);
    expect(parseMoney('800,5'), 800.5);
    expect(parseMoney('12.5'), 12.5);
    expect(parseMoney('0'), isNull);
    expect(parseMoney('hola'), isNull);
    expect(formatMoney(45300), r'$ 45.300');
    expect(formatMoney(1250.5), r'$ 1.250,50');
  });

  test('totales del mes y por categoría', () {
    final expenses = [
      spent('a', DateTime(2026, 10, 2), 40000),
      spent('b', DateTime(2026, 10, 10), 25000, ExpenseCategory.vet),
      spent('c', DateTime(2026, 10, 15), 5000),
      spent('d', DateTime(2026, 9, 20), 30000),
    ];
    final oct = DateTime(2026, 10, 18);
    expect(totalOfMonth(expenses, oct), 70000);
    expect(totalOfMonth(expenses, DateTime(2026, 9)), 30000);
    expect(byCategory(expenses, oct), [
      (ExpenseCategory.food, 45000.0),
      (ExpenseCategory.vet, 25000.0),
    ]);
    expect(ExpenseCategory.ofSupply(SupplyKind.food),
        ExpenseCategory.food);
  });

  test('se guardan con la mascota; los datos viejos cargan', () async {
    final pet = Pet(id: 'p', name: 'Pancho', expenses: [
      spent('a', DateTime(2026, 10, 2), 40000, ExpenseCategory.food, 'Royal'),
    ]);
    final back = Pet.fromJson(pet.toJson()).expenses.single;
    expect(back.amount, 40000);
    expect(back.note, 'Royal');
    expect(Pet.fromJson(pet.toJson()..remove('expenses')).expenses, isEmpty);

    final state = PetsState();
    await state.savePet(Pet(id: 'p', name: 'Pancho'));
    await state.saveExpense('p', spent('a', DateTime(2026, 9, 1), 100));
    await state.saveExpense('p', spent('b', DateTime(2026, 10, 1), 200));
    expect(state.byId('p')!.expenses.map((e) => e.id), ['b', 'a']);
    await state.saveExpense('p', spent('a', DateTime(2026, 9, 1), 150));
    expect(state.byId('p')!.expenses.last.amount, 150);
    await state.deleteExpense('p', 'b');
    expect(state.byId('p')!.expenses.map((e) => e.id), ['a']);
  });

  testWidgets('la ficha muestra el mes y permite anotar un gasto',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final state = PetsState();
    await state.savePet(Pet(id: 'p', name: 'Pancho', expenses: [
      spent('a', now, 40000, ExpenseCategory.food, 'Royal Canin 15 kg'),
    ]));

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ListView(children: [
              ExpenseSection(pet: context.watch<PetsState>().byId('p')!),
              TextButton(
                onPressed: () => showExpenseDialog(
                  context,
                  context.read<PetsState>().byId('p')!,
                ),
                child: const Text('nuevo'),
              ),
            ]),
          ),
        ),
      ),
    ));
    expect(find.text(r'$ 40.000'), findsWidgets);
    expect(find.text('Royal Canin 15 kg'), findsOneWidget);

    await tester.tap(find.text('nuevo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '25.000');
    await tester.tap(find.text('Veterinaria'));
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(state.byId('p')!.expenses.length, 2);
    expect(find.text(r'$ 65.000'), findsOneWidget);
  });
}
