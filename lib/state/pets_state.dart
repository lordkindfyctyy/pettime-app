import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/expense.dart';
import '../models/health_record.dart';
import '../models/medication.dart';
import '../models/pet.dart';
import '../models/pet_share.dart';
import '../models/supply.dart';
import '../models/vet_visit.dart';
import '../models/weight_entry.dart';
import '../services/calendar_service.dart';
import '../services/family_sync.dart';
import '../services/home_widget_service.dart';
import '../services/notification_service.dart';
import '../services/photo_service.dart';

class PetsState extends ChangeNotifier {
  static const storageKey = 'pets_v1';
  static const _key = storageKey;
  static const _uuid = Uuid();

  /// Adds a given dose to the stored pets JSON [raw] without a [PetsState]
  /// (used when a notification action runs while the app is closed).
  /// Returns the updated JSON, or null when the pet or medication is gone.
  static String? addDoseToJson(
    String raw,
    String petId,
    String medId,
    DateTime at,
  ) {
    final pets = (jsonDecode(raw) as List)
        .map((p) => Pet.fromJson(p as Map<String, dynamic>))
        .toList();
    final i = pets.indexWhere((p) => p.id == petId);
    if (i == -1 || !pets[i].medications.any((m) => m.id == medId)) return null;
    pets[i] = pets[i].copyWith(
      medications: [
        for (final m in pets[i].medications)
          m.id == medId
              ? m.copyWith(givenDoses: [...m.givenDoses, at]..sort())
              : m,
      ],
      // A shared pet sends the dose to the family the next time the app opens.
      share: pets[i].share?.copyWith(dirty: true),
    );
    return jsonEncode(pets.map((p) => p.toJson()).toList());
  }

  List<Pet> _pets = [];
  List<Pet> get pets => List.unmodifiable(_pets);

  Pet? byId(String id) {
    for (final p in _pets) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      _pets = (jsonDecode(raw) as List)
          .map((p) => Pet.fromJson(p as Map<String, dynamic>))
          .toList();
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_pets.map((p) => p.toJson()).toList()));
    notifyListeners();
    _background(() => HomeWidgetService.refresh(_pets));
  }

  String newId() => _uuid.v4();

  /// Stores the pet (adds it, or replaces the one with the same id) and
  /// updates the screen. Alarms and Calendar are not touched here.
  ///
  /// A change to a pet shared with the family is marked to be sent, unless
  /// it is what came from the server ([fromSync]).
  Future<void> _store(Pet pet, {bool fromSync = false}) async {
    final share = pet.share;
    if (!fromSync && share != null && !share.dirty) {
      pet = pet.copyWith(share: share.copyWith(dirty: true));
    }
    final i = _pets.indexWhere((p) => p.id == pet.id);
    if (i == -1) {
      _pets.add(pet);
    } else {
      _pets[i] = pet;
    }
    await _save();
    if (!fromSync && share != null) FamilySync.instance.schedule(pet.id);
  }

  /// Saves what came from the family's server: [pet] replaces this phone's
  /// copy, and its alarms and Calendar events follow the changes (what the
  /// others deleted is cancelled here too).
  Future<void> applySharedPet(Pet pet) async {
    final old = byId(pet.id);
    await _store(pet, fromSync: true);
    _background(() async {
      final removedMeds = [
        for (final m in old?.medications ?? const <Medication>[])
          if (!pet.medications.any((n) => n.id == m.id)) m,
      ];
      for (final med in removedMeds) {
        await NotificationService.instance.cancelMedication(med.id);
        await CalendarService.instance.deleteMedication(med.id);
      }
      for (final visit in old?.visits ?? const <VetVisit>[]) {
        if (!pet.visits.any((v) => v.id == visit.id)) {
          await CalendarService.instance.deleteVisit(visit.id);
        }
      }
      for (final med in pet.medications) {
        await NotificationService.instance.scheduleMedication(pet, med);
      }
      final removedRecords = [
        for (final r in old?.records ?? const <HealthRecord>[])
          if (!pet.records.any((n) => n.id == r.id)) r.id,
      ];
      final removedSupplies = [
        for (final s in old?.supplies ?? const <Supply>[])
          if (!pet.supplies.any((n) => n.id == s.id)) s.id,
      ];
      await NotificationService.instance
          .scheduleRecords(pet, removedIds: removedRecords);
      await NotificationService.instance
          .scheduleSupplies(pet, removedIds: removedSupplies);
      if (removedRecords.isEmpty) {
        await CalendarService.instance.syncPet(pet);
      } else {
        await CalendarService.instance
            .syncRecords(pet, removedIds: removedRecords);
        await CalendarService.instance.syncPet(pet);
      }
    });
  }

  /// Sets how the pet is shared (null: no longer shared) without marking it
  /// as changed.
  Future<void> setShare(String petId, PetShare? share) async {
    final pet = byId(petId);
    if (pet == null) return;
    await _store(
      pet.copyWith(share: share, clearShare: share == null),
      fromSync: true,
    );
  }

  /// Alarms and Google Calendar are slow (hundreds of platform calls, network)
  /// and the data is already saved, so they run after the screen has updated.
  /// A failure (offline, revoked permission) must not undo or block anything.
  void _background(Future<void> Function() task) {
    unawaited(() async {
      try {
        await task();
      } catch (e) {
        debugPrint('Background sync failed: $e');
      }
    }());
  }

  /// Adds the pet, or replaces the one with the same id.
  Future<void> savePet(Pet pet) async {
    await _store(pet);
    _background(() async {
      for (final med in pet.medications) {
        await NotificationService.instance.scheduleMedication(pet, med);
      }
      await NotificationService.instance.scheduleRecords(pet);
      await NotificationService.instance.scheduleSupplies(pet);
      await CalendarService.instance.syncPet(pet);
    });
  }

  Future<void> deletePet(String id) async {
    final pet = byId(id);
    _pets.removeWhere((p) => p.id == id);
    await _save();
    _background(() async {
      await PhotoService.instance.delete(pet?.photoPath);
      for (final med in pet?.medications ?? const <Medication>[]) {
        await PhotoService.instance.delete(med.photoPath);
        await NotificationService.instance.cancelMedication(med.id);
        await CalendarService.instance.deleteMedication(med.id);
      }
      for (final visit in pet?.visits ?? const <VetVisit>[]) {
        await CalendarService.instance.deleteVisit(visit.id);
      }
      if (pet != null && pet.supplies.isNotEmpty) {
        await NotificationService.instance.scheduleSupplies(
          pet.copyWith(supplies: []),
          removedIds: [for (final s in pet.supplies) s.id],
        );
      }
      if (pet != null && pet.records.isNotEmpty) {
        final ids = [for (final r in pet.records) r.id];
        final empty = pet.copyWith(records: []);
        await NotificationService.instance.scheduleRecords(empty, removedIds: ids);
        await CalendarService.instance.syncRecords(empty, removedIds: ids);
      }
    });
  }

  Future<void> saveMedication(String petId, Medication med) async {
    final pet = byId(petId);
    if (pet == null) return;
    final meds = [...pet.medications];
    final i = meds.indexWhere((m) => m.id == med.id);
    if (i == -1) {
      meds.add(med);
    } else {
      meds[i] = med;
    }
    final updated = pet.copyWith(medications: meds);
    await _store(updated);
    _background(() async {
      await NotificationService.instance.scheduleMedication(updated, med);
      await CalendarService.instance.syncMedication(updated, med);
    });
  }

  /// Records that a dose was given ([at] defaults to now).
  Future<void> logDose(String petId, String medId, [DateTime? at]) =>
      _changeDoses(petId, medId, (doses) => [...doses, at ?? DateTime.now()]);

  Future<void> removeDose(String petId, String medId, DateTime at) =>
      _changeDoses(petId, medId, (doses) => doses.where((d) => d != at).toList());

  Future<void> _changeDoses(
    String petId,
    String medId,
    List<DateTime> Function(List<DateTime>) change,
  ) async {
    final med = byId(petId)?.medications.where((m) => m.id == medId).firstOrNull;
    if (med == null) return;
    final doses = change(med.givenDoses)..sort();
    // Doses given are not part of the alarm or the Calendar event, but they
    // decide which "¿ya le diste…?" reminders are still needed.
    final updatedMed = med.copyWith(givenDoses: doses);
    final pet = byId(petId)!.copyWith(
      medications: [
        for (final m in byId(petId)!.medications)
          m.id == medId ? updatedMed : m,
      ],
    );
    await _store(pet);
    _background(
      () => NotificationService.instance.syncFollowUps(pet, updatedMed),
    );
  }

  Future<void> saveVisit(String petId, VetVisit visit) async {
    final pet = byId(petId);
    if (pet == null) return;
    final visits = [...pet.visits];
    final i = visits.indexWhere((v) => v.id == visit.id);
    if (i == -1) {
      visits.add(visit);
    } else {
      visits[i] = visit;
    }
    final updated = pet.copyWith(visits: visits);
    await _store(updated);
    _background(() => CalendarService.instance.syncVisit(updated, visit));
  }

  Future<void> deleteVisit(String petId, String visitId) async {
    final pet = byId(petId);
    if (pet == null) return;
    await _store(pet.copyWith(
      visits: pet.visits.where((v) => v.id != visitId).toList(),
    ));
    _background(() => CalendarService.instance.deleteVisit(visitId));
  }

  /// Adds or edits a supply (food, medicine…) and its restocking reminders.
  Future<void> saveSupply(String petId, Supply supply) async {
    final pet = byId(petId);
    if (pet == null) return;
    final supplies = [...pet.supplies];
    final i = supplies.indexWhere((s) => s.id == supply.id);
    if (i == -1) {
      supplies.add(supply);
    } else {
      supplies[i] = supply;
    }
    final updated = pet.copyWith(supplies: supplies);
    await _store(updated);
    _background(() => NotificationService.instance.scheduleSupplies(updated));
  }

  /// A new package was opened today.
  Future<void> restock(String petId, String supplyId, [DateTime? on]) async {
    final s = byId(petId)?.supplies.where((s) => s.id == supplyId).firstOrNull;
    if (s == null) return;
    final day = on ?? DateTime.now();
    await saveSupply(
      petId,
      s.copyWith(openedOn: DateTime(day.year, day.month, day.day)),
    );
  }

  Future<void> deleteSupply(String petId, String supplyId) async {
    final pet = byId(petId);
    if (pet == null) return;
    final updated = pet.copyWith(
      supplies: pet.supplies.where((s) => s.id != supplyId).toList(),
    );
    await _store(updated);
    _background(() => NotificationService.instance
        .scheduleSupplies(updated, removedIds: [supplyId]));
  }

  /// Adds a weighing, keeping them by date. Weights don't touch alarms or
  /// Calendar.
  Future<void> addWeight(String petId, WeightEntry entry) async {
    final pet = byId(petId);
    if (pet == null) return;
    final weights = [...pet.weights, entry]
      ..sort((a, b) => a.date.compareTo(b.date));
    await _store(pet.copyWith(weights: weights));
  }

  Future<void> deleteWeight(String petId, String entryId) async {
    final pet = byId(petId);
    if (pet == null) return;
    await _store(pet.copyWith(
      weights: pet.weights.where((w) => w.id != entryId).toList(),
    ));
  }

  /// Adds an expense, or replaces the one with the same id; newest first.
  Future<void> saveExpense(String petId, Expense expense) async {
    final pet = byId(petId);
    if (pet == null) return;
    final expenses = [
      ...pet.expenses.where((e) => e.id != expense.id),
      expense,
    ]..sort((a, b) => b.date.compareTo(a.date));
    await _store(pet.copyWith(expenses: expenses));
  }

  Future<void> deleteExpense(String petId, String expenseId) async {
    final pet = byId(petId);
    if (pet == null) return;
    await _store(pet.copyWith(
      expenses: pet.expenses.where((e) => e.id != expenseId).toList(),
    ));
  }

  /// Replaces every pet with the ones of a backup. Alarms are rebuilt, and
  /// the photos and Calendar events of what is no longer there are removed.
  Future<void> replaceAll(List<Pet> pets) async {
    final old = _pets;
    _pets = [...pets];
    await _save();
    final newPhotos = {
      for (final p in pets) ...[
        p.photoPath,
        for (final m in p.medications) m.photoPath,
      ],
    };
    _background(() async {
      for (final p in old) {
        for (final path in [p.photoPath, for (final m in p.medications) m.photoPath]) {
          if (!newPhotos.contains(path)) await PhotoService.instance.delete(path);
        }
      }
      await NotificationService.instance.syncAll(_pets);
      final calendar = CalendarService.instance;
      final medIds = {for (final p in pets) for (final m in p.medications) m.id};
      final visitIds = {for (final p in pets) for (final v in p.visits) v.id};
      for (final p in old) {
        for (final m in p.medications) {
          if (!medIds.contains(m.id)) await calendar.deleteMedication(m.id);
        }
        for (final v in p.visits) {
          if (!visitIds.contains(v.id)) await calendar.deleteVisit(v.id);
        }
        final gone = [
          for (final r in p.records)
            if (!pets.any((n) => n.records.any((x) => x.id == r.id))) r.id,
        ];
        if (gone.isNotEmpty) {
          await calendar.syncRecords(p.copyWith(records: []), removedIds: gone);
        }
      }
      await calendar.syncAll(_pets);
    });
  }

  /// Adds or edits an entry of the health booklet. A newer application of
  /// the same vaccine replaces the reminder of the older one, so all the
  /// pet's reminders are rebuilt.
  Future<void> saveRecord(String petId, HealthRecord record) async {
    final pet = byId(petId);
    if (pet == null) return;
    final records = [...pet.records];
    final i = records.indexWhere((r) => r.id == record.id);
    if (i == -1) {
      records.add(record);
    } else {
      records[i] = record;
    }
    final updated = pet.copyWith(records: records);
    await _store(updated);
    _background(() async {
      await NotificationService.instance.scheduleRecords(updated);
      await CalendarService.instance.syncRecords(updated);
    });
  }

  Future<void> deleteRecord(String petId, String recordId) async {
    final pet = byId(petId);
    if (pet == null) return;
    final updated = pet.copyWith(
      records: pet.records.where((r) => r.id != recordId).toList(),
    );
    await _store(updated);
    _background(() async {
      await NotificationService.instance
          .scheduleRecords(updated, removedIds: [recordId]);
      await CalendarService.instance
          .syncRecords(updated, removedIds: [recordId]);
    });
  }

  Future<void> deleteMedication(String petId, String medId) async {
    final pet = byId(petId);
    if (pet == null) return;
    final photo = pet.medications.where((m) => m.id == medId).firstOrNull?.photoPath;
    await _store(pet.copyWith(
      medications: pet.medications.where((m) => m.id != medId).toList(),
    ));
    _background(() async {
      await PhotoService.instance.delete(photo);
      await NotificationService.instance.cancelMedication(medId);
      await CalendarService.instance.deleteMedication(medId);
    });
  }
}
