import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pettime_app/main.dart';
import 'package:pettime_app/models/medication.dart';
import 'package:pettime_app/models/pet.dart';
import 'package:pettime_app/models/vet_visit.dart';
import 'package:pettime_app/services/notification_service.dart';
import 'package:pettime_app/state/language_state.dart';
import 'package:pettime_app/state/pets_state.dart';
import 'package:pettime_app/widgets/medication_card.dart';
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

  test('notification shows the pet photo only when the file exists', () {
    final dir = Directory.systemTemp.createTempSync('pettime_photo');
    addTearDown(() => dir.deleteSync(recursive: true));
    final photo = File('${dir.path}/luna.jpg')..writeAsBytesSync([1, 2, 3]);

    final medPhoto = File('${dir.path}/pill.jpg')..writeAsBytesSync([4, 5, 6]);
    final med = Medication(
      id: 'm',
      name: 'X',
      everyMinutes: 60,
      startsAt: DateTime(2026, 1, 1),
    );

    final withPhoto = Pet(id: 'p', name: 'Luna', photoPath: photo.path);
    final icon = NotificationService.androidDetails(withPhoto, med).largeIcon;
    expect(icon, isA<FilePathAndroidBitmap>());
    expect((icon as FilePathAndroidBitmap).data, photo.path);
    // No medicine photo: plain text, no big picture.
    expect(NotificationService.androidDetails(withPhoto, med).styleInformation,
        isNull);

    // With a medicine photo it is the big picture, keeping the text readable.
    final style = NotificationService.androidDetails(
      withPhoto,
      med.copyWith(photoPath: medPhoto.path),
    ).styleInformation as BigPictureStyleInformation;
    expect((style.bigPicture as FilePathAndroidBitmap).data, medPhoto.path);
    expect(style.summaryText, 'Es hora de darle X a Luna');

    // Files that are gone are ignored.
    photo.deleteSync();
    medPhoto.deleteSync();
    final gone = NotificationService.androidDetails(
      withPhoto,
      med.copyWith(photoPath: medPhoto.path),
    );
    expect(gone.largeIcon, isNull);
    expect(gone.styleInformation, isNull);
    expect(
        NotificationService.androidDetails(Pet(id: 'q', name: 'X'), med).largeIcon,
        isNull);
  });

  test('Pet keeps, replaces and clears its photo', () {
    final pet = Pet(id: 'p', name: 'Luna', photoPath: '/a.jpg');
    expect(Pet.fromJson(pet.toJson()).photoPath, '/a.jpg');
    expect(pet.copyWith(name: 'Nina').photoPath, '/a.jpg');
    expect(pet.copyWith(photoPath: '/b.jpg').photoPath, '/b.jpg');
    expect(pet.copyWith(clearPhoto: true).photoPath, isNull);
  });

  test('alarms are planned by dose number and capped', () {
    final med = Medication(
      id: 'm',
      name: 'X',
      everyMinutes: 480,
      startsAt: DateTime(2026, 1, 1, 8),
    );
    final now = DateTime(2026, 1, 1, 9);
    final plan = NotificationService.plannedDoses(med, now);
    expect(plan.length, NotificationService.dosesAhead);
    expect(plan.first.$1, 1);
    final base = NotificationService.baseId('m');
    expect(plan.first.$2, base + 1);

    // Later, the same dose keeps the same alarm id.
    final later = NotificationService.plannedDoses(med, DateTime(2026, 1, 1, 20));
    expect(later.first.$1, 2);
    expect(later.map((p) => p.$2), contains(base + 2));

    // Every 6 h until a set date: alarms stop at the end of the treatment.
    final sixHours = med.copyWith(
      everyMinutes: 360,
      endsAt: DateTime(2026, 1, 3, 8),
    );
    final times = NotificationService.plannedDoses(sixHours, now)
        .map((p) => sixHours.doseTime(p.$1))
        .toList();
    expect(times.first, DateTime(2026, 1, 1, 14));
    expect(times.last, DateTime(2026, 1, 3, 8));
    expect(times.length, 8);

    // A finished treatment has no alarms.
    final ended = med.copyWith(endsAt: DateTime(2026, 1, 1, 12));
    expect(NotificationService.plannedDoses(ended, now), isEmpty);
  });

  test('Medication keeps, replaces and clears its photo', () {
    final med = Medication(
      id: 'm',
      name: 'X',
      everyMinutes: 60,
      startsAt: DateTime(2026, 1, 1),
      photoPath: '/a.jpg',
    );
    expect(Medication.fromJson(med.toJson()).photoPath, '/a.jpg');
    expect(med.copyWith(dose: '1').photoPath, '/a.jpg');
    expect(med.copyWith(photoPath: '/b.jpg').photoPath, '/b.jpg');
    expect(med.copyWith(clearPhoto: true).photoPath, isNull);
    // Data saved before photos existed has none.
    expect(
      Medication.fromJson({
        'id': 'm',
        'name': 'X',
        'everyMinutes': 60,
        'startsAt': DateTime(2026, 1, 1).toIso8601String(),
      }).photoPath,
      isNull,
    );
  });

  test('appointments link to Google Maps by address or by pasted link', () {
    final date = DateTime(2026, 1, 1, 10);
    final bySearch = VetVisit(
      id: 'v',
      clinic: 'Peluquería Can & Co',
      date: date,
      kind: AppointmentKind.grooming,
      address: 'Av. Siempreviva 742',
    );
    final uri = bySearch.mapsUri!;
    expect(uri.host, 'www.google.com');
    expect(uri.path, '/maps/search/');
    expect(uri.queryParameters['query'], 'Peluquería Can & Co, Av. Siempreviva 742');
    expect(bySearch.locationText, 'Peluquería Can & Co, Av. Siempreviva 742');

    final byLink = VetVisit(
      id: 'v',
      clinic: 'Vet Sur',
      date: date,
      address: 'https://maps.app.goo.gl/abc123',
    );
    expect(byLink.mapsUri.toString(), 'https://maps.app.goo.gl/abc123');

    // Only the name: still searchable. Nothing at all: no link.
    expect(VetVisit(id: 'v', clinic: 'Vet Sur', date: date).mapsUri, isNotNull);
    expect(VetVisit(id: 'v', clinic: ' ', date: date).mapsUri, isNull);
  });

  test('appointments keep their kind and address; old data defaults to the vet', () {
    final visit = VetVisit(
      id: 'v',
      clinic: 'Spa',
      date: DateTime(2026, 1, 1),
      kind: AppointmentKind.grooming,
      address: 'Calle 1',
    );
    final back = VetVisit.fromJson(visit.toJson());
    expect(back.kind, AppointmentKind.grooming);
    expect(back.address, 'Calle 1');

    final old = VetVisit.fromJson({
      'id': 'v',
      'clinic': 'Vet',
      'date': DateTime(2026, 1, 1).toIso8601String(),
    });
    expect(old.kind, AppointmentKind.vet);
    expect(old.address, '');
  });

  testWidgets('medication card shows the photo above the description', (tester) async {
    await initializeDateFormatting('es');
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final dir = Directory.systemTemp.createTempSync('pettime_card');
    addTearDown(() => dir.deleteSync(recursive: true));
    final photo = File('${dir.path}/pill.png')
      ..writeAsBytesSync(base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='));
    final med = Medication(
      id: 'm',
      name: 'Amoxicilina',
      dose: '1 comprimido',
      everyMinutes: 480,
      startsAt: DateTime.now().add(const Duration(hours: 1)),
      photoPath: photo.path,
    );
    final state = PetsState();
    await state.savePet(Pet(id: 'p', name: 'Luna', medications: [med]));

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MedicationCard(petId: 'p', medication: med),
            ),
          ),
        ),
      ),
    );

    final image = tester.getTopLeft(find.byType(Image));
    final name = tester.getTopLeft(find.text('Amoxicilina'));
    final dose = tester.getTopLeft(find.text('1 comprimido'));
    final actions = tester.getTopLeft(find.text('Dada ahora'));
    expect(image.dy, lessThan(name.dy));
    expect(name.dy, lessThan(dose.dy));
    expect(dose.dy, lessThan(actions.dy));
    expect(find.text('cada 8 h'), findsOneWidget);
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
      MultiProvider(providers: [ChangeNotifierProvider.value(value: state), ChangeNotifierProvider(create: (_) => LanguageState())], child: const PetTimeApp()),
    );
    // Opens on "Hoy"; the list of pets is in its own tab.
    expect(find.text('Agregá tu primera mascota en la pestaña Mascotas'),
        findsOneWidget);
    await tester.tap(find.text('Mascotas'));
    await tester.pumpAndSettle();
    expect(find.text('Todavía no agregaste ninguna mascota'), findsOneWidget);

    await tester.tap(find.text('Mascota'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Luna');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Luna'), findsOneWidget);
  });
}
