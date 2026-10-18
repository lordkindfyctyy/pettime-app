import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/health_record.dart';
import '../models/medication.dart';
import '../models/pet.dart';
import '../models/vet_visit.dart';
import '../services/calendar_service.dart';
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
  }

  String newId() => _uuid.v4();

  /// Stores the pet (adds it, or replaces the one with the same id) and
  /// updates the screen. Alarms and Calendar are not touched here.
  Future<void> _store(Pet pet) async {
    final i = _pets.indexWhere((p) => p.id == pet.id);
    if (i == -1) {
      _pets.add(pet);
    } else {
      _pets[i] = pet;
    }
    await _save();
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
    // Doses given are not part of the alarm or the Calendar event.
    await _store(byId(petId)!.copyWith(
      medications: [
        for (final m in byId(petId)!.medications)
          m.id == medId ? med.copyWith(givenDoses: doses) : m,
      ],
    ));
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
