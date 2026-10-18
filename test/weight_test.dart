import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pettime_app/models/pet.dart';
import 'package:pettime_app/models/weight_entry.dart';
import 'package:pettime_app/screens/pet_detail_screen.dart';
import 'package:pettime_app/state/pets_state.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('lee el peso con coma o punto y lo muestra con coma', () {
    expect(parseKg('32,5'), 32.5);
    expect(parseKg(' 4.25 '), 4.25);
    expect(parseKg(''), isNull);
    expect(parseKg('abc'), isNull);
    expect(parseKg('0'), isNull);
    expect(formatKg(32.5), '32,5 kg');
    expect(formatKg(4), '4 kg');
    expect(formatKg(0.85), '0,85 kg');
  });

  test('los pesos se guardan ordenados por fecha y se pueden borrar', () async {
    final state = PetsState();
    await state.savePet(Pet(id: 'p', name: 'Pancho'));
    await state.addWeight('p', WeightEntry(id: 'b', date: DateTime(2026, 10, 1), kg: 32));
    await state.addWeight('p', WeightEntry(id: 'a', date: DateTime(2026, 9, 1), kg: 31));
    expect(state.byId('p')!.weights.map((w) => w.id), ['a', 'b']);
    expect(state.byId('p')!.currentWeight!.kg, 32);

    final again = Pet.fromJson(state.byId('p')!.toJson());
    expect(again.weights.map((w) => w.kg), [31, 32]);

    await state.deleteWeight('p', 'b');
    expect(state.byId('p')!.currentWeight!.kg, 31);
  });

  test('los datos viejos sin pesos cargan', () {
    final json = Pet(id: 'p', name: 'Luna').toJson()..remove('weights');
    expect(Pet.fromJson(json).weights, isEmpty);
    expect(Pet.fromJson(json).currentWeight, isNull);
  });

  testWidgets('la ficha muestra el peso, la diferencia y permite anotar uno',
      (tester) async {
    await initializeDateFormatting('es');
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = PetsState();
    await state.savePet(Pet(id: 'p', name: 'Pancho', weights: [
      WeightEntry(id: 'a', date: DateTime(2026, 9, 1), kg: 31),
      WeightEntry(id: 'b', date: DateTime(2026, 10, 1), kg: 32.5),
    ]));
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: const MaterialApp(home: PetDetailScreen(petId: 'p')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('32,5 kg'), findsOneWidget);
    expect(find.text('▲ +1,5 kg'), findsOneWidget);

    await tester.tap(find.text('Anotar peso'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '33,1');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(state.byId('p')!.currentWeight!.kg, 33.1);
    expect(find.text('33,1 kg'), findsOneWidget);
    expect(find.text('▲ +0,6 kg'), findsOneWidget);
  });
}
