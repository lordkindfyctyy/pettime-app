import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pettime_app/models/agenda.dart';
import 'package:pettime_app/models/health_record.dart';
import 'package:pettime_app/models/medication.dart';
import 'package:pettime_app/models/pet.dart';
import 'package:pettime_app/models/vet_visit.dart';
import 'package:pettime_app/screens/health_record_form_screen.dart';
import 'package:pettime_app/screens/today_screen.dart';
import 'package:pettime_app/services/notification_service.dart';
import 'package:pettime_app/state/pets_state.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

HealthRecord rec(
  String id,
  String name,
  DateTime applied, [
  DateTime? due,
  HealthKind kind = HealthKind.vaccine,
]) =>
    HealthRecord(id: id, kind: kind, name: name, appliedOn: applied, nextDue: due);

Future<void> tapSave(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.text('Guardar'), 200,
      scrollable: find.byType(Scrollable).first);
  await tester.tap(find.text('Guardar'));
  await tester.pumpAndSettle();
}

Future<void> pumpScreen(WidgetTester tester, PetsState state, Widget screen) async {
  await initializeDateFormatting('es');
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: state,
    child: MaterialApp(home: screen),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('libreta de vacunas', () {
    test('se guarda con la mascota; los datos viejos sin libreta cargan', () {
      final pet = Pet(id: 'p', name: 'Luna', records: [
        rec('r', 'Antirrábica', DateTime(2026, 3, 1), DateTime(2027, 3, 1)),
      ]);
      final back = Pet.fromJson(pet.toJson());
      expect(back.records.single.name, 'Antirrábica');
      expect(back.records.single.nextDue, DateTime(2027, 3, 1));
      expect(back.records.single.kind, HealthKind.vaccine);

      final old = pet.toJson()..remove('records');
      expect(Pet.fromJson(old).records, isEmpty);
    });

    test('una aplicación nueva de lo mismo reemplaza a la anterior', () {
      final records = [
        rec('a', 'Antirrábica', DateTime(2025, 3, 1), DateTime(2026, 3, 1)),
        rec('b', 'antirrábica ', DateTime(2026, 3, 2), DateTime(2027, 3, 2)),
        rec('c', 'Pipeta', DateTime(2026, 9, 1), DateTime(2026, 10, 1),
            HealthKind.fleaTick),
        rec('d', 'Séxtuple', DateTime(2026, 1, 1)), // sin próxima
      ];
      expect(pendingRecords(records).map((r) => r.id), ['c', 'b']);
    });

    test('etiqueta de vencimiento', () {
      final now = DateTime(2026, 10, 17, 22);
      expect(dueLabel(DateTime(2026, 10, 17), now), 'Hoy');
      expect(dueLabel(DateTime(2026, 10, 18, 9), now), 'Mañana');
      expect(dueLabel(DateTime(2026, 10, 22), now), 'En 5 días');
      expect(dueLabel(DateTime(2026, 10, 16), now), 'Vencida ayer');
      expect(dueLabel(DateTime(2026, 10, 10), now), 'Vencida hace 7 días');
    });

    test('avisa 3 días antes y el mismo día a las 10, solo lo que falta', () {
      final pet = Pet(id: 'p', name: 'Luna', records: [
        rec('old', 'Antirrábica', DateTime(2025, 1, 1), DateTime(2026, 1, 1)),
        rec('new', 'Antirrábica', DateTime(2026, 1, 2), DateTime(2026, 11, 10)),
      ]);
      final planned =
          NotificationService.plannedRecordReminders(pet, DateTime(2026, 11, 8));
      // El de 3 días antes (7/11) ya pasó; queda el del día.
      expect(planned.length, 1);
      final (r, days, at, id) = planned.single;
      expect(r.id, 'new');
      expect(days, 0);
      expect(at, DateTime(2026, 11, 10, 10));
      expect(id, NotificationService.baseId('rec:new') + 1);
      expect(NotificationService.recordBody(pet, r, 3),
          'En 3 días le toca Antirrábica a Luna');

      final early =
          NotificationService.plannedRecordReminders(pet, DateTime(2026, 11, 1));
      expect([for (final p in early) p.$3],
          [DateTime(2026, 11, 7, 10), DateTime(2026, 11, 10, 10)]);
    });

    test('PetsState agrega, edita y borra aplicaciones', () async {
      final state = PetsState();
      await state.savePet(Pet(id: 'p', name: 'Luna'));
      await state.saveRecord('p', rec('r', 'Pipeta', DateTime(2026, 10, 1)));
      await state.saveRecord('p',
          rec('r', 'Pipeta', DateTime(2026, 10, 1), DateTime(2026, 11, 1)));
      expect(state.byId('p')!.records.single.nextDue, DateTime(2026, 11, 1));
      await state.deleteRecord('p', 'r');
      expect(state.byId('p')!.records, isEmpty);
    });
  });

  group('pantalla Hoy', () {
    final med = Medication(
      id: 'm',
      name: 'Amoxicilina',
      dose: '1 comp.',
      everyMinutes: 480,
      startsAt: DateTime(2026, 10, 1, 8),
    );

    test('arma las tomas del día y reconoce las ya dadas', () {
      final pet = Pet(id: 'p', name: 'Luna', medications: [
        med.copyWith(givenDoses: [DateTime(2026, 10, 17, 7, 50)]),
      ]);
      final slots = dosesOfDay([pet], DateTime(2026, 10, 17, 12));
      expect([for (final s in slots) s.time], [
        DateTime(2026, 10, 17),
        DateTime(2026, 10, 17, 8),
        DateTime(2026, 10, 17, 16),
      ]);
      expect([for (final s in slots) s.given], [false, true, false]);

      final now = DateTime(2026, 10, 17, 12, 30);
      expect(slots[0].missed(now), isTrue);
      expect(slots[2].canGive(now), isTrue); // 16 h: ventana desde las 12
      expect(slots[2].canGive(DateTime(2026, 10, 17, 11)), isFalse);
    });

    test('no muestra tomas antes del inicio ni después del fin', () {
      final pet = Pet(id: 'p', name: 'Luna', medications: [
        med.copyWith(
          startsAt: DateTime(2026, 10, 17, 10),
          endsAt: DateTime(2026, 10, 17, 18),
        ),
      ]);
      expect([for (final s in dosesOfDay([pet], DateTime(2026, 10, 17))) s.time],
          [DateTime(2026, 10, 17, 10), DateTime(2026, 10, 17, 18)]);
    });

    test('turnos del día y vacunas de la semana', () {
      final pet = Pet(
        id: 'p',
        name: 'Luna',
        visits: [
          VetVisit(id: 'v1', clinic: 'Vet Sur', date: DateTime(2026, 10, 17, 18)),
          VetVisit(id: 'v2', clinic: 'Vet Sur', date: DateTime(2026, 10, 18, 9)),
        ],
        records: [
          rec('a', 'Antirrábica', DateTime(2025, 10, 1), DateTime(2026, 10, 15)),
          rec('b', 'Pipeta', DateTime(2026, 9, 20), DateTime(2026, 10, 24),
              HealthKind.fleaTick),
          rec('c', 'Séxtuple', DateTime(2026, 1, 1), DateTime(2026, 12, 1)),
        ],
      );
      final now = DateTime(2026, 10, 17, 9);
      expect([for (final (_, v) in visitsOfDay([pet], now)) v.id], ['v1']);
      expect([for (final (_, r) in recordsDueSoon([pet], now)) r.id], ['a', 'b']);
    });

    testWidgets('marcar una toma como dada', (tester) async {
      final now = DateTime(2026, 10, 17, 15, 30);
      final state = PetsState();
      await state.savePet(Pet(id: 'p', name: 'Luna', medications: [med]));
      await pumpScreen(tester, state, TodayScreen(clock: () => now));

      expect(find.text('16:00 · Amoxicilina (1 comp.)'), findsOneWidget);
      expect(find.text('Medicación · faltan 3'), findsOneWidget);
      await tester.tap(find.text('Dar'));
      await tester.pumpAndSettle();

      expect(state.byId('p')!.medications.single.givenDoses, [now]);
      expect(find.text('Medicación · faltan 2'), findsOneWidget);
      expect(find.textContaining('Dada a las 15:30'), findsOneWidget);
    });

    testWidgets('sin mascotas invita a agregar una', (tester) async {
      await pumpScreen(tester, PetsState(), const TodayScreen());
      expect(find.text('Agregá tu primera mascota en la pestaña Mascotas'),
          findsOneWidget);
    });
  });

  testWidgets('el formulario guarda una vacuna con próxima dosis en 1 año',
      (tester) async {
    final state = PetsState();
    await state.savePet(Pet(id: 'p', name: 'Luna'));
    await pumpScreen(tester, state, const HealthRecordFormScreen(petId: 'p'));

    await tester.tap(find.text('Antirrábica'));
    await tester.tap(find.text('1 año'));
    await tester.pump();
    await tapSave(tester);

    final r = state.byId('p')!.records.single;
    final today = DateUtils.dateOnly(DateTime.now());
    expect(r.name, 'Antirrábica');
    expect(r.appliedOn, today);
    expect(r.nextDue, DateTime(today.year + 1, today.month, today.day));
  });

  testWidgets('registrar de nuevo repite el intervalo desde hoy', (tester) async {
    final state = PetsState();
    final old = rec('r', 'Pipeta', DateTime(2026, 1, 1), DateTime(2026, 1, 31),
        HealthKind.fleaTick);
    await state.savePet(Pet(id: 'p', name: 'Luna', records: [old]));
    await pumpScreen(
        tester, state, HealthRecordFormScreen(petId: 'p', repeatOf: old));
    await tapSave(tester);

    final records = state.byId('p')!.records;
    expect(records.length, 2);
    final today = DateUtils.dateOnly(DateTime.now());
    expect(records.last.kind, HealthKind.fleaTick);
    expect(records.last.nextDue, today.add(const Duration(days: 30)));
    expect(pendingRecords(records).single.id, records.last.id);
  });
}
