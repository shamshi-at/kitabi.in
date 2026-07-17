import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_service.dart';

// Passed via --dart-define at build/run time; never hardcoded (CLAUDE.md
// rule: no credential lands in source). Empty means "not configured".
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
bool get supabaseConfigured => supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

// OAuth deep-link callback scheme — must match the intent-filter in
// AndroidManifest.xml and the CFBundleURLTypes entry in Info.plist.
const _oauthRedirect = 'in.kitabi.kitabi://login-callback';

/// Supabase persists its own session as plain SharedPreferences by default;
/// this swaps that for Keychain/Keystore-backed storage instead.
class _SecureSessionStorage extends LocalStorage {
  const _SecureSessionStorage();

  static const _storage = FlutterSecureStorage();
  static const _key = 'kitabi_supabase_session';

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> accessToken() => _storage.read(key: _key);

  @override
  Future<bool> hasAccessToken() async => (await _storage.read(key: _key)) != null;

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _key, value: persistSessionString);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);
}

Future<void> initSupabase() async {
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
    authOptions: FlutterAuthClientOptions(localStorage: _SecureSessionStorage()),
  );
}

class SupabaseAuthService implements AuthService {
  SupabaseAuthService(this._client);

  final SupabaseClient _client;

  KitabiAuthUser? _toKitabiAuthUser(User? user) {
    if (user == null) return null;
    final meta = user.userMetadata ?? {};
    return KitabiAuthUser(
      id: user.id,
      email: user.email,
      fullName: meta['full_name'] as String? ?? meta['name'] as String?,
      avatarUrl: meta['avatar_url'] as String? ?? meta['picture'] as String?,
    );
  }

  @override
  Stream<KitabiAuthUser?> get authStateChanges =>
      _client.auth.onAuthStateChange
          .map((state) => _toKitabiAuthUser(state.session?.user))
          // Supabase fires several events on a cold start — the restored
          // session, then a token refresh (and periodic refreshes after) — all
          // for the same reader. Only the *identity* changing matters here;
          // without this, every token refresh re-emitted, re-ran
          // bootstrapProvider (a network call) and bounced the router back to
          // splash, so the app flashed splash → home → splash → home on launch
          // (owner report, 17 Jul 2026).
          .distinct((a, b) => a?.id == b?.id);

  @override
  KitabiAuthUser? get currentUser => _toKitabiAuthUser(_client.auth.currentSession?.user);

  @override
  Future<void> signInWithGoogle() async {
    // Browser-redirect flow, not the native google_sign_in package — same
    // choice as rupee-diary: one fewer native dependency, one OAuth path to
    // maintain for both providers.
    await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: _oauthRedirect,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  @override
  Future<void> signInWithApple() async {
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
    );
    final idToken = credential.identityToken;
    if (idToken == null) {
      throw StateError('Apple Sign-In did not return an identity token');
    }
    await _client.auth.signInWithIdToken(provider: OAuthProvider.apple, idToken: idToken);
  }

  @override
  Future<void> signOut() => _client.auth.signOut();
}
