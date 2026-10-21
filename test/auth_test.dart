import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pettime_app/l10n/app_lang.dart';
import 'package:pettime_app/main.dart';
import 'package:pettime_app/services/auth_service.dart';
import 'package:pettime_app/state/auth_state.dart';
import 'package:pettime_app/state/language_state.dart';
import 'package:pettime_app/state/pets_state.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A login service in memory: one account, ana@example.com / secreto.
class FakeAuth implements AuthBackend {
  AuthUser? _user;
  String? resetFor;

  @override
  AuthUser? get currentUser => _user;

  @override
  Future<AuthUser> signInWithEmail(String email, String password) async {
    if (email.trim() != 'ana@example.com' || password != 'secreto') {
      throw const AuthException('Email o contraseña incorrectos.');
    }
    return _user = const AuthUser(uid: 'u1', email: 'ana@example.com');
  }

  @override
  Future<AuthUser> register(String email, String password) async =>
      _user = AuthUser(uid: 'u2', email: email.trim());

  @override
  Future<AuthUser> signInWithGoogle() async =>
      throw const AuthException(''); // the user canceled

  @override
  Future<void> sendPasswordReset(String email) async => resetFor = email;

  @override
  Future<void> signOut() async => _user = null;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLang.code = 'es';
  });

  group('AuthState', () {
    test('without a backend there is no login', () async {
      final auth = AuthState();
      await auth.load();
      expect(auth.available, isFalse);
      expect(auth.showLogin, isFalse);
    });

    test('asks to sign in until the user signs in or skips', () async {
      final auth = AuthState(FakeAuth());
      await auth.load();
      expect(auth.showLogin, isTrue);

      await auth.skip();
      expect(auth.showLogin, isFalse);

      // the choice is remembered
      final again = AuthState(FakeAuth());
      await again.load();
      expect(again.showLogin, isFalse);
    });

    test('signs in, shows the error of a wrong password, and signs out', () async {
      final auth = AuthState(FakeAuth());
      await auth.load();

      expect(await auth.signInWithEmail('ana@example.com', 'mal'), isFalse);
      expect(auth.error, 'Email o contraseña incorrectos.');
      expect(auth.signedIn, isFalse);

      expect(await auth.signInWithEmail(' ana@example.com ', 'secreto'), isTrue);
      expect(auth.error, isNull);
      expect(auth.signedIn, isTrue);
      expect(auth.showLogin, isFalse);
      expect(auth.user!.label, 'ana@example.com');

      await auth.signOut();
      expect(auth.signedIn, isFalse);
      expect(auth.showLogin, isTrue);
    });

    test('canceling Google is not an error', () async {
      final auth = AuthState(FakeAuth());
      await auth.load();
      expect(await auth.signInWithGoogle(), isFalse);
      expect(auth.error, isNull);
    });

    test('password recovery needs the email', () async {
      final backend = FakeAuth();
      final auth = AuthState(backend);
      expect(await auth.sendPasswordReset(' '), isFalse);
      expect(auth.error, isNotNull);
      expect(await auth.sendPasswordReset('ana@example.com'), isTrue);
      expect(backend.resetFor, 'ana@example.com');
      expect(auth.error, isNull);
    });

    test('the user label falls back from name to email', () {
      expect(const AuthUser(uid: 'x', name: 'Ana', email: 'a@b.c').label, 'Ana');
      expect(const AuthUser(uid: 'x', email: 'a@b.c').label, 'a@b.c');
      expect(const AuthUser(uid: 'x').label, '');
    });

    test('Firebase error codes have a message', () {
      expect(
        FirebaseAuthBackend.messageFor('wrong-password'),
        'Email o contraseña incorrectos.',
      );
      expect(
        FirebaseAuthBackend.messageFor('email-already-in-use'),
        'Ya hay una cuenta con ese email.',
      );
      expect(FirebaseAuthBackend.messageFor('algo-raro'), contains('algo-raro'));
    });
  });

  testWidgets('the login screen opens first, signs in, and lets you skip', (tester) async {
    await initializeDateFormatting();
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final auth = AuthState(FakeAuth());
    await auth.load();
    final language = LanguageState();
    await language.load();
    await language.setChoice('es');
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => PetsState()),
          ChangeNotifierProvider.value(value: language),
          ChangeNotifierProvider.value(value: auth),
        ],
        child: const PetTimeApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Continuar sin cuenta'), findsOneWidget);
    expect(find.text('Continuar con Google'), findsOneWidget);

    // the form checks before asking the service
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(find.text('Ingresá tu email'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'ana@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'mal-clave');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(find.text('Email o contraseña incorrectos.'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(1), 'secreto');
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();
    expect(find.text('Continuar sin cuenta'), findsNothing);
    expect(find.text('Hoy'), findsWidgets); // the app

    await auth.signOut();
    await tester.pumpAndSettle();
    expect(find.text('Continuar sin cuenta'), findsOneWidget);

    await tester.tap(find.text('Continuar sin cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('Continuar sin cuenta'), findsNothing);
  });
}
