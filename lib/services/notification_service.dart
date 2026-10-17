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

  static const dosesAhead = 48;
  static const _channel = AndroidNotificationDetails(
    'medication',
    'Medicación',
    channelDescription: 'Avisos para dar la medicación a tus mascotas',
    importance: Importance.high,
    priority: Priority.high,
    actions: [
      AndroidNotificationAction(_doseGivenAction, 'Dada ✓'),
    ],
  );

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
    return h << 6;
  }

  static String messageTitle(Pet pet) => 'Medicación de ${pet.name}';

  static String messageBody(Pet pet, Medication med) {
    final dose = med.dose.isEmpty ? '' : ' (${med.dose})';
    return 'Es hora de darle ${med.name}$dose a ${pet.name}';
  }

  Future<void> cancelMedication(String medicationId) async {
    if (!_ready) return;
    final base = baseId(medicationId);
    for (var i = 0; i < dosesAhead; i++) {
      await _plugin.cancel(id: base + i);
    }
  }

  Future<void> scheduleMedication(Pet pet, Medication med) async {
    if (!_ready) return;
    await cancelMedication(med.id);

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final exact = await android?.canScheduleExactNotifications() ?? true;
    final mode = exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    final base = baseId(med.id);
    var from = DateTime.now();
    for (var i = 0; i < dosesAhead; i++) {
      final next = med.nextDose(from);
      if (next == null) break;
      await _plugin.zonedSchedule(
        id: base + i,
        title: messageTitle(pet),
        body: messageBody(pet, med),
        payload: payload(pet, med),
        scheduledDate: tz.TZDateTime.from(next, tz.local),
        notificationDetails: const NotificationDetails(
          android: _channel,
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: mode,
      );
      from = next;
    }
  }

  /// Reschedules everything from scratch; used when the app starts.
  Future<void> syncAll(Iterable<Pet> pets) async {
    if (!_ready) return;
    await _plugin.cancelAllPendingNotifications();
    for (final pet in pets) {
      for (final med in pet.medications) {
        await scheduleMedication(pet, med);
      }
    }
  }
}
