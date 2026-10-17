import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/medication.dart';
import '../models/pet.dart';

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
  );

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
    );
    _ready = true;
  }

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
