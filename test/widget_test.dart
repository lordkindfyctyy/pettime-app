import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pettime_app/main.dart';
import 'package:pettime_app/models/medication.dart';
import 'package:pettime_app/models/pet.dart';
import 'package:pettime_app/state/pets_state.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Medication.nextDose steps by the interval', () {
    final med = Medication(
      id: 'm',
      name: 'Amoxicilina',
      everyHours: 8,
      startsAt: DateTime(2026, 1, 1, 8),
    );
    expect(med.nextDose(DateTime(2026, 1, 1, 7)), DateTime(2026, 1, 1, 8));
    expect(med.nextDose(DateTime(2026, 1, 1, 8)), DateTime(2026, 1, 1, 16));
    expect(med.nextDose(DateTime(2026, 1, 1, 17)), DateTime(2026, 1, 2));
  });

  test('Medication.nextDose is null after the end date', () {
    final med = Medication(
      id: 'm',
      name: 'X',
      everyHours: 12,
      startsAt: DateTime(2026, 1, 1, 8),
      endsAt: DateTime(2026, 1, 2, 8),
    );
    expect(med.nextDose(DateTime(2026, 1, 2, 9)), isNull);
  });

  test('Pet.ageLabel', () {
    final pet = Pet(id: 'p', name: 'Luna', birthDate: DateTime(2023, 3, 10));
    expect(pet.ageLabel(DateTime(2026, 5, 10)), '3 años y 2 meses');
    expect(pet.ageLabel(DateTime(2023, 4, 12)), '1 mes');
  });

  test('Pet round-trips through JSON', () {
    final pet = Pet(
      id: 'p',
      name: 'Luna',
      food: 'Balanceado',
      medications: [
        Medication(
          id: 'm',
          name: 'X',
          everyHours: 6,
          startsAt: DateTime(2026, 1, 1),
        ),
      ],
    );
    final copy = Pet.fromJson(pet.toJson());
    expect(copy.name, 'Luna');
    expect(copy.medications.single.everyHours, 6);
  });

  testWidgets('shows the empty state and adds a pet', (tester) async {
    await initializeDateFormatting('es');
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = PetsState();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: state, child: const PetTimeApp()),
    );
    expect(find.text('Todavía no agregaste ninguna mascota'), findsOneWidget);

    await tester.tap(find.text('Mascota'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Luna');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Luna'), findsOneWidget);
  });
}
