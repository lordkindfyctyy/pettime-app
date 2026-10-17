import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pettime_app/main.dart';
import 'package:pettime_app/models/medication.dart';
import 'package:pettime_app/models/pet.dart';
import 'package:pettime_app/models/vet_visit.dart';
import 'package:pettime_app/services/calendar_service.dart';
import 'package:pettime_app/services/notification_service.dart';
import 'package:pettime_app/state/pets_state.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Medication.nextDose steps by the interval', () {
    final med = Medication(
      id: 'm',
      name: 'Amoxicilina',
      everyMinutes: 480,
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
      everyMinutes: 720,
      startsAt: DateTime(2026, 1, 1, 8),
      endsAt: DateTime(2026, 1, 2, 8),
    );
    expect(med.nextDose(DateTime(2026, 1, 2, 9)), isNull);
  });

  test('notification text names the pet and the medication', () {
    final pet = Pet(id: 'p', name: 'Luna');
    final med = Medication(
      id: 'm',
      name: 'Amoxicilina',
      dose: '1 comprimido',
      everyMinutes: 480,
      startsAt: DateTime(2026, 1, 1),
    );
    expect(NotificationService.messageBody(pet, med),
        'Es hora de darle Amoxicilina (1 comprimido) a Luna');
    expect(NotificationService.messageTitle(pet), 'Medicación de Luna');
  });

  test('notification ids fit 31 bits and leave room for every dose', () {
    final a = NotificationService.baseId('a');
    expect(a, NotificationService.baseId('a'));
    expect(a, isNot(NotificationService.baseId('b')));
    expect(a + NotificationService.dosesAhead, lessThan(1 << 31));
    expect(a % 64, 0);
  });

  test('PetsState saves, edits and deletes visits', () async {
    final state = PetsState();
    await state.savePet(Pet(id: 'p', name: 'Luna'));
    final date = DateTime.now().add(const Duration(days: 3));
    await state.saveVisit('p', VetVisit(id: 'v', clinic: 'Vet Sur', date: date));
    expect(state.byId('p')!.visits.single.isDone, isFalse);

    await state.saveVisit(
        'p', VetVisit(id: 'v', clinic: 'Vet Norte', date: date, reason: 'Vacuna'));
    expect(state.byId('p')!.visits.single.clinic, 'Vet Norte');

    await state.deleteVisit('p', 'v');
    expect(state.byId('p')!.visits, isEmpty);
  });

  test('Calendar event ids are valid base32hex and stable', () {
    final id = CalendarService.eventId('pm', '3f2a1b9c-0d4e-4f5a-8b6c-7d8e9f0a1b2c');
    expect(id, 'pm3f2a1b9c0d4e4f5a8b6c7d8e9f0a1b2c');
    expect(RegExp(r'^[a-v0-9]{5,1024}$').hasMatch(id), isTrue);
  });

  test('Calendar recurrence repeats every N hours until the end', () {
    final open = Medication(
      id: 'm',
      name: 'X',
      everyMinutes: 480,
      startsAt: DateTime.utc(2026, 1, 1, 8),
    );
    expect(CalendarService.recurrence(open), 'RRULE:FREQ=HOURLY;INTERVAL=8');
    final closed = open.copyWith(endsAt: DateTime.utc(2026, 1, 10, 20, 30));
    expect(CalendarService.recurrence(closed),
        'RRULE:FREQ=HOURLY;INTERVAL=8;UNTIL=20260110T203000Z');
  });

  test('PetsState logs and removes given doses, keeping them sorted', () async {
    final state = PetsState();
    final med = Medication(
      id: 'm',
      name: 'X',
      everyMinutes: 480,
      startsAt: DateTime(2026, 1, 1),
    );
    await state.savePet(Pet(id: 'p', name: 'Luna', medications: [med]));

    final late = DateTime(2026, 1, 2, 20);
    final early = DateTime(2026, 1, 2, 8);
    await state.logDose('p', 'm', late);
    await state.logDose('p', 'm', early);
    final saved = state.byId('p')!.medications.single;
    expect(saved.givenDoses, [early, late]);
    expect(saved.lastGiven, late);

    await state.removeDose('p', 'm', late);
    expect(state.byId('p')!.medications.single.givenDoses, [early]);

    // Editing the medication keeps its history.
    final again = Pet.fromJson(state.byId('p')!.toJson());
    expect(again.medications.single.givenDoses, [early]);
  });

  test('addDoseToJson records a dose without a PetsState', () {
    final pet = Pet(id: 'p', name: 'Luna', medications: [
      Medication(
        id: 'm',
        name: 'X',
        everyMinutes: 480,
        startsAt: DateTime(2026, 1, 1),
      ),
    ]);
    final raw = jsonEncode([pet.toJson()]);
    final at = DateTime(2026, 1, 2, 9);

    final updated = PetsState.addDoseToJson(raw, 'p', 'm', at)!;
    final back = Pet.fromJson((jsonDecode(updated) as List).single);
    expect(back.medications.single.givenDoses, [at]);

    expect(PetsState.addDoseToJson(raw, 'p', 'gone', at), isNull);
    expect(PetsState.addDoseToJson(raw, 'gone', 'm', at), isNull);
  });

  test('notification payload carries the pet and medication ids', () {
    final pet = Pet(id: 'p1', name: 'Luna');
    final med = Medication(
        id: 'm1', name: 'X', everyMinutes: 480, startsAt: DateTime(2026, 1, 1));
    expect(NotificationService.payload(pet, med), 'p1|m1');
  });

  test('Medication supports intervals in minutes', () {
    final med = Medication(
      id: 'm',
      name: 'X',
      everyMinutes: 30,
      startsAt: DateTime(2026, 1, 1, 8),
    );
    expect(med.nextDose(DateTime(2026, 1, 1, 8, 10)), DateTime(2026, 1, 1, 8, 30));
    expect(med.intervalLabel, 'cada 30 min');
    expect(med.copyWith(everyMinutes: 480).intervalLabel, 'cada 8 h');
    expect(med.copyWith(everyMinutes: 90).intervalLabel, 'cada 1 h 30 min');
    expect(CalendarService.recurrence(med), 'RRULE:FREQ=MINUTELY;INTERVAL=30');
  });

  test('Medication saved with whole hours still loads', () {
    final med = Medication.fromJson({
      'id': 'm',
      'name': 'X',
      'everyHours': 8,
      'startsAt': DateTime(2026, 1, 1).toIso8601String(),
    });
    expect(med.everyMinutes, 480);
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
          everyMinutes: 360,
          startsAt: DateTime(2026, 1, 1),
        ),
      ],
    );
    final copy = Pet.fromJson(pet.toJson());
    expect(copy.name, 'Luna');
    expect(copy.medications.single.everyMinutes, 360);
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
