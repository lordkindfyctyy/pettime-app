import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/calendar_service.dart';
import 'services/drive_backup_service.dart';
import 'services/notification_service.dart';
import 'state/pets_state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');
  final pets = PetsState();
  await pets.load();
  await CalendarService.instance.load();
  await DriveBackupService.instance.load();
  NotificationService.instance.onDoseGiven =
      (petId, medId) => pets.logDose(petId, medId);
  runApp(
    ChangeNotifierProvider.value(value: pets, child: const PetTimeApp()),
  );
  // Scheduling the alarms takes hundreds of platform calls; do it after the
  // first frame so the app opens right away.
  unawaited(_startAlarms(pets));
  // The daily copy to Google Drive, if it's on (uploads in the background).
  unawaited(DriveBackupService.instance.backupIfDue(pets.pets));
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
      theme: petTimeTheme(),
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
