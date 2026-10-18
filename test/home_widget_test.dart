import 'package:flutter_test/flutter_test.dart';
import 'package:pettime_app/models/medication.dart';
import 'package:pettime_app/models/pet.dart';
import 'package:pettime_app/services/home_widget_service.dart';

Pet pancho({List<DateTime>? given}) => Pet(
      id: 'p',
      name: 'Pancho',
      medications: [
        Medication(
          id: 'm',
          name: 'Amoxicilina',
          dose: '1 comprimido',
          everyMinutes: 8 * 60,
          startsAt: DateTime(2026, 10, 18, 6),
          endsAt: DateTime(2026, 10, 19, 23),
          givenDoses: given,
        ),
      ],
    );

void main() {
  test('muestra las tomas pendientes, sin las dadas ni las vencidas', () {
    // 10:00: la de las 6 ya pasó su ventana (hasta las 10); quedan 14 y 22
    // de hoy, y 6, 14 y 22 de mañana.
    final now = DateTime(2026, 10, 18, 10, 30);
    final doses = upcomingWidgetDoses([pancho()], now);
    expect([for (final d in doses) d.time], [
      DateTime(2026, 10, 18, 14),
      DateTime(2026, 10, 18, 22),
      DateTime(2026, 10, 19, 6),
      DateTime(2026, 10, 19, 14),
      DateTime(2026, 10, 19, 22),
    ]);
    expect(doses.first.title, 'Pancho · Amoxicilina');
    expect(doses.first.detail, '1 comprimido');
    expect(doses.first.until, DateTime(2026, 10, 18, 18));

    // Dada a las 13:50: la de las 14 ya no aparece.
    final given = upcomingWidgetDoses(
      [pancho(given: [DateTime(2026, 10, 18, 13, 50)])],
      DateTime(2026, 10, 18, 13, 55),
    );
    expect(given.first.time, DateTime(2026, 10, 18, 22));
  });

  test('se actualiza cuando sale una toma y a la medianoche', () {
    final now = DateTime(2026, 10, 18, 10, 30);
    final times = widgetRefreshTimes(upcomingWidgetDoses([pancho()], now), now);
    expect(times.take(3), [
      DateTime(2026, 10, 18, 18),
      DateTime(2026, 10, 19),
      DateTime(2026, 10, 19, 2),
    ]);
    expect(times.every((t) => t.isAfter(now)), isTrue);
  });
}
