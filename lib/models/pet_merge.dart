import 'caregiver.dart';
import 'diary_entry.dart';
import 'medication.dart';
import 'pet.dart';
import 'pet_share.dart';

/// The pet as it is sent to the server: without what only makes sense on
/// this phone (how it is shared, the paths of its photos, the diary's too).
Map<String, dynamic> sharePayload(Pet pet) {
  final json = pet.toJson()
    ..remove('share')
    ..remove('photoPath');
  json['medications'] = [
    for (final m in pet.medications) m.toJson()..remove('photoPath'),
  ];
  json['diary'] = [
    for (final d in pet.diary) d.toJson()..remove('photos'),
  ];
  return json;
}

/// A pet that came from the server, keeping this phone's own photos (the
/// pet's, the medicines' and the diary's, by id) from [local].
Pet petFromShared(
  Map<String, dynamic> remote, {
  Pet? local,
  required PetShare share,
}) {
  final pet = Pet.fromJson({...remote, 'photoPath': local?.photoPath});
  final localMeds = {for (final m in local?.medications ?? <Medication>[]) m.id: m};
  final localDiary = {for (final d in local?.diary ?? <DiaryEntry>[]) d.id: d};
  return pet.copyWith(
    diary: [
      for (final d in pet.diary)
        localDiary[d.id] == null ? d : d.copyWith(photos: localDiary[d.id]!.photos),
    ],
    share: share,
    medications: [
      for (final m in pet.medications)
        localMeds[m.id]?.photoPath == null
            ? m
            : m.copyWith(photoPath: localMeds[m.id]!.photoPath),
    ],
  );
}

/// Combines this phone's changes ([local]) with someone else's that got to
/// the server first ([remote]), for when both changed the pet since the last
/// sync. Nothing anybody added is lost:
/// - lists (medication, visits, vaccines, weights, restock, expenses, walks,
///   diary) keep the items of both; an item changed on both phones keeps
///   this phone's;
/// - a caregiver's care ended on either phone stays ended;
/// - the doses given are the ones given on either phone;
/// - the pet's own data (name, food, notes…) keeps this phone's.
/// An item deleted on one phone while the other changed the pet comes back;
/// it can be deleted again.
Pet mergePets(Pet local, Pet remote) {
  List<T> union<T>(List<T> mine, List<T> theirs, String Function(T) id) {
    final ids = {for (final m in mine) id(m)};
    return [...mine, ...theirs.where((t) => !ids.contains(id(t)))];
  }

  final remoteMeds = {for (final m in remote.medications) m.id: m};
  final meds = [
    for (final m in local.medications)
      remoteMeds[m.id] == null
          ? m
          : m.copyWith(
              givenDoses: ({...m.givenDoses, ...remoteMeds[m.id]!.givenDoses}
                      .toList())
                ..sort(),
            ),
    ...remote.medications.where(
      (r) => !local.medications.any((m) => m.id == r.id),
    ),
  ];

  return local.copyWith(
    medications: meds,
    visits: union(local.visits, remote.visits, (v) => v.id),
    records: union(local.records, remote.records, (r) => r.id),
    weights: union(local.weights, remote.weights, (w) => w.id)
      ..sort((a, b) => a.date.compareTo(b.date)),
    supplies: union(local.supplies, remote.supplies, (s) => s.id),
    expenses: union(local.expenses, remote.expenses, (e) => e.id)
      ..sort((a, b) => b.date.compareTo(a.date)),
    walks: union(local.walks, remote.walks, (w) => w.id)
      ..sort((a, b) => b.date.compareTo(a.date)),
    diary: union(local.diary, remote.diary, (d) => d.id)
      ..sort((a, b) => b.date.compareTo(a.date)),
    caregivers: mergeCaregivers(local.caregivers, remote.caregivers),
  );
}
