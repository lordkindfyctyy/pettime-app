import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';

import '../l10n/app_lang.dart';
import 'google_account.dart';

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
      throw AuthException(messageFor(e.code));
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
    final String? idToken;
    try {
      idToken = await GoogleAccount.instance.signInForIdToken();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        throw const AuthException('');
      }
      throw AuthException(
        tr('No se pudo iniciar sesión con Google ({code}).', {'code': e.code.name}),
      );
    }
    if (idToken == null) {
      throw AuthException(tr('No se pudo iniciar sesión con Google.'));
    }
    return _run(
      () => _auth.signInWithCredential(
        fb.GoogleAuthProvider.credential(idToken: idToken),
      ),
    );
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException(messageFor(e.code));
    }
  }

  @override
  Future<void> signOut() async {
    await GoogleAccount.instance.signOut();
    await _auth.signOut();
  }

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
