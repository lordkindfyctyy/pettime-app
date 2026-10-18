import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../models/agenda.dart';
import '../models/pet.dart';

/// One dose shown on the home screen widget.
class WidgetDose {
  WidgetDose({
    required this.time,
    required this.until,
    required this.title,
    required this.detail,
  });

  final DateTime time;

  /// The widget stops showing it after this (its window to give it closes).
  final DateTime until;

  /// "Pancho · Amoxicilina".
  final String title;

  /// The dose, e.g. "1 comprimido"; may be empty.
  final String detail;

  Map<String, dynamic> toJson() => {
        't': time.millisecondsSinceEpoch,
        'u': until.millisecondsSinceEpoch,
        'title': title,
        'detail': detail,
      };
}

/// The pending doses of today, tomorrow and the day after, by time: the ones
/// not given yet whose window is still open. The widget picks what to show
/// by the clock, so it stays right for a while without the app.
List<WidgetDose> upcomingWidgetDoses(
  Iterable<Pet> pets,
  DateTime now, {
  int max = 40,
}) {
  final doses = <WidgetDose>[];
  for (var d = 0; d < 3; d++) {
    final day = DateTime(now.year, now.month, now.day + d);
    for (final slot in dosesOfDay(pets, day)) {
      if (slot.given || slot.missed(now)) continue;
      doses.add(WidgetDose(
        time: slot.time,
        until: slot.time.add(Duration(minutes: slot.med.everyMinutes ~/ 2)),
        title: '${slot.pet.name} · ${slot.med.name}',
        detail: slot.med.dose,
      ));
    }
  }
  doses.sort((a, b) => a.time.compareTo(b.time));
  return doses.take(max).toList();
}

/// When the widget has to redraw: each time a dose drops off it, and at
/// midnight, when "Mañana" becomes "Hoy".
List<DateTime> widgetRefreshTimes(List<WidgetDose> doses, DateTime now) {
  final times = <DateTime>{
    for (final d in doses) d.until,
    for (var d = 1; d <= 3; d++) DateTime(now.year, now.month, now.day + d),
  }.where((t) => t.isAfter(now)).toList()
    ..sort();
  return times.take(50).toList();
}

/// Keeps the "Próximas tomas" widget on the phone's home screen up to date.
class HomeWidgetService {
  HomeWidgetService._();

  static const _provider = 'com.mascotas.pettime_app.DosesWidget';

  /// Saves the upcoming doses for the widget and redraws it. Never throws:
  /// the widget is a convenience and must not break saving.
  static Future<void> refresh(Iterable<Pet> pets, [DateTime? now]) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final at = now ?? DateTime.now();
    final doses = upcomingWidgetDoses(pets, at);
    try {
      await HomeWidget.saveWidgetData<String>(
        'doses',
        jsonEncode(doses.map((d) => d.toJson()).toList()),
      );
      await HomeWidget.saveWidgetData<bool>('hasPets', pets.isNotEmpty);
      await HomeWidget.updateWidget(qualifiedAndroidName: _provider);
      await HomeWidget.scheduleWidgetUpdates(
        widgetRefreshTimes(doses, at),
        qualifiedAndroidName: _provider,
      );
    } catch (e) {
      debugPrint('Could not update the home screen widget: $e');
    }
  }
}
