import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/sign_in_screen.dart';
import '../../features/catalog/presentation/add_edit_book_screen.dart';
import '../../features/catalog/presentation/author_browse_screen.dart';
import '../../features/catalog/presentation/catalog_search_screen.dart';
import '../../features/catalog/presentation/isbn_scan_screen.dart';
import '../../features/catalog/presentation/publisher_browse_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/library/presentation/book_detail_screen.dart';
import '../../features/library/presentation/library_grid_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../auth/auth_providers.dart';

/// Route names as constants (CLAUDE.md convention).
abstract final class Routes {
  static const splash = '/';
  static const signIn = '/sign-in';
  static const home = '/home';
  static const profile = '/profile';
  static const catalogSearch = '/catalog/search';
  static const catalogScan = '/catalog/scan';
  static const catalogAdd = '/catalog/add';
  static const authorBrowse = '/catalog/authors/:authorId';
  static const publisherBrowse = '/catalog/publishers/:publisherId';
  static const library = '/library';
  static const bookDetail = '/library/book/:workId/:editionId';

  static String authorBrowsePath(String authorId) => '/catalog/authors/$authorId';
  static String publisherBrowsePath(String publisherId) => '/catalog/publishers/$publisherId';
  static String bookDetailPath(String workId, String editionId) =>
      '/library/book/$workId/$editionId';
}

/// Re-runs the router's redirect whenever auth or bootstrap state changes
/// (pattern from rupee-diary/app: a ChangeNotifier fed by ref.listen, wired
/// as go_router's refreshListenable).
class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen(authStateProvider, (_, _) => notifyListeners());
    ref.listen(bootstrapProvider, (_, _) => notifyListeners());
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

      if (loc == Routes.splash || loc == Routes.signIn) {
        return Routes.home;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.splash,
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.signIn,
        name: 'sign-in',
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: Routes.home,
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: Routes.profile,
        name: 'profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: Routes.catalogSearch,
        name: 'catalog-search',
        builder: (context, state) => const CatalogSearchScreen(),
      ),
      GoRoute(
        path: Routes.catalogScan,
        name: 'catalog-scan',
        builder: (context, state) => const IsbnScanScreen(),
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
        path: Routes.library,
        name: 'library',
        builder: (context, state) => const LibraryGridScreen(),
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
