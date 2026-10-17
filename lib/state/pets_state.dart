import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/medication.dart';
import '../models/pet.dart';
import '../models/vet_visit.dart';
import '../services/calendar_service.dart';
import '../services/notification_service.dart';

class PetsState extends ChangeNotifier {
  static const _key = 'pets_v1';
  static const _uuid = Uuid();

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

  /// Adds the pet, or replaces the one with the same id.
  Future<void> savePet(Pet pet) async {
    final i = _pets.indexWhere((p) => p.id == pet.id);
    if (i == -1) {
      _pets.add(pet);
    } else {
      _pets[i] = pet;
    }
    await _save();
    for (final med in pet.medications) {
      await NotificationService.instance.scheduleMedication(pet, med);
    }
    await _calendar(() => CalendarService.instance.syncPet(pet));
  }

  Future<void> deletePet(String id) async {
    final pet = byId(id);
    _pets.removeWhere((p) => p.id == id);
    await _save();
    for (final med in pet?.medications ?? const <Medication>[]) {
      await NotificationService.instance.cancelMedication(med.id);
      await _calendar(() => CalendarService.instance.deleteMedication(med.id));
    }
    for (final visit in pet?.visits ?? const <VetVisit>[]) {
      await _calendar(() => CalendarService.instance.deleteVisit(visit.id));
    }
  }

  /// The local data is already saved; a Calendar failure (offline, revoked
  /// permission) must not undo or block it.
  Future<void> _calendar(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('Google Calendar sync failed: $e');
    }
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
    await savePet(pet.copyWith(medications: meds));
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
    await saveMedication(petId, med.copyWith(givenDoses: doses));
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
    await savePet(pet.copyWith(visits: visits));
  }

  Future<void> deleteVisit(String petId, String visitId) async {
    final pet = byId(petId);
    if (pet == null) return;
    await _calendar(() => CalendarService.instance.deleteVisit(visitId));
    await savePet(pet.copyWith(
      visits: pet.visits.where((v) => v.id != visitId).toList(),
    ));
  }

  Future<void> deleteMedication(String petId, String medId) async {
    final pet = byId(petId);
    if (pet == null) return;
    await NotificationService.instance.cancelMedication(medId);
    await _calendar(() => CalendarService.instance.deleteMedication(medId));
    await savePet(pet.copyWith(
      medications: pet.medications.where((m) => m.id != medId).toList(),
    ));
  }
}
