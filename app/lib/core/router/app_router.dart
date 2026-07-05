import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/activity/presentation/activity_screen.dart';
import '../../features/auth/presentation/sign_in_screen.dart';
import '../../features/catalog/presentation/add_edit_book_screen.dart';
import '../../features/catalog/presentation/author_browse_screen.dart';
import '../../features/catalog/presentation/catalog_search_screen.dart';
import '../../features/catalog/presentation/isbn_scan_screen.dart';
import '../../features/catalog/presentation/publisher_browse_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/import_books/presentation/import_screen.dart';
import '../../features/insights/presentation/insights_screen.dart';
import '../../features/lending/presentation/lending_ledger_screen.dart';
import '../../features/library/presentation/book_detail_screen.dart';
import '../../features/library/presentation/library_grid_screen.dart';
import '../../features/onboarding/onboarding_providers.dart';
import '../../features/onboarding/presentation/welcome_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/recommendations/presentation/recommendations_screen.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/update_gate/presentation/update_screen.dart';
import '../../data/api/api_client.dart';
import '../auth/auth_providers.dart';
import 'shell_scaffold.dart';

/// Route names as constants (CLAUDE.md convention).
abstract final class Routes {
  static const splash = '/';
  static const signIn = '/sign-in';
  static const update = '/update';
  static const welcome = '/welcome';
  static const home = '/home';
  static const profile = '/profile';
  static const catalogSearch = '/catalog/search';
  static const catalogScan = '/catalog/scan';
  static const catalogAdd = '/catalog/add';
  static const authorBrowse = '/catalog/authors/:authorId';
  static const publisherBrowse = '/catalog/publishers/:publisherId';
  static const library = '/library';
  static const lendingLedger = '/lending';
  static const insights = '/insights';
  static const recommendations = '/recommendations';
  static const importBooks = '/import';
  static const activity = '/activity';
  // Top-level (not under a nav branch) so it covers the bottom nav full-screen.
  static const bookDetail = '/book/:workId/:editionId';

  static String authorBrowsePath(String authorId) => '/catalog/authors/$authorId';
  static String publisherBrowsePath(String publisherId) => '/catalog/publishers/$publisherId';
  static String bookDetailPath(String workId, String editionId) => '/book/$workId/$editionId';
}

/// Re-runs the router's redirect whenever auth or bootstrap state changes
/// (pattern from rupee-diary/app: a ChangeNotifier fed by ref.listen, wired
/// as go_router's refreshListenable).
class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen(authStateProvider, (_, _) => notifyListeners());
    ref.listen(bootstrapProvider, (_, _) => notifyListeners());
    ref.listen(updateRequiredProvider, (_, _) => notifyListeners());
    ref.listen(onboardingSeenProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefreshNotifier(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final loc = state.matchedLocation;

      // A 426 from the API locks the app onto the update screen (version gate).
      if (ref.read(updateRequiredProvider)) {
        return loc == Routes.update ? null : Routes.update;
      }

      final authState = ref.read(authStateProvider);

      // Auth state hasn't resolved its first value yet — stay on splash.
      if (!authState.hasValue && !authState.hasError) {
        return loc == Routes.splash ? null : Routes.splash;
      }

      final signedIn = authState.valueOrNull != null;
      if (!signedIn) {
        return loc == Routes.signIn ? null : Routes.signIn;
      }

      // Signed in — hold on splash until the profile bootstrap resolves, so
      // /me is guaranteed to exist by the time any other screen builds.
      final bootstrap = ref.read(bootstrapProvider);
      if (!bootstrap.hasValue && !bootstrap.hasError) {
        return loc == Routes.splash ? null : Routes.splash;
      }

      // First run: show the welcome once (hold on splash until it resolves).
      final onboarding = ref.read(onboardingSeenProvider);
      if (!onboarding.hasValue && !onboarding.hasError) {
        return loc == Routes.splash ? null : Routes.splash;
      }
      if (onboarding.valueOrNull == false) {
        return loc == Routes.welcome ? null : Routes.welcome;
      }
      if (loc == Routes.splash || loc == Routes.signIn || loc == Routes.welcome) {
        return Routes.home;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        name: 'splash',
        builder: (context, state) => SplashScreen(),
      ),
      GoRoute(
        path: Routes.signIn,
        name: 'sign-in',
        builder: (context, state) => SignInScreen(),
      ),
      GoRoute(
        path: Routes.update,
        name: 'update',
        builder: (context, state) => UpdateScreen(),
      ),
      GoRoute(
        path: Routes.welcome,
        name: 'welcome',
        builder: (context, state) => WelcomeScreen(),
      ),
      // The four tabs live in a persistent bottom-nav shell (S3). Each is its
      // own branch so tab state (scroll position, etc.) is preserved.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            ShellScaffold(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                name: 'home',
                builder: (context, state) => HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.library,
                name: 'library',
                builder: (context, state) => LibraryGridScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.lendingLedger,
                name: 'lending-ledger',
                builder: (context, state) => LendingLedgerScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.insights,
                name: 'insights',
                builder: (context, state) => InsightsScreen(),
              ),
            ],
          ),
        ],
      ),
      // Full-screen routes pushed above the shell (they cover the bottom nav).
      GoRoute(
        path: Routes.profile,
        name: 'profile',
        builder: (context, state) => ProfileScreen(),
      ),
      GoRoute(
        path: Routes.recommendations,
        name: 'recommendations',
        builder: (context, state) => RecommendationsScreen(),
      ),
      GoRoute(
        path: Routes.importBooks,
        name: 'import',
        builder: (context, state) => ImportScreen(),
      ),
      GoRoute(
        path: Routes.activity,
        name: 'activity',
        builder: (context, state) => ActivityScreen(),
      ),
      GoRoute(
        path: Routes.catalogSearch,
        name: 'catalog-search',
        builder: (context, state) => CatalogSearchScreen(),
      ),
      GoRoute(
        path: Routes.catalogScan,
        name: 'catalog-scan',
        builder: (context, state) => IsbnScanScreen(),
      ),
      GoRoute(
        path: Routes.catalogAdd,
        name: 'catalog-add',
        builder: (context, state) => AddEditBookScreen(workId: state.extra as String?),
      ),
      GoRoute(
        path: Routes.authorBrowse,
        name: 'author-browse',
        builder: (context, state) =>
            AuthorBrowseScreen(authorId: state.pathParameters['authorId']!),
      ),
      GoRoute(
        path: Routes.publisherBrowse,
        name: 'publisher-browse',
        builder: (context, state) =>
            PublisherBrowseScreen(publisherId: state.pathParameters['publisherId']!),
      ),
      GoRoute(
        path: Routes.bookDetail,
        name: 'book-detail',
        builder: (context, state) => BookDetailScreen(
          workId: state.pathParameters['workId']!,
          editionId: state.pathParameters['editionId']!,
        ),
      ),
    ],
  );
});
