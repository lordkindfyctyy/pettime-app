import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'l10n/app_lang.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/drive_backup_service.dart';
import 'services/family_sync.dart';
import 'services/lost_pets_service.dart';
import 'services/home_widget_service.dart';
import 'services/notification_service.dart';
import 'services/shop_settings.dart';
import 'state/auth_state.dart';
import 'state/language_state.dart';
import 'state/pets_state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Dates are written in the language of the app, which is Spanish or English.
  await initializeDateFormatting();
  final language = LanguageState();
  await language.load();
  final auth = AuthState(await _startFirebase());
  await auth.load();
  final pets = PetsState();
  await pets.load();
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
  // The alarms and the widget carry text: redo them in the new language.
  language.onLanguageChanged = () {
    unawaited(NotificationService.instance.rescheduleAll(pets.pets));
    unawaited(HomeWidgetService.refresh(pets.pets));
  };
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: pets),
        ChangeNotifierProvider.value(value: language),
        ChangeNotifierProvider.value(value: auth),
      ],
      child: const PetTimeApp(),
    ),
  );
  // Scheduling the alarms takes hundreds of platform calls; do it after the
  // first frame so the app opens right away.
  unawaited(_startAlarms(pets));
  // The "Próximas tomas" widget, in case time went by since it was drawn.
  unawaited(HomeWidgetService.refresh(pets.pets));
  // The daily copy to Google Drive, if it's on (uploads in the background).
  unawaited(DriveBackupService.instance.backupIfDue(pets.pets));
}

/// Starts Firebase for the login. Without the Firebase files in the build
/// (android/app/google-services.json) there is no login and the app opens
/// as always.
Future<AuthBackend?> _startFirebase() async {
  try {
    await Firebase.initializeApp();
    return FirebaseAuthBackend();
  } catch (e) {
    debugPrint('Firebase is not set up, the app runs without login: $e');
    return null;
  }
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
      title: tr('PetTime'),
      theme: petTimeTheme(),
      locale: context.watch<LanguageState>().locale,
      supportedLocales: [for (final code in AppLang.supported) Locale(code)],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AuthGate(),
    );
  }
}

/// The login screen while the build has a login and nobody signed in or
/// skipped it; the app otherwise.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return context.watch<AuthState>().showLogin
        ? const LoginScreen(asGate: true)
        : const HomeScreen();
  }
}
