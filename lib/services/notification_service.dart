import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/medication.dart';
import '../models/pet.dart';
import '../state/pets_state.dart';

const _doseGivenAction = 'dose_given';
const _doseGivenPort = 'pettime_dose_given';

/// Runs when the "Dada" button is pressed, possibly in a background isolate.
///
/// If the app is alive its main isolate owns the in-memory state, so the
/// press is forwarded there; otherwise the stored data is updated directly.
@pragma('vm:entry-point')
Future<void> notificationBackgroundHandler(NotificationResponse response) async {
  if (response.actionId != _doseGivenAction) return;
  final payload = response.payload;
  if (payload == null) return;

  final port = IsolateNameServer.lookupPortByName(_doseGivenPort);
  if (port != null) {
    port.send(payload);
    return;
  }

  DartPluginRegistrant.ensureInitialized();
  final parts = payload.split('|');
  if (parts.length != 2) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final raw = prefs.getString(PetsState.storageKey);
  if (raw == null) return;
  final updated =
      PetsState.addDoseToJson(raw, parts[0], parts[1], DateTime.now());
  if (updated != null) await prefs.setString(PetsState.storageKey, updated);
}

/// Schedules one local notification per upcoming dose of every medication.
///
/// Only the next [dosesAhead] doses of each medication are scheduled; the
/// window is refilled every time the app starts or the data changes.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  /// Every alarm is a slow call into Android and the plugin rewrites its whole
  /// list each time, so keep few: only the next [dosesAhead] doses of each
  /// medication (10 days at every 6 h). The rest are added whenever the app
  /// is opened.
  static const dosesAhead = 40;
  static const _slots = 64;

  /// Android details for one pet's alarm; the pet's photo, when it has one
  /// and the file still exists, is shown as the large icon.
  static AndroidNotificationDetails androidDetails(Pet pet) {
    final photo = pet.photoPath;
    return AndroidNotificationDetails(
      'medication',
      'Medicación',
      channelDescription: 'Avisos para dar la medicación a tus mascotas',
      importance: Importance.high,
      priority: Priority.high,
      largeIcon: photo != null && File(photo).existsSync()
          ? FilePathAndroidBitmap(photo)
          : null,
      actions: const [
        AndroidNotificationAction(_doseGivenAction, 'Dada ✓'),
      ],
    );
  }

  /// Called in the main isolate with a `petId|medId` payload when "Dada" is
  /// pressed on a notification.
  void Function(String petId, String medId)? onDoseGiven;
  final _port = ReceivePort();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  // Local notifications are only wired up for the mobile targets.
  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> init() async {
    if (!_supported || _ready) return;
    tz_data.initializeTimeZones();
    final zone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zone.identifier));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.actionId == _doseGivenAction && response.payload != null) {
          _dispatch(response.payload!);
        }
      },
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
    );
    IsolateNameServer.removePortNameMapping(_doseGivenPort);
    IsolateNameServer.registerPortWithName(_port.sendPort, _doseGivenPort);
    _port.listen((message) => _dispatch(message as String));
    _ready = true;
  }

  void _dispatch(String payload) {
    final parts = payload.split('|');
    if (parts.length == 2) onDoseGiven?.call(parts[0], parts[1]);
  }

  static String payload(Pet pet, Medication med) => '${pet.id}|${med.id}';

  /// Asks for the notification permission; returns whether it was granted.
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission() ?? false;
      if (granted && !(await android.canScheduleExactNotifications() ?? true)) {
        await android.requestExactAlarmsPermission();
      }
      return granted;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, sound: true) ?? false;
  }

  /// Notification ids of one medication: a stable 24-bit hash of its id in the
  /// high bits and the dose index in the low 6 bits (so [dosesAhead] <= 64).
  static int baseId(String medicationId) {
    var h = 0x811c9dc5;
    for (final unit in medicationId.codeUnits) {
      h = ((h ^ unit) * 0x01000193) & 0xFFFFFF;
    }
    // The top bit marks the dose-number scheme; alarms left over from the
    // earlier scheme (ids without it) are removed by [syncAll].
    return (h << 6) | (1 << 30);
  }

  static String messageTitle(Pet pet) => 'Medicación de ${pet.name}';

  static String messageBody(Pet pet, Medication med) {
    final dose = med.dose.isEmpty ? '' : ' (${med.dose})';
    return 'Es hora de darle ${med.name}$dose a ${pet.name}';
  }

  /// Ids of the alarms of one medication: [baseId] plus a slot below [_slots].
  static bool _isSlotOf(int id, int base) => id >= base && id < base + _slots;

  /// Which doses get an alarm: the next [dosesAhead] ones, up to the end of the
  /// treatment. Each is (dose number, notification id).
  static List<(int, int)> plannedDoses(Medication med, DateTime now) {
    final base = baseId(med.id);
    final planned = <(int, int)>[];
    var k = med.nextDoseIndex(now);
    while (planned.length < dosesAhead && med.doseTimeIfActive(k) != null) {
      planned.add((k, base + k % _slots));
      k++;
    }
    return planned;
  }

  Future<Set<int>> _pendingIds() async =>
      {for (final p in await _plugin.pendingNotificationRequests()) p.id};

  /// Removes every pending alarm of the medication.
  Future<void> cancelMedication(String medicationId) async {
    if (!_ready) return;
    final base = baseId(medicationId);
    for (final id in await _pendingIds()) {
      if (_isSlotOf(id, base)) await _plugin.cancel(id: id);
    }
  }

  /// Schedules the alarms of one medication from scratch (its settings or its
  /// pet changed). Alarms already pending are replaced.
  Future<void> scheduleMedication(Pet pet, Medication med) async {
    if (!_ready) return;
    final planned = {for (final (_, id) in plannedDoses(med, DateTime.now())) id};
    final base = baseId(med.id);
    for (final id in await _pendingIds()) {
      if (_isSlotOf(id, base) && !planned.contains(id)) {
        await _plugin.cancel(id: id);
      }
    }
    await _schedule(pet, med, alreadyPending: const {});
  }

  Future<void> _schedule(
    Pet pet,
    Medication med, {
    required Set<int> alreadyPending,
  }) async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final exact = await android?.canScheduleExactNotifications() ?? true;
    final mode = exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    final details = NotificationDetails(
      android: androidDetails(pet),
      iOS: const DarwinNotificationDetails(),
    );
    for (final (k, id) in plannedDoses(med, DateTime.now())) {
      if (alreadyPending.contains(id)) continue;
      await _plugin.zonedSchedule(
        id: id,
        title: messageTitle(pet),
        body: messageBody(pet, med),
        payload: payload(pet, med),
        scheduledDate: tz.TZDateTime.from(med.doseTime(k), tz.local),
        notificationDetails: details,
        androidScheduleMode: mode,
      );
    }
  }

  /// Brings the pending alarms in line with the data when the app starts:
  /// removes the ones that no longer belong to any medication and adds only the
  /// missing ones (each add or cancel is a slow call into Android).
  Future<void> syncAll(Iterable<Pet> pets) async {
    if (!_ready) return;
    final now = DateTime.now();
    final expected = {
      for (final pet in pets)
        for (final med in pet.medications)
          for (final (_, id) in plannedDoses(med, now)) id,
    };
    final pending = await _pendingIds();
    for (final id in pending) {
      if (!expected.contains(id)) await _plugin.cancel(id: id);
    }
    for (final pet in pets) {
      for (final med in pet.medications) {
        await _schedule(pet, med, alreadyPending: pending);
      }
    }
  }
}
