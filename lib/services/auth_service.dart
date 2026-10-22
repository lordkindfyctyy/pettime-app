import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../l10n/app_lang.dart';

/// Who is signed in.
class AuthUser {
  const AuthUser({required this.uid, this.email, this.name});

  final String uid;
  final String? email;
  final String? name;

  /// What to show as the name of the account.
  String get label {
    final n = name?.trim() ?? '';
    if (n.isNotEmpty) return n;
    return email ?? '';
  }
}

/// A failed sign in, with a message that can be shown as is.
class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What the app needs from the login service: Firebase in the app, a fake in
/// the tests.
abstract class AuthBackend {
  AuthUser? get currentUser;

  /// Who was signed in the last time, once the service has restored them
  /// (right at the start, [currentUser] can still be empty).
  Future<AuthUser?> restoreUser();

  /// Who is signed in, every time it changes: also when the service signs the
  /// user out by itself (account disabled or deleted, token revoked).
  Stream<AuthUser?> get changes;

  Future<AuthUser> signInWithEmail(String email, String password);
  Future<AuthUser> register(String email, String password);

  /// Throws an [AuthException] with an empty message when the user cancels.
  Future<AuthUser> signInWithGoogle();

  Future<void> sendPasswordReset(String email);
  Future<void> signOut();

  /// Deletes the account of whoever is signed in (Play asks apps with
  /// accounts to let them be deleted from the app).
  Future<void> deleteAccount();
}

/// [AuthBackend] on Firebase Authentication.
class FirebaseAuthBackend implements AuthBackend {
  FirebaseAuthBackend([fb.FirebaseAuth? auth])
      : _auth = auth ?? fb.FirebaseAuth.instance;

  final fb.FirebaseAuth _auth;

  static AuthUser? _user(fb.User? u) => u == null
      ? null
      : AuthUser(uid: u.uid, email: u.email, name: u.displayName);

  @override
  AuthUser? get currentUser => _user(_auth.currentUser);

  @override
  Future<AuthUser?> restoreUser() async =>
      _user(await _auth.authStateChanges().first);

  @override
  Stream<AuthUser?> get changes => _auth.authStateChanges().map(_user);

  /// The message for a Firebase error code.
  static String messageFor(String code) => switch (code) {
        'invalid-email' => tr('El email no es válido.'),
        'user-not-found' ||
        'wrong-password' ||
        'invalid-credential' =>
          tr('Email o contraseña incorrectos.'),
        'email-already-in-use' => tr('Ya hay una cuenta con ese email.'),
        'weak-password' =>
          tr('La contraseña es muy débil: usá al menos 6 caracteres.'),
        'user-disabled' => tr('Esta cuenta está deshabilitada.'),
        'network-request-failed' => tr('No hay conexión a internet.'),
        'too-many-requests' =>
          tr('Demasiados intentos. Probá de nuevo en un rato.'),
        _ => tr('No se pudo iniciar sesión ({code}).', {'code': code}),
      };

  Future<AuthUser> _run(Future<fb.UserCredential> Function() action) async {
    try {
      final user = _user((await action()).user);
      if (user == null) {
        throw AuthException(tr('No se pudo iniciar sesión.'));
      }
      return user;
    } on fb.FirebaseAuthException catch (e) {
      // An empty message is the user closing the window: nothing to show.
      throw AuthException(isCancel(e.code) ? '' : messageFor(e.code));
    }
  }

  @override
  Future<AuthUser> signInWithEmail(String email, String password) => _run(
        () => _auth.signInWithEmailAndPassword(
          email: email.trim(),
          password: password,
        ),
      );

  @override
  Future<AuthUser> register(String email, String password) => _run(
        () => _auth.createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        ),
      );

  @override
  Future<AuthUser> signInWithGoogle() async {
    // Firebase's own Google flow, not the google_sign_in plugin: that one is
    // shared with the Drive backup, and signing in or out of the app would
    // change or disconnect the account the backup uses.
    return _run(() => _auth.signInWithProvider(fb.GoogleAuthProvider()));
  }

  /// The codes Firebase gives when the user closes the Google window.
  static bool isCancel(String code) => const {
        'web-context-canceled',
        'web-context-already-presented',
        'canceled',
        'cancelled-popup-request',
        'popup-closed-by-user',
      }.contains(code);

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException(messageFor(e.code));
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> deleteAccount() async {
    try {
      await _auth.currentUser?.delete();
    } on fb.FirebaseAuthException catch (e) {
      // Firebase only deletes accounts that signed in a short while ago.
      if (e.code == 'requires-recent-login') {
        throw AuthException(tr(
            'Por seguridad, cerrá sesión, volvé a entrar y probá de nuevo.'));
      }
      throw AuthException(
          tr('No se pudo borrar la cuenta ({code}).', {'code': e.code}));
    }
    await signOut();
  }
}
