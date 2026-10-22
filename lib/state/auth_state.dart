import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_lang.dart';
import '../services/auth_service.dart';

/// The login of the app. The login is optional: whoever taps "Continuar sin
/// cuenta" uses the app as before. Without a [backend] (Firebase is not set
/// up in this build) there is no login at all.
class AuthState extends ChangeNotifier {
  AuthState([this.backend]);

  static const skippedKey = 'login_skipped_v1';

  final AuthBackend? backend;

  StreamSubscription<AuthUser?>? _changes;

  AuthUser? _user;
  AuthUser? get user => _user;

  bool _skipped = false;
  bool _busy = false;
  bool get busy => _busy;

  String? _error;
  String? get error => _error;

  /// The build has a login service.
  bool get available => backend != null;

  bool get signedIn => _user != null;

  /// The app shows the login screen instead of the app.
  bool get showLogin => available && !signedIn && !_skipped;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _skipped = prefs.getBool(skippedKey) ?? false;
    _user = await backend?.restoreUser();
    _changes ??= backend?.changes.listen(_onChanged);
    notifyListeners();
  }

  /// The service says who is signed in changed (e.g. the account was disabled
  /// or deleted elsewhere and the session ended).
  void _onChanged(AuthUser? user) {
    if (user?.uid == _user?.uid) return;
    _user = user;
    notifyListeners();
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  Future<void> skip() async {
    _skipped = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(skippedKey, true);
  }

  Future<bool> signInWithEmail(String email, String password) =>
      _run(() => backend!.signInWithEmail(email, password));

  Future<bool> register(String email, String password) =>
      _run(() => backend!.register(email, password));

  Future<bool> signInWithGoogle() => _run(backend!.signInWithGoogle);

  /// Sends the email to choose a new password. Returns whether it was sent.
  Future<bool> sendPasswordReset(String email) async {
    if (email.trim().isEmpty) {
      _error = tr('Escribí tu email para recuperar la contraseña.');
      notifyListeners();
      return false;
    }
    return _guard(() => backend!.sendPasswordReset(email));
  }

  /// Signs out. Returns whether it did; if not, [error] says so and the user
  /// stays signed in.
  Future<bool> signOut() async {
    try {
      await backend?.signOut();
    } catch (e) {
      debugPrint('Sign out failed: $e');
      _error = tr('No se pudo cerrar la sesión.');
      notifyListeners();
      return false;
    }
    await _forgetUser();
    return true;
  }

  Future<void> _forgetUser() async {
    _user = null;
    // Whoever signs out is asked again next time.
    _skipped = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(skippedKey);
    notifyListeners();
  }

  /// Deletes the account. Returns whether it was deleted; if not, [error]
  /// says why.
  Future<bool> deleteAccount() async {
    final ok = await _guard(backend!.deleteAccount);
    // The account is gone: the phone forgets it even if signing out fails.
    if (ok) await _forgetUser();
    return ok;
  }

  Future<bool> _run(Future<AuthUser> Function() action) async {
    return _guard(() async {
      _user = await action();
    });
  }

  Future<bool> _guard(Future<void> Function() action) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on AuthException catch (e) {
      // An empty message is the user canceling: nothing to show.
      _error = e.message.isEmpty ? null : e.message;
      return false;
    } catch (e) {
      debugPrint('Login failed: $e');
      _error = tr('No se pudo iniciar sesión.');
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
