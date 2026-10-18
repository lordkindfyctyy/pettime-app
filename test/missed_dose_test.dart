import 'package:flutter_test/flutter_test.dart';
import 'package:pettime_app/models/medication.dart';
import 'package:pettime_app/models/pet.dart';
import 'package:pettime_app/services/notification_service.dart';

void main() {
  final med = Medication(
    id: 'm',
    name: 'Amoxicilina',
    dose: '1 comp.',
    everyMinutes: 480,
    startsAt: DateTime(2026, 10, 18, 8),
  );

  test('avisa a los 30 minutos si la toma no se marcó', () {
    final planned =
        NotificationService.plannedFollowUps(med, DateTime(2026, 10, 18, 8, 10));
    final (k, id, at) = planned.first;
    expect(k, 0);
    expect(at, DateTime(2026, 10, 18, 8, 30));
    expect(id, NotificationService.followUpBaseId('m'));
    expect(planned.length, NotificationService.followUpsAhead);

    // Los ids no se pisan con los de las alarmas de las tomas.
    final doseIds = {
      for (final (_, id)
          in NotificationService.plannedDoses(med, DateTime(2026, 10, 18)))
        id,
    };
    expect(planned.any((p) => doseIds.contains(p.$2)), isFalse);
  });

  test('si la toma ya se dio no avisa, y no avisa lo que ya pasó', () {
    final given = med.copyWith(givenDoses: [DateTime(2026, 10, 18, 8, 5)]);
    expect(
      NotificationService.plannedFollowUps(given, DateTime(2026, 10, 18, 8, 10))
          .first
          .$3,
      DateTime(2026, 10, 18, 16, 30),
    );
    expect(
      NotificationService.plannedFollowUps(med, DateTime(2026, 10, 18, 8, 45))
          .first
          .$3,
      DateTime(2026, 10, 18, 16, 30),
    );
  });

  test('no avisa en medicaciones de menos de una hora', () {
    expect(
      NotificationService.plannedFollowUps(
        med.copyWith(everyMinutes: 30),
        DateTime(2026, 10, 18, 8),
      ),
      isEmpty,
    );
  });

  test('no avisa después del fin del tratamiento', () {
    final short = med.copyWith(endsAt: DateTime(2026, 10, 18, 16));
    final planned =
        NotificationService.plannedFollowUps(short, DateTime(2026, 10, 18, 8, 10));
    expect([for (final p in planned) p.$3],
        [DateTime(2026, 10, 18, 8, 30), DateTime(2026, 10, 18, 16, 30)]);
  });

  test('texto del aviso y toma más cercana', () {
    final pet = Pet(id: 'p', name: 'Pancho');
    expect(
      NotificationService.followUpBody(pet, med, DateTime(2026, 10, 18, 8)),
      '¿Ya le diste Amoxicilina (1 comp.) a Pancho? Era a las 08:00',
    );
    expect(
      NotificationService.nearestDoseIndex(med, DateTime(2026, 10, 18, 15, 40)),
      1,
    );
    expect(
      NotificationService.nearestDoseIndex(med, DateTime(2026, 10, 18, 8, 20)),
      0,
    );
  });
}
