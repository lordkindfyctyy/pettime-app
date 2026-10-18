import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/calendar_service.dart';
import 'services/notification_service.dart';
import 'state/pets_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');
  final pets = PetsState();
  await pets.load();
  await CalendarService.instance.load();
  NotificationService.instance.onDoseGiven =
      (petId, medId) => pets.logDose(petId, medId);
  runApp(
    ChangeNotifierProvider.value(value: pets, child: const PetTimeApp()),
  );
  // Scheduling the alarms takes hundreds of platform calls; do it after the
  // first frame so the app opens right away.
  unawaited(_startAlarms(pets));
}

Future<void> _startAlarms(PetsState pets) async {
  try {
    await NotificationService.instance.init();
    await NotificationService.instance.syncAll(pets.pets);
  } catch (e) {
    debugPrint('Could not schedule the alarms: $e');
  }
}

class PetTimeApp extends StatelessWidget {
  const PetTimeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PetTime',
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const HomeScreen(),
    );
  }
}
