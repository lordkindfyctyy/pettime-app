import 'package:flutter/foundation.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../config.dart';
import '../models/medication.dart';
import '../models/pet.dart';
import '../models/vet_visit.dart';

/// Mirrors medications (recurring events) and vet visits (single events) into
/// the user's primary Google Calendar.
///
/// Event ids are derived from the local ids, so syncing is idempotent: an
/// existing event is updated and a missing one is created.
class CalendarService extends ChangeNotifier {
  CalendarService._();
  static final instance = CalendarService._();

  static const _prefsKey = 'calendar_sync_v1';
  static const _scopes = [gcal.CalendarApi.calendarEventsScope];
  static const _visitDuration = Duration(hours: 1);
  static const _doseDuration = Duration(minutes: 15);

  bool _initialized = false;
  bool _enabled = false;
  bool get enabled => _enabled;

  /// Google sign-in only runs on the mobile targets.
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> load() async {
    if (!supported) return;
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_prefsKey) ?? false;
    notifyListeners();
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(serverClientId: googleServerClientId);
    _initialized = true;
  }

  /// Signs in, asks for the Calendar permission and turns syncing on.
  Future<void> enable() async {
    await _ensureInitialized();
    final account = await GoogleSignIn.instance.authenticate();
    await account.authorizationClient.authorizeScopes(_scopes);
    await _setEnabled(true);
  }

  Future<void> disable() async {
    if (_initialized) await GoogleSignIn.instance.signOut();
    await _setEnabled(false);
  }

  Future<void> _setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);
    notifyListeners();
  }

  Future<gcal.CalendarApi?> _api() async {
    if (!_enabled) return null;
    await _ensureInitialized();
    final account = await GoogleSignIn.instance.attemptLightweightAuthentication();
    if (account == null) return null;
    final auth = await account.authorizationClient.authorizationForScopes(_scopes);
    if (auth == null) return null;
    return gcal.CalendarApi(auth.authClient(scopes: _scopes));
  }

  /// Local id -> valid Google Calendar event id (lowercase base32hex chars).
  static String eventId(String kind, String id) =>
      '$kind${id.replaceAll('-', '')}';

  static String medicationTitle(Pet pet, Medication med) =>
      '${med.name} — ${pet.name}';

  static String visitTitle(Pet pet, VetVisit visit) =>
      'Veterinaria: ${pet.name} en ${visit.clinic}';

  /// RRULE for a medication: every N hours, until the end of the treatment.
  static String recurrence(Medication med) {
    final end = med.endsAt;
    final until = end == null
        ? ''
        : ';UNTIL=${_utcStamp(end)}';
    final minutes = med.everyMinutes;
    final freq = minutes % 60 == 0
        ? 'FREQ=HOURLY;INTERVAL=${minutes ~/ 60}'
        : 'FREQ=MINUTELY;INTERVAL=$minutes';
    return 'RRULE:$freq$until';
  }

  static String _utcStamp(DateTime d) {
    final u = d.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${u.year}${two(u.month)}${two(u.day)}T'
        '${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
  }

  gcal.Event _medicationEvent(Pet pet, Medication med) {
    return gcal.Event()
      ..id = eventId('pm', med.id)
      ..summary = medicationTitle(pet, med)
      ..description = [
        if (med.dose.isNotEmpty) 'Dosis: ${med.dose}',
        if (med.notes.isNotEmpty) med.notes,
      ].join('\n')
      ..start = _time(med.startsAt)
      ..end = _time(med.startsAt.add(_doseDuration))
      ..recurrence = [recurrence(med)]
      // The app's own notification already alerts on every dose (and names
      // the pet), so Calendar must not alert a second time.
      ..reminders = _noReminders();
  }

  gcal.Event _visitEvent(Pet pet, VetVisit visit) {
    return gcal.Event()
      ..id = eventId('pv', visit.id)
      ..summary = visitTitle(pet, visit)
      ..description = [
        if (visit.reason.isNotEmpty) 'Motivo: ${visit.reason}',
        if (visit.notes.isNotEmpty) visit.notes,
      ].join('\n')
      ..start = _time(visit.date)
      ..end = _time(visit.date.add(_visitDuration))
      ..reminders = _popup(minutes: 60);
  }

  gcal.EventDateTime _time(DateTime t) => gcal.EventDateTime()
    ..dateTime = t.toUtc()
    ..timeZone = tz.local.name;

  gcal.EventReminders _popup({required int minutes}) => gcal.EventReminders()
    ..useDefault = false
    ..overrides = [
      gcal.EventReminder()
        ..method = 'popup'
        ..minutes = minutes,
    ];

  gcal.EventReminders _noReminders() => gcal.EventReminders()
    ..useDefault = false
    ..overrides = [];

  Future<void> _upsert(gcal.CalendarApi api, gcal.Event event) async {
    try {
      await api.events.update(event, 'primary', event.id!);
    } on gcal.DetailedApiRequestError catch (e) {
      if (e.status != 404) rethrow;
      await api.events.insert(event, 'primary');
    }
  }

  Future<void> _delete(gcal.CalendarApi api, String id) async {
    try {
      await api.events.delete('primary', id);
    } on gcal.DetailedApiRequestError catch (e) {
      // Already gone (404) or deleted earlier (410): nothing left to remove.
      if (e.status != 404 && e.status != 410) rethrow;
    }
  }

  /// Creates or updates every medication and visit of [pet].
  Future<void> syncPet(Pet pet) async {
    final api = await _api();
    if (api == null) return;
    for (final med in pet.medications) {
      await _upsert(api, _medicationEvent(pet, med));
    }
    for (final visit in pet.visits) {
      await _upsert(api, _visitEvent(pet, visit));
    }
  }

  Future<void> syncAll(Iterable<Pet> pets) async {
    for (final pet in pets) {
      await syncPet(pet);
    }
  }

  Future<void> deleteMedication(String medicationId) async {
    final api = await _api();
    if (api != null) await _delete(api, eventId('pm', medicationId));
  }

  Future<void> deleteVisit(String visitId) async {
    final api = await _api();
    if (api != null) await _delete(api, eventId('pv', visitId));
  }
}
