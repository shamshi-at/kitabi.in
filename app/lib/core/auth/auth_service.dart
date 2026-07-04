/// Auth abstraction so the rest of the app never touches Supabase directly
/// (pattern from rupee-diary/app). [UnconfiguredAuthService] lets the app
/// boot and render offline-appropriate UI before real Supabase credentials
/// exist — see [supabaseConfigured] in supabase_auth_service.dart.
class KitabiAuthUser {
  const KitabiAuthUser({required this.id, this.email, this.fullName, this.avatarUrl});

  final String id;
  final String? email;
  final String? fullName;
  final String? avatarUrl;
}

abstract class AuthService {
  Stream<KitabiAuthUser?> get authStateChanges;
  KitabiAuthUser? get currentUser;

  Future<void> signInWithGoogle();
  Future<void> signInWithApple();
  Future<void> signOut();
}

class UnconfiguredAuthService implements AuthService {
  const UnconfiguredAuthService();

  @override
  Stream<KitabiAuthUser?> get authStateChanges => Stream<KitabiAuthUser?>.value(null);

  @override
  KitabiAuthUser? get currentUser => null;

  @override
  Future<void> signInWithGoogle() async {
    throw StateError('Supabase is not configured — pass --dart-define=SUPABASE_URL=... '
        'and SUPABASE_PUBLISHABLE_KEY=...');
  }

  @override
  Future<void> signInWithApple() => signInWithGoogle();

  @override
  Future<void> signOut() async {}
}
