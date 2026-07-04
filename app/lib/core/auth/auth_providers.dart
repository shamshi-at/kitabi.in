import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../data/api/api_client.dart';
import 'auth_service.dart';
import 'supabase_auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  if (!supabaseConfigured) return const UnconfiguredAuthService();
  return SupabaseAuthService(Supabase.instance.client);
});

/// Drives the router redirect (CLAUDE.md: "auth guard redirect" convention).
final authStateProvider = StreamProvider<KitabiAuthUser?>((ref) {
  final service = ref.watch(authServiceProvider);
  return service.authStateChanges;
});

/// Creates the profile row on first login; the router waits for this to
/// resolve before letting a signed-in user reach anywhere but the splash
/// screen, so /me is guaranteed to exist by the time Home renders.
final bootstrapProvider = FutureProvider<void>((ref) async {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return;
  await ref.watch(apiClientProvider).bootstrap();
});
