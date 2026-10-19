import 'health_record.dart';
import 'medication.dart';
import 'pet.dart';
import 'supply.dart';
import 'vet_visit.dart';
import 'walk.dart';

/// One scheduled dose of a medication on the "Hoy" screen.
class DoseSlot {
  DoseSlot({
    required this.pet,
    required this.med,
    required this.time,
    this.givenAt,
  });

  final Pet pet;
  final Medication med;
  final DateTime time;

  /// When it was marked as given, or null.
  final DateTime? givenAt;

  bool get given => givenAt != null;

  /// A dose given up to half an interval before or after its time counts
  /// for it (so a dose given a bit late or early isn't counted twice).
  Duration get _half => Duration(minutes: med.everyMinutes ~/ 2);

  /// Still pending and its time window has already passed.
  bool missed(DateTime now) => !given && now.isAfter(time.add(_half));

  /// Can be marked as given now: its window is open (or about to).
  bool canGive(DateTime now) =>
      !given && !missed(now) && now.isAfter(time.subtract(_half));
}

/// Doses of [day] of every medication, by time. Each given dose is matched to
/// at most one slot within half an interval of it.
List<DoseSlot> dosesOfDay(Iterable<Pet> pets, DateTime day) {
  final start = DateTime(day.year, day.month, day.day);
  final end = DateTime(day.year, day.month, day.day + 1);
  // Very short intervals would fill the screen; a day of doses every 15 min
  // is already 96.
  const maxPerMed = 96;
  final slots = <DoseSlot>[];
  for (final pet in pets) {
    for (final med in pet.medications) {
      final half = Duration(minutes: med.everyMinutes ~/ 2);
      final used = <DateTime>{};
      var k = start.isAfter(med.startsAt)
          ? (start.difference(med.startsAt).inMinutes / med.everyMinutes).ceil()
          : 0;
      for (var n = 0; n < maxPerMed; n++, k++) {
        final time = med.doseTimeIfActive(k);
        if (time == null || !time.isBefore(end)) break;
        DateTime? given;
        for (final g in med.givenDoses) {
          if (!used.contains(g) && g.difference(time).abs() <= half) {
            given = g;
            used.add(g);
            break;
          }
        }
        slots.add(DoseSlot(pet: pet, med: med, time: time, givenAt: given));
      }
    }
  }
  slots.sort((a, b) => a.time.compareTo(b.time));
  return slots;
}

/// Appointments on [day], by time.
List<(Pet, VetVisit)> visitsOfDay(Iterable<Pet> pets, DateTime day) {
  final list = [
    for (final pet in pets)
      for (final v in pet.visits)
        if (v.date.year == day.year &&
            v.date.month == day.month &&
            v.date.day == day.day)
          (pet, v),
  ]..sort((a, b) => a.$2.date.compareTo(b.$2.date));
  return list;
}

/// Pending vaccines and antiparasitics that are overdue or due within
/// [withinDays] of [now], soonest first.
List<(Pet, HealthRecord)> recordsDueSoon(
  Iterable<Pet> pets,
  DateTime now, {
  int withinDays = 7,
}) {
  final list = [
    for (final pet in pets)
      for (final r in pendingRecords(pet.records))
        if (daysUntil(r.nextDue!, now) <= withinDays) (pet, r),
  ]..sort((a, b) => a.$2.nextDue!.compareTo(b.$2.nextDue!));
  return list;
}

/// Food and medicines that are running out (within their warning days) or
/// already ran out, soonest first.
List<(Pet, Supply)> suppliesToRestock(Iterable<Pet> pets, DateTime now) {
  final list = [
    for (final pet in pets)
      for (final s in pet.supplies)
        if (s.needsRestock(now)) (pet, s),
  ]..sort((a, b) => a.$2.runsOutOn.compareTo(b.$2.runsOutOn));
  return list;
}

/// Pets with the walk reminder on that haven't been walked on [day] yet.
List<Pet> petsToWalk(Iterable<Pet> pets, DateTime day) => [
  for (final p in pets)
    if (p.walkReminder != null && walksOn(p.walks, day).isEmpty) p,
];
