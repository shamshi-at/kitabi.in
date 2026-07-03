import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/presentation/home_screen.dart';

/// Route names as constants (CLAUDE.md convention).
abstract final class Routes {
  static const home = '/';
}

final routerProvider = Provider<GoRouter>((ref) {
  // Auth-guard redirect goes here once Supabase auth lands.
  return GoRouter(
    initialLocation: Routes.home,
    routes: [
      GoRoute(
        path: Routes.home,
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
    ],
  );
});
