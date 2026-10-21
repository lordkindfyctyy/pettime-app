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
    _user = backend?.currentUser;
    notifyListeners();
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

  Future<void> signOut() async {
    await backend?.signOut();
    _user = null;
    // Whoever signs out is asked again next time.
    _skipped = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(skippedKey);
    notifyListeners();
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
