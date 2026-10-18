import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/calendar_service.dart';
import 'services/drive_backup_service.dart';
import 'services/family_sync.dart';
import 'services/lost_pets_service.dart';
import 'services/home_widget_service.dart';
import 'services/notification_service.dart';
import 'services/shop_settings.dart';
import 'state/pets_state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');
  final pets = PetsState();
  await pets.load();
  await CalendarService.instance.load();
  await DriveBackupService.instance.load();
  await ShopSettings.instance.load();
  await LostPetsService.instance.load();
  NotificationService.instance.onDoseGiven =
      (petId, medId) => pets.logDose(petId, medId);
  // Pets shared with the family: sync now, every minute while the app is
  // open, and when it comes back (a dose may have been marked from a
  // notification while it was closed).
  FamilySync.instance.attach(pets);
  AppLifecycleListener(
    onResume: () async {
      await pets.load();
      FamilySync.instance.resume();
    },
    onPause: FamilySync.instance.pause,
  );
  runApp(
    ChangeNotifierProvider.value(value: pets, child: const PetTimeApp()),
  );
  // Scheduling the alarms takes hundreds of platform calls; do it after the
  // first frame so the app opens right away.
  unawaited(_startAlarms(pets));
  // The "Próximas tomas" widget, in case time went by since it was drawn.
  unawaited(HomeWidgetService.refresh(pets.pets));
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
