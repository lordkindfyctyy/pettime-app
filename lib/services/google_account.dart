import 'package:google_sign_in/google_sign_in.dart';

import '../config.dart';

/// The Google account used by the Drive backup.
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

  /// Signs in with Google (showing the account chooser) and returns the ID
  /// token that Firebase turns into a login.
  Future<String?> signInForIdToken() async {
    await _ensureInitialized();
    final account = await GoogleSignIn.instance.authenticate();
    return account.authentication.idToken;
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
