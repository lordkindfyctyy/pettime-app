import 'package:google_sign_in/google_sign_in.dart';

import '../config.dart';

//// The Google account used by the Drive backup. The app's login does not use
/// it (see FirebaseAuthBackend.signInWithGoogle): signing in or out of the app
/// must not change or disconnect the account of the backup.
class GoogleAccount {
  GoogleAccount._();
  static final instance = GoogleAccount._();

  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(serverClientId: googleServerClientId);
    _initialized = true;
  }

  /// Signs in (showing the account chooser if needed) and asks for [scopes].
  Future<void> connect(List<String> scopes) async {
    await _ensureInitialized();
    final account =
        await GoogleSignIn.instance.attemptLightweightAuthentication() ??
            await GoogleSignIn.instance.authenticate();
    await account.authorizationClient.authorizeScopes(scopes);
  }

  /// The permission for [scopes] without asking anything, or null when not
  /// signed in or the permission was not granted (or was revoked). Turn it
  /// into an API client with `authClient(scopes: ...)`.
  Future<GoogleSignInClientAuthorization?> authorization(
    List<String> scopes,
  ) async {
    await _ensureInitialized();
    final account =
        await GoogleSignIn.instance.attemptLightweightAuthentication();
    if (account == null) return null;
    return account.authorizationClient.authorizationForScopes(scopes);
  }

  Future<void> signOut() async {
    if (_initialized) await GoogleSignIn.instance.signOut();
  }
}
