import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pettime_app/models/agenda.dart';
import 'package:pettime_app/models/caregiver.dart';
import 'package:pettime_app/models/diary_entry.dart';
import 'package:pettime_app/models/medication.dart';
import 'package:pettime_app/models/pet.dart';
import 'package:pettime_app/models/pet_merge.dart';
import 'package:pettime_app/models/pet_share.dart';
import 'package:pettime_app/models/walk.dart';
import 'package:pettime_app/screens/diary_entry_form_screen.dart';
import 'package:pettime_app/screens/pet_detail_screen.dart';
import 'package:pettime_app/screens/today_screen.dart';
import 'package:pettime_app/services/backup_service.dart';
import 'package:pettime_app/services/family_sync.dart';
import 'package:pettime_app/services/notification_service.dart';
import 'package:pettime_app/services/pettime_api.dart';
import 'package:pettime_app/services/vet_report.dart';
import 'package:pettime_app/state/pets_state.dart';
import 'package:pettime_app/widgets/caregiver_sheet.dart';
import 'package:pettime_app/widgets/diary_section.dart';
import 'package:pettime_app/widgets/walk_section.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Walk walk(String id, DateTime date, int minutes, {double? km}) =>
    Walk(id: id, date: date, minutes: minutes, km: km);

/// A fake sixsevenweb.com that keeps one shared pet, like family/share.php.
class FakeServer {
  Map<String, dynamic>? pet;
  int version = 0;

  late final client = MockClient((request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    Map<String, dynamic> current() => {
      'ok': true,
      'code': 'K7Q2M9XP',
      'version': version,
      'pet': pet,
      'photoUrl': null,
    };
    switch (body['action']) {
      case 'create':
        pet = body['pet'] as Map<String, dynamic>;
        version = 1;
        return http.Response(
          jsonEncode({
            'ok': true,
            'code': 'K7Q2M9XP',
            'ownerKey': 'k',
            'version': 1,
          }),
          200,
        );
      case 'get':
        if (pet == null || body['code'] != 'K7Q2M9XP') {
          return http.Response(
            '{"ok":false,"error":"No existe ese código."}',
            404,
          );
        }
        return http.Response(jsonEncode(current()), 200);
      case 'update':
        if (body['baseVersion'] != version) {
          return http.Response(
            jsonEncode({...current(), 'ok': false, 'error': 'conflict'}),
            409,
          );
        }
        pet = body['pet'] as Map<String, dynamic>;
        version++;
        return http.Response(jsonEncode({'ok': true, 'version': version}), 200);
      case 'stop':
        pet = null;
        return http.Response('{"ok":true}', 200);
    }
    return http.Response('{"ok":false}', 422);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() => initializeDateFormatting('es'));

  group('paseos', () {
    final today = DateTime(2026, 10, 19, 12);

    test('se guardan con la mascota; los datos viejos cargan', () {
      final pet = Pet(
        id: 'p',
        name: 'Luna',
        walks: [walk('a', DateTime(2026, 10, 19, 8), 30, km: 2.5)],
        walkReminder: const WalkReminder(hour: 18, minute: 30),
      );
      final back = Pet.fromJson(pet.toJson());
      expect(back.walks.single.km, 2.5);
      expect(back.walkReminder!.label, '18:30');
      final old = Pet.fromJson(
        pet.toJson()
          ..remove('walks')
          ..remove('walkReminder'),
      );
      expect(old.walks, isEmpty);
      expect(old.walkReminder, isNull);
    });

    test('totales, racha y textos', () {
      final walks = [
        walk('a', DateTime(2026, 10, 19, 8), 30),
        walk('b', DateTime(2026, 10, 19, 19), 15),
        walk('c', DateTime(2026, 10, 18, 9), 40),
        walk('d', DateTime(2026, 10, 17, 9), 20),
        walk('e', DateTime(2026, 10, 15, 9), 60),
      ];
      expect(walksOn(walks, today).length, 2);
      expect(minutesLast7Days(walks, today), [0, 0, 60, 0, 20, 40, 45]);
      expect(walkStreak(walks, today), 3);
      // Hoy sin paseo todavía no corta la racha.
      expect(walkStreak(walks.skip(2), today), 2);
      expect(formatMinutes(45), '45 min');
      expect(formatMinutes(60), '1 h');
      expect(formatMinutes(80), '1 h 20 min');
      expect(parseKm('2,5'), 2.5);
      expect(parseKm('0'), isNull);
      expect(formatKm(3), '3 km');
      expect(formatKm(2.5), '2,5 km');
    });

    test('el aviso salta los días que ya salió', () {
      final pet = Pet(
        id: 'p',
        name: 'Luna',
        walkReminder: const WalkReminder(hour: 18),
      );
      final planned = NotificationService.plannedWalkReminders(pet, today);
      expect(planned.length, NotificationService.walkDaysAhead);
      expect(planned.first.$1, DateTime(2026, 10, 19, 18));
      expect({for (final p in planned) p.$2}.length, planned.length);

      final walked = pet.copyWith(
        walks: [walk('a', DateTime(2026, 10, 19, 8), 30)],
      );
      final after = NotificationService.plannedWalkReminders(walked, today);
      expect(after.first.$1, DateTime(2026, 10, 20, 18));
      // Los avisos que quedan conservan su número.
      expect(after.first.$2, planned[1].$2);

      expect(
        NotificationService.plannedWalkReminders(
          Pet(id: 'x', name: 'X'),
          today,
        ),
        isEmpty,
      );
      expect(petsToWalk([pet, walked], today).map((p) => p.name), ['Luna']);
    });

    test('guardar y borrar desde el estado', () async {
      final state = PetsState();
      await state.savePet(Pet(id: 'p', name: 'Luna'));
      await state.saveWalk('p', walk('a', DateTime(2026, 10, 18), 20));
      await state.saveWalk('p', walk('b', DateTime(2026, 10, 19), 30));
      expect(state.byId('p')!.walks.map((w) => w.id), ['b', 'a']);
      await state.setWalkReminder('p', const WalkReminder(hour: 19));
      expect(state.byId('p')!.walkReminder!.hour, 19);
      await state.deleteWalk('p', 'b');
      await state.setWalkReminder('p', null);
      expect(state.byId('p')!.walks.single.id, 'a');
      expect(state.byId('p')!.walkReminder, isNull);
    });

    testWidgets('la sección se ve con letra grande', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final pet = Pet(
        id: 'p',
        name: 'Luna',
        walks: [
          walk('a', DateTime(2026, 10, 19, 8), 30),
          walk('b', DateTime(2026, 10, 18, 8), 50),
        ],
        walkReminder: const WalkReminder(hour: 18),
      );
      final state = PetsState();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 900),
              textScaler: TextScaler.linear(1.6),
            ),
            child: MaterialApp(
              home: Scaffold(
                body: ListView(
                  children: [WalkSection(pet: pet, now: today)],
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Hoy: 1 paseo · 30 min'), findsOneWidget);
      expect(find.text('Todos los días a las 18:00'), findsOneWidget);
    });

    testWidgets('"Hoy" muestra a quién falta sacar', (tester) async {
      final state = PetsState();
      await state.savePet(
        Pet(id: 'p', name: 'Luna', walkReminder: const WalkReminder(hour: 18)),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(home: TodayScreen(clock: () => today)),
        ),
      );
      expect(find.text('Todavía no salió hoy'), findsOneWidget);
    });
  });

  group('diario', () {
    late Directory tmp;
    setUp(
      () async => tmp = await Directory.systemTemp.createTemp('pettime_diary'),
    );
    tearDown(() => tmp.delete(recursive: true));

    DiaryEntry entry({List<String> photos = const []}) => DiaryEntry(
      id: 'd1',
      date: DateTime(2026, 10, 19, 9),
      symptoms: const [Symptom.vomit, Symptom.lethargy],
      text: 'Vomitó dos veces',
      photos: photos,
    );

    test('se guarda con la mascota; los datos viejos cargan', () {
      final pet = Pet(
        id: 'p',
        name: 'Luna',
        diary: [
          entry(photos: ['/x/1.jpg']),
        ],
      );
      final back = Pet.fromJson(pet.toJson()).diary.single;
      expect(back.symptoms, [Symptom.vomit, Symptom.lethargy]);
      expect(back.symptomsLabel, 'Vómitos, Decaído');
      expect(back.photos, ['/x/1.jpg']);
      expect(Pet.fromJson(pet.toJson()..remove('diary')).diary, isEmpty);
    });

    test(
      'las fotos no se mandan a la familia y cada celular guarda las suyas',
      () {
        final pet = Pet(
          id: 'p',
          name: 'Luna',
          diary: [
            entry(photos: ['/x/1.jpg']),
          ],
        );
        final json = sharePayload(pet);
        expect((json['diary'] as List).single.containsKey('photos'), isFalse);
        final back = petFromShared(
          json,
          local: pet,
          share: const PetShare(code: 'K7Q2M9XP', version: 2),
        );
        expect(back.diary.single.photos, ['/x/1.jpg']);
        expect(back.diary.single.text, 'Vomitó dos veces');

        final theirs = pet.copyWith(
          diary: [
            DiaryEntry(
              id: 'd2',
              date: DateTime(2026, 10, 20),
              text: 'Comió bien',
            ),
          ],
        );
        expect(mergePets(pet, theirs).diary.map((d) => d.id), ['d2', 'd1']);
      },
    );

    test('borrar una anotación borra sus fotos', () async {
      final photo = File('${tmp.path}/d.jpg')..writeAsBytesSync([1]);
      final state = PetsState();
      await state.savePet(Pet(id: 'p', name: 'Luna'));
      await state.saveDiaryEntry('p', entry(photos: [photo.path]));
      expect(state.byId('p')!.diary.single.photos, [photo.path]);
      await state.deleteDiaryEntry('p', 'd1');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(state.byId('p')!.diary, isEmpty);
      expect(photo.existsSync(), isFalse);
    });

    test('la copia de seguridad lleva las fotos del diario', () {
      final photo = File('${tmp.path}/origen/d_1.jpg')
        ..createSync(recursive: true)
        ..writeAsBytesSync([7, 8, 9]);
      final zip = BackupService.buildZip([
        Pet(
          id: 'p',
          name: 'Luna',
          diary: [
            entry(photos: [photo.path, '${tmp.path}/no-existe.jpg']),
          ],
        ),
      ]);
      expect(
        ZipDecoder().decodeBytes(zip).findFile('fotos/d_1.jpg'),
        isNotNull,
      );
      final restored = BackupService.readZip(
        zip,
        Directory('${tmp.path}/nuevo'),
      ).single.diary.single;
      expect(restored.photos.length, 1);
      expect(File(restored.photos.single).readAsBytesSync(), [7, 8, 9]);
    });

    test('la ficha del veterinario lleva el diario y los paseos', () async {
      final now = DateTime(2026, 10, 19, 12);
      final pet = Pet(
        id: 'p',
        name: 'Luna',
        diary: [
          entry(),
          DiaryEntry(id: 'old', date: DateTime(2026, 6, 1), text: 'Hace mucho'),
        ],
        walks: [
          walk('a', DateTime(2026, 10, 19), 30, km: 2),
          walk('b', DateTime(2026, 10, 10), 30),
        ],
      );
      expect(VetReport.diaryForReport(pet, now).map((d) => d.id), ['d1']);
      expect(
        VetReport.walkSummary(pet, now),
        '2 paseos en los últimos 30 días · 2 min por día en promedio · 2 km en total',
      );
      expect(VetReport.walkSummary(Pet(id: 'x', name: 'X'), now), isNull);
    });

    testWidgets('la sección muestra las últimas anotaciones', (tester) async {
      final pet = Pet(
        id: 'p',
        name: 'Luna',
        diary: [
          for (var i = 0; i < 5; i++)
            DiaryEntry(
              id: 'd$i',
              date: DateTime(2026, 10, 19 - i),
              text: 'Nota $i',
            ),
        ],
      );
      final state = PetsState();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
            home: Scaffold(
              body: ListView(children: [DiarySection(pet: pet)]),
            ),
          ),
        ),
      );
      expect(find.text('Nota 0'), findsOneWidget);
      expect(find.text('Nota 3'), findsNothing);
      expect(find.text('Ver todo el diario (5)'), findsOneWidget);
    });
  });

  group('cuidador', () {
    Medication amoxi() => Medication(
      id: 'm1',
      name: 'Amoxicilina',
      everyMinutes: 480,
      startsAt: DateTime(2026, 10, 18, 8),
    );

    test('el código del cuidador esconde el de la familia', () {
      final code = CaregiverCode.encode('K7Q2M9XP', 'AB3D');
      expect(code.length, 12);
      expect(code.startsWith('K7Q2M9XP'), isFalse);
      expect(code.contains('K7Q2M9XP'), isFalse);
      expect(CaregiverCode.decode(code), ('K7Q2M9XP', 'AB3D'));
      expect(CaregiverCode.display(code).split('-').length, 3);
      expect(CaregiverCode.newId().length, 4);
    });

    test(
      'combinar: un cuidado terminado en cualquier celular queda terminado',
      () {
        final until = DateTime(2026, 10, 25, 23, 59);
        final ana = Caregiver(id: 'AAAA', name: 'Ana', until: until);
        final ended = ana.end(DateTime(2026, 10, 20));
        final beto = Caregiver(id: 'BBBB', name: 'Beto', until: until);
        final merged = mergeCaregivers([ana], [ended, beto]);
        expect(merged.map((c) => c.id), ['AAAA', 'BBBB']);
        expect(merged.first.endedAt, DateTime(2026, 10, 20));
        expect(mergeCaregivers([ended], [ana]).single.endedAt, isNotNull);
      },
    );

    test('en el celular del cuidador las alarmas paran cuando termina', () {
      final until = DateTime(2026, 10, 19, 23, 59);
      final pet = Pet(
        id: 'p',
        name: 'Luna',
        medications: [amoxi()],
        walkReminder: const WalkReminder(hour: 18),
        caregivers: [Caregiver(id: 'AAAA', name: 'Ana', until: until)],
        share: const PetShare(
          code: 'K7Q2M9XP',
          version: 1,
          caregiverId: 'AAAA',
        ),
      );
      final now = DateTime(2026, 10, 19, 9);
      expect(pet.careEndsAt, until);
      expect(pet.careFinished(now), isFalse);
      expect(pet.careFinished(DateTime(2026, 10, 20)), isTrue);
      final doses = NotificationService.plannedDoses(
        pet.medications.single,
        now,
        until: pet.careEndsAt,
      );
      // La de las 16 sí; la de las 0 ya es después del cuidado.
      expect(doses.length, 1);
      expect(NotificationService.plannedWalkReminders(pet, now).length, 1);
      // En los celulares de la familia siguen como siempre.
      final family = pet.copyWith(
        share: const PetShare(code: 'K7Q2M9XP', version: 1),
      );
      expect(family.careEndsAt, isNull);
      expect(
        NotificationService.plannedDoses(family.medications.single, now).length,
        NotificationService.dosesAhead,
      );
    });

    test('dejarla, sumarse con el código y que se vaya sola', () async {
      final server = FakeServer();
      final api = PetTimeApi(
        client: server.client,
        base: 'https://x/api/pettime',
      );
      var now = DateTime(2026, 10, 19, 10);

      // La dueña comparte y agrega a Ana hasta el 25.
      final owner = PetsState();
      final ownerSync = FamilySync(api: api, clock: () => now);
      ownerSync.attach(owner);
      await owner.savePet(Pet(id: 'p', name: 'Luna', medications: [amoxi()]));
      await ownerSync.share(owner.byId('p')!);
      final ana = Caregiver(
        id: 'AAAA',
        name: 'Ana',
        until: DateTime(2026, 10, 25, 23, 59),
      );
      await owner.saveCaregiver('p', ana);
      expect(await ownerSync.sendNow('p'), isTrue);

      // Ana se suma con su código.
      SharedPreferences.setMockInitialValues({});
      final carer = PetsState();
      final carerSync = FamilySync(api: api, clock: () => now);
      carerSync.attach(carer);
      final code = CaregiverCode.encode('K7Q2M9XP', 'AAAA');
      final joined = await carerSync.join(code);
      expect(joined.share!.isCaregiver, isTrue);
      expect(joined.careEndsAt, ana.until);

      // Un código que no existe o que venció no sirve.
      SharedPreferences.setMockInitialValues({});
      final other = PetsState();
      final otherSync = FamilySync(
        api: api,
        clock: () => DateTime(2026, 10, 30),
      );
      otherSync.attach(other);
      await expectLater(
        otherSync.join(CaregiverCode.encode('K7Q2M9XP', 'ZZZZ')),
        throwsA(isA<ApiException>()),
      );
      await expectLater(otherSync.join(code), throwsA(isA<ApiException>()));
      expect(other.pets, isEmpty);

      // Ana da una toma y se sincroniza; a la dueña le llega.
      await carer.logDose('p', 'm1', DateTime(2026, 10, 19, 16));
      await carerSync.syncAll();
      await ownerSync.syncAll();
      expect(owner.byId('p')!.medications.single.givenDoses, [
        DateTime(2026, 10, 19, 16),
      ]);

      // Termina el cuidado: Luna sale del celular de Ana, no del de la dueña.
      now = DateTime(2026, 10, 26, 9);
      await carerSync.syncAll();
      expect(carer.pets, isEmpty);
      await ownerSync.syncAll();
      expect(owner.byId('p'), isNotNull);

      ownerSync.pause();
      carerSync.pause();
      otherSync.pause();
    });

    test(
      'la dueña lo termina antes; sin internet espera para mandar lo último',
      () async {
        final server = FakeServer();
        final api = PetTimeApi(
          client: server.client,
          base: 'https://x/api/pettime',
        );
        var now = DateTime(2026, 10, 19, 10);
        final owner = PetsState();
        final ownerSync = FamilySync(api: api, clock: () => now);
        ownerSync.attach(owner);
        await owner.savePet(Pet(id: 'p', name: 'Luna'));
        await ownerSync.share(owner.byId('p')!);
        await owner.saveCaregiver(
          'p',
          Caregiver(
            id: 'AAAA',
            name: 'Ana',
            until: DateTime(2026, 10, 25, 23, 59),
          ),
        );
        await ownerSync.sendNow('p');

        SharedPreferences.setMockInitialValues({});
        final carer = PetsState();
        final carerSync = FamilySync(api: api, clock: () => now);
        carerSync.attach(carer);
        await carerSync.join(CaregiverCode.encode('K7Q2M9XP', 'AAAA'));

        await owner.endCaregiver('p', 'AAAA', now);
        await ownerSync.sendNow('p');
        await carerSync.syncAll();
        expect(carer.pets, isEmpty);

        // Sin internet y con cambios sin mandar, espera unos días.
        final offline = FamilySync(
          api: PetTimeApi(
            client: MockClient(
              (_) async => throw const SocketException('sin red'),
            ),
            base: 'https://x/api/pettime',
          ),
          clock: () => now,
        );
        final carer2 = PetsState();
        offline.attach(carer2);
        await carer2.applySharedPet(
          Pet(
            id: 'q',
            name: 'Toby',
            caregivers: [
              Caregiver(id: 'BBBB', name: 'Ana', until: DateTime(2026, 10, 18)),
            ],
            share: const PetShare(
              code: 'K7Q2M9XP',
              version: 1,
              caregiverId: 'BBBB',
              dirty: true,
            ),
          ),
        );
        await offline.syncAll();
        expect(carer2.byId('q'), isNotNull);
        now = DateTime(2026, 10, 22);
        await offline.syncAll();
        expect(carer2.byId('q'), isNull);

        ownerSync.pause();
        carerSync.pause();
        offline.pause();
      },
    );
  });

  group('pantallas con letra grande', () {
    Future<PetsState> show(WidgetTester tester, Pet pet, Widget screen) async {
      tester.view.physicalSize = const Size(360, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final state = PetsState();
      await state.savePet(pet);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 1600),
              textScaler: TextScaler.linear(1.6),
            ),
            child: MaterialApp(home: screen),
          ),
        ),
      );
      await tester.pump();
      return state;
    }

    final now = DateTime.now();
    final luna = Pet(
      id: 'p',
      name: 'Luna',
      walks: [
        walk('a', now, 30),
        walk('b', now.subtract(const Duration(days: 1)), 45),
      ],
      walkReminder: const WalkReminder(hour: 18),
      diary: [
        DiaryEntry(
          id: 'd1',
          date: now,
          symptoms: const [Symptom.vomit, Symptom.drinksMuch],
          text: 'Vomitó a la mañana',
        ),
      ],
      caregivers: [
        Caregiver(
          id: 'AAAA',
          name: 'Ana',
          until: now.add(const Duration(days: 5)),
        ),
      ],
      share: const PetShare(code: 'K7Q2M9XP', version: 1, ownerKey: 'k'),
    );

    testWidgets('la ficha con paseos, diario y cuidador', (tester) async {
      await show(tester, luna, const PetDetailScreen(petId: 'p'));
      expect(tester.takeException(), isNull);
      expect(find.text('La cuida Ana'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Vomitó a la mañana'), 300);
      expect(tester.takeException(), isNull);
    });

    testWidgets('la ficha en el celular del cuidador', (tester) async {
      final cared = luna
          .copyWith(
            caregivers: [],
            share: const PetShare(
              code: 'K7Q2M9XP',
              version: 1,
              caregiverId: 'AAAA',
            ),
          )
          .copyWith(caregivers: luna.caregivers);
      await show(tester, cared, const PetDetailScreen(petId: 'p'));
      expect(tester.takeException(), isNull);
      expect(find.text('Cuidás a Luna'), findsOneWidget);
      expect(find.text('La cuida Ana'), findsNothing);
    });

    testWidgets('anotar en el diario', (tester) async {
      final state = await show(
        tester,
        Pet(id: 'p', name: 'Luna'),
        const DiaryEntryFormScreen(petId: 'p'),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Tos'));
      await tester.enterText(find.byType(TextField), 'Tose de noche');
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Guardar'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Guardar'));
      await tester.pump();
      final d = state.byId('p')!.diary.single;
      expect(d.symptoms, [Symptom.cough]);
      expect(d.text, 'Tose de noche');
    });

    testWidgets('anotar un paseo', (tester) async {
      final state = await show(
        tester,
        Pet(id: 'p', name: 'Luna'),
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showWalkDialog(context, state0(context)),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('45 min'));
      await tester.pump();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(state.byId('p')!.walks.single.minutes, 45);
    });

    testWidgets('la hoja del cuidador', (tester) async {
      await show(
        tester,
        luna,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showCaregiverSheet(context, 'p'),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Ana'), findsOneWidget);
      expect(find.text('Agregar cuidador'), findsOneWidget);
      expect(
        caregiverInviteText(luna, luna.caregivers.single),
        contains(
          CaregiverCode.display(CaregiverCode.encode('K7Q2M9XP', 'AAAA')),
        ),
      );
    });
  });
}

Pet state0(BuildContext context) =>
    Provider.of<PetsState>(context, listen: false).byId('p')!;
