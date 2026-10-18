import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pettime_app/models/agenda.dart';
import 'package:pettime_app/models/pet.dart';
import 'package:pettime_app/models/supply.dart';
import 'package:pettime_app/screens/today_screen.dart';
import 'package:pettime_app/services/notification_service.dart';
import 'package:pettime_app/state/pets_state.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Supply food({DateTime? opened, int warn = 5}) => Supply(
      id: 's',
      name: 'Royal Canin Fit 15 kg',
      kind: SupplyKind.food,
      packageAmount: 15,
      unit: 'kg',
      perDay: 0.3,
      openedOn: opened ?? DateTime(2026, 10, 1),
      warnDaysBefore: warn,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('calcula cuándo se termina y cuánto queda', () {
    final s = food();
    // 15 kg a 0,3 kg por día = 50 días.
    expect(s.runsOutOn, DateTime(2026, 11, 20));
    expect(s.warnOn, DateTime(2026, 11, 15));
    expect(s.daysLeft(DateTime(2026, 11, 10, 18)), 10);
    expect(s.needsRestock(DateTime(2026, 11, 10)), isFalse);
    expect(s.needsRestock(DateTime(2026, 11, 15)), isTrue);
    expect(s.fractionLeft(DateTime(2026, 10, 26)), closeTo(0.5, 0.01));
    expect(daysLeftLabel(10), 'Quedan 10 días');
    expect(daysLeftLabel(1), 'Se termina mañana');
    expect(daysLeftLabel(0), 'Se termina hoy');
    expect(daysLeftLabel(-3), 'Se terminó hace 3 días');
  });

  test('se guarda con la mascota; los datos viejos cargan', () {
    final pet = Pet(id: 'p', name: 'Pancho', supplies: [food()]);
    final back = Pet.fromJson(pet.toJson()).supplies.single;
    expect(back.name, 'Royal Canin Fit 15 kg');
    expect(back.perDay, 0.3);
    expect(back.runsOutOn, DateTime(2026, 11, 20));
    final old = pet.toJson()..remove('supplies');
    expect(Pet.fromJson(old).supplies, isEmpty);
  });

  test('mensaje y link de WhatsApp', () {
    final msg = orderMessage(food(), 'Pancho');
    expect(msg, 'Hola! Quiero pedir Royal Canin Fit 15 kg para Pancho. ¡Gracias!');
    final toShop = whatsAppUri(msg, phone: '+54 9 11 1234-5678');
    expect(toShop.host, 'wa.me');
    expect(toShop.path, '/5491112345678');
    expect(toShop.queryParameters['text'], msg);
    expect(whatsAppUri(msg).path, '/');
    expect(parseAmount('0,3'), 0.3);
    expect(parseAmount('0'), isNull);
    expect(formatAmount(0.3), '0,3');
    expect(formatAmount(15), '15');
  });

  test('avisa el día de aviso y el día que se termina, a las 10', () {
    final pet = Pet(id: 'p', name: 'Pancho', supplies: [food()]);
    final planned = NotificationService.plannedSupplyReminders(
        pet, DateTime(2026, 11, 1));
    expect([for (final p in planned) p.$3],
        [DateTime(2026, 11, 15, 10), DateTime(2026, 11, 20, 10)]);
    expect(planned.last.$2, isTrue);
    expect(NotificationService.supplyBody(pet, food(), true),
        'Hoy se termina Royal Canin Fit 15 kg. Pedilo desde PetTime.');
    expect(
      NotificationService.plannedSupplyReminders(pet, DateTime(2026, 11, 16)).length,
      1,
    );
  });

  test('reponer empieza un paquete nuevo hoy', () async {
    final state = PetsState();
    await state.savePet(Pet(id: 'p', name: 'Pancho', supplies: [food()]));
    await state.restock('p', 's', DateTime(2026, 11, 18, 15));
    final s = state.byId('p')!.supplies.single;
    expect(s.openedOn, DateTime(2026, 11, 18));
    expect(s.runsOutOn, DateTime(2027, 1, 7));
  });

  testWidgets('Hoy muestra lo que hay que reponer', (tester) async {
    await initializeDateFormatting('es');
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime(2026, 11, 17, 9);
    final state = PetsState();
    await state.savePet(Pet(id: 'p', name: 'Pancho', supplies: [food()]));
    expect(suppliesToRestock(state.pets, now).length, 1);

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(home: TodayScreen(clock: () => now)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Por reponer'), findsOneWidget);
    expect(find.text('Royal Canin Fit 15 kg'), findsOneWidget);
    expect(find.textContaining('Quedan 3 días'), findsOneWidget);
    expect(find.text('Pedir por WhatsApp'), findsOneWidget);
  });
}
