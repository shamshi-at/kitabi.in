import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/activity/presentation/activity_screen.dart';
import '../../features/auth/presentation/sign_in_screen.dart';
import '../../features/catalog/presentation/add_edit_book_screen.dart';
import '../../features/catalog/presentation/add_edition_screen.dart';
import '../../features/catalog/presentation/author_browse_screen.dart';
import '../../features/catalog/presentation/author_picker_screen.dart';
import '../../features/catalog/presentation/book_link_resolver_screen.dart';
import '../../features/catalog/presentation/browse_screen.dart';
import '../../features/catalog/presentation/catalog_search_screen.dart';
import '../../features/catalog/presentation/isbn_scan_screen.dart';
import '../../features/catalog/presentation/publisher_browse_screen.dart';
import '../../features/catalog/presentation/publisher_picker_screen.dart';
import '../../features/catalog/presentation/series_browse_screen.dart';
import '../../features/catalog/presentation/series_picker_screen.dart';
import '../../features/catalog/presentation/revision_inbox_screen.dart';
import '../../features/catalog/presentation/work_picker_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/import_books/presentation/import_screen.dart';
import '../../features/insights/presentation/insights_screen.dart';
import '../../features/lending/presentation/lending_ledger_screen.dart';
import '../../features/library/presentation/book_detail_screen.dart';
import '../../features/library/presentation/library_grid_screen.dart';
import '../../features/library/presentation/reading_timer_screen.dart';
import '../../features/library/presentation/review_editor_screen.dart';
import '../../features/onboarding/onboarding_providers.dart';
import '../../features/onboarding/presentation/welcome_screen.dart';
import '../../features/connections/presentation/connection_loans_screen.dart';
import '../../features/connections/presentation/connections_screen.dart';
import '../../features/connections/presentation/public_profile_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/recommendations/presentation/recommendations_screen.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/update_gate/presentation/update_screen.dart';
import '../../data/api/api_client.dart';
import '../../features/onboarding/presentation/language_picker_screen.dart';
import '../../features/profile/providers/profile_providers.dart';
import '../auth/auth_providers.dart';
import 'shell_scaffold.dart';

/// Route names as constants (CLAUDE.md convention).
abstract final class Routes {
  static const splash = '/';
  static const signIn = '/sign-in';
  static const update = '/update';
  static const welcome = '/welcome';
  static const languages = '/languages';
  static const home = '/home';
  static const profile = '/profile';
  static const catalogSearch = '/catalog/search';
  static const catalogBrowse = '/catalog/browse';
  static const catalogScan = '/catalog/scan';
  // Same scanner, but pops with the looked-up work (or raw ISBN) so the manual
  // add-book form can prefill itself instead of adding straight to the library.
  static const catalogScanResult = '/catalog/scan-result';
  static const catalogAdd = '/catalog/add';
  // Add another edition to an existing Work; workId + optional title via `extra`.
  static const catalogAddEdition = '/catalog/add-edition';
  static const authorPicker = '/catalog/author-picker';
  static const publisherPicker = '/catalog/publisher-picker';
  // Pick a series instead of typing one — see SeriesPickerScreen for why.
  static const seriesPicker = '/catalog/series-picker';
  // Pick an existing Work — used when linking a translation.
  static const workPicker = '/catalog/work-picker';
  static const authorBrowse = '/catalog/authors/:authorId';
  static const publisherBrowse = '/catalog/publishers/:publisherId';
  static const seriesBrowse = '/catalog/series/:seriesId';
  // Short, shareable/deep-link paths that mirror the landing page's public
  // pages (kitabi.in/b/:id, /a/:id, /p/:id). Registering them here means an
  // opened universal link lands on the right screen in-app.
  static const bookLink = '/b/:workId';
  static const authorLink = '/a/:authorId';
  static const publisherLink = '/p/:publisherId';
  static const library = '/library';
  static const lendingLedger = '/lending';
  static const connections = '/connections';
  static const connectionLoans = '/connections/loans';
  static const insights = '/insights';
  static const recommendations = '/recommendations';
  static const importBooks = '/import';
  static const activity = '/activity';
  // Top-level (not under a nav branch) so it covers the bottom nav full-screen.
  static const bookDetail = '/book/:workId/:editionId';
  // Dedicated rate & review page; book display data (title/author/cover) via `extra`.
  static const reviewEditor = '/review/:workId';
  // Full-screen reading-session timer; display data (title/author/pages) via `extra`.
  static const readingTimer = '/reading-timer/:libraryEntryId';
  // Approval inbox — pending edits to books this reader contributed.
  static const revisions = '/catalog/revisions';
  // Another reader's public profile; display name via `extra`.
  static const publicProfile = '/reader/:userId';

  static String authorBrowsePath(String authorId) => '/catalog/authors/$authorId';
  static String publisherBrowsePath(String publisherId) => '/catalog/publishers/$publisherId';
  static String seriesBrowsePath(String seriesId) => '/catalog/series/$seriesId';
  static String bookDetailPath(String workId, String editionId) => '/book/$workId/$editionId';
  static String reviewEditorPath(String workId) => '/review/$workId';
  static String readingTimerPath(String libraryEntryId) => '/reading-timer/$libraryEntryId';
  static String publicProfilePath(String userId) => '/reader/$userId';
}

/// Opens the loans-with-one-person page — every counterparty name in the app
/// routes through here. Linked Kitabi users match by [userId]; self-logged
/// free-text names match by [name].
void openPersonLoans(BuildContext context, {String? userId, required String name}) {
  context.push(Routes.connectionLoans, extra: {'userId': userId, 'name': name});
}

/// The app's own URL scheme (declared in iOS `CFBundleURLTypes`), shared with
/// the Supabase OAuth callback — hence the separate host below, so the two can
/// never be confused for one another.
const kAppScheme = 'in.kitabi.kitabi';
const kReadingTimerHost = 'reading-timer';

/// The route an iOS Live Activity tap maps to, or null when the link isn't
/// one of ours. Pulled out of the listener so the rule can be tested without a
/// platform channel — and so the *scheme* check stays visible: this scheme is
/// shared with the Supabase OAuth callback, and swallowing one of those links
/// would break sign-in rather than the timer.
String? readingTimerRouteFor(Uri uri) {
  if (!uri.isScheme(kAppScheme) ||
      uri.host != kReadingTimerHost) {
    return null;
  }
  final id = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
  if (id.isEmpty) return null;
  return Routes.readingTimerPath(id);
}

/// A navigation target that arrived before the router was usable — a
/// notification tap or universal link on a cold start. Navigating immediately
/// gets swallowed: the redirect below pins everything to splash until auth +
/// bootstrap resolve, then routes splash → home, losing the target. The
/// redirect consumes this instead of returning home once the session is ready.
String? pendingExternalTarget;

/// Route an externally-triggered navigation (push tap, app link): straight
/// away when the app is up, or parked in [pendingExternalTarget] for the
/// redirect to consume when the session is still booting.
void navigateFromExternal(GoRouter router, String location) {
  final config = router.routerDelegate.currentConfiguration;
  final current = config.uri.path;
  if (current == Routes.splash || current == Routes.signIn) {
    pendingExternalTarget = location;
    return;
  }
  // Already there — the OS has done the only thing left to do by bringing the
  // app forward. Pushing again stacks a second copy of the same screen, and
  // for the reading timer that is actively destructive: the buried copy's
  // "someone else stopped this sitting" guard fires when the top one stops and
  // pops it, so Stop & log threw the reader back to Home instead of showing
  // the page question (found tapping the live notification on an Android
  // emulator, 26 Jul 2026 — every route these handlers reach has the same
  // duplicate-stacking hazard, so the guard belongs here).
  //
  // It has to be the *top match*, not `uri.path`: go_router leaves `uri` on
  // the last declarative location, so after an imperative `push` it still
  // reads "/home" and a comparison against it would never fire (this guard was
  // written that way first, and was dead code — caught by probing the match
  // list rather than by trusting the field name).
  final top = config.matches.isEmpty ? current : config.matches.last.matchedLocation;
  if (top == location) return;
  router.push(location);
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
    ref.listen(meProvider, (_, _) => notifyListeners()); // preferred-languages gate
  }
}

/// A live reference to the app's single [GoRouter], set the moment
/// [routerProvider] builds — lets code with no `Ref`/`BuildContext` (the
/// reading-timer notification-tap handler, which can run in a background
/// isolate) drive navigation via [navigateFromExternal]. Null before the
/// router first builds (or after its `ProviderScope` is torn down); callers
/// fall back to [pendingExternalTarget] in that case, same as a cold start.
GoRouter? globalRouter;

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefreshNotifier(ref);
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      // An external link can arrive here as a *whole URI* — scheme, host and
      // all — because Flutter's engine hands incoming deep links straight to
      // the router, which has no route named `in.kitabi.kitabi://…` and shows
      // "Page Not Found". That is what a tap on the iOS Live Activity did
      // (owner report, 26 Jul 2026): the widget's own tap URL never reached
      // `DeepLinkListener` at all, so testing that listener proved nothing
      // about the real delivery path. Rewriting it here catches the link
      // whichever way it arrives, and parking it means a *cold-start* tap
      // survives the splash/bootstrap gates below instead of landing on Home.
      final external = readingTimerRouteFor(state.uri);
      if (external != null) {
        pendingExternalTarget = external;
        return external;
      }

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
      // `.isLoading` (not `!hasValue`) so a background re-run triggered by
      // authStateProvider settling — which Riverpod exposes as "loading" but
      // still carrying the previous build's value — still holds here instead
      // of reading that stale value as final.
      // Hold on splash while the bootstrap resolves — AND if it failed without
      // ever having succeeded. Letting an *error* through was how a signed-in
      // reader reached the language picker with no profile row: its first save
      // is a PATCH /me, which could only 404, and nothing ever called bootstrap
      // again (owner report, 13 Aug 2026). The splash offers a retry, so this
      // is a held door with a handle, not a dead end.
      //
      // `!bootstrap.hasValue` matters: once a session has bootstrapped, a later
      // background re-run that errors (a token refresh during a tunnel) must not
      // yank a reader out of the app and back to the splash.
      final bootstrap = ref.read(bootstrapProvider);
      if (bootstrap.isLoading || (bootstrap.hasError && !bootstrap.hasValue)) {
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

      // Ask for reading languages once (after the welcome). Server-side, so it
      // re-asks on any device until at least one is set. `.isLoading` (see
      // bootstrap above) so a background re-fetch never reads a stale/empty
      // cached value as final and flashes the language picker.
      final me = ref.read(meProvider);
      if (me.isLoading) {
        return loc == Routes.splash ? null : Routes.splash;
      }
      // A fetch failure (a network hiccup right at cold start — e.g. the
      // phone is still reconnecting Wi-Fi at unlock) must not be misread as
      // "confirmed no languages set": `.valueOrNull` on a first-ever
      // `AsyncError` is null same as a real empty response, which flashed the
      // picker for already-configured accounts (owner report, 15 Jul 2026).
      // Only a response that actually came back gets to answer this gate.
      if (!me.hasError || me.hasValue) {
        final langs = (me.valueOrNull?['preferred_languages'] as List?) ?? const [];
        if (langs.isEmpty) {
          return loc == Routes.languages ? null : Routes.languages;
        }
      }

      if (loc == Routes.splash ||
          loc == Routes.signIn ||
          loc == Routes.welcome ||
          loc == Routes.languages) {
        // A cold-start push tap / app link waited out the boot — honour it now
        // instead of landing on home.
        final target = pendingExternalTarget;
        if (target != null) {
          pendingExternalTarget = null;
          return target;
        }
        return Routes.home;
      }
      // Arrived, and no gate sent us elsewhere — so a parked target has been
      // honoured and must not fire again later (the next trip through
      // splash/sign-in would otherwise re-open it out of nowhere).
      if (pendingExternalTarget == loc) pendingExternalTarget = null;
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
      GoRoute(
        path: Routes.languages,
        name: 'languages',
        builder: (context, state) => LanguagePickerScreen(),
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
                builder: (context, state) => LibraryGridScreen(
                  initialStatus: state.uri.queryParameters['status'],
                  initialShelf: state.uri.queryParameters['shelf'],
                ),
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
        path: Routes.connectionLoans,
        name: 'connection-loans',
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>? ?? const {};
          return ConnectionLoansScreen(
            userId: args['userId'] as String?,
            name: args['name'] as String? ?? '',
          );
        },
      ),
      GoRoute(
        path: Routes.connections,
        name: 'connections',
        builder: (context, state) => ConnectionsScreen(),
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
        builder: (context, state) =>
            CatalogSearchScreen(initialQuery: state.uri.queryParameters['q']),
      ),
      GoRoute(
        path: Routes.catalogBrowse,
        name: 'catalog-browse',
        builder: (context, state) => BrowseScreen(),
      ),
      GoRoute(
        path: Routes.catalogScan,
        name: 'catalog-scan',
        builder: (context, state) => IsbnScanScreen(),
      ),
      GoRoute(
        path: Routes.catalogScanResult,
        name: 'catalog-scan-result',
        builder: (context, state) => IsbnScanScreen(returnResult: true),
      ),
      GoRoute(
        path: Routes.catalogAdd,
        name: 'catalog-add',
        builder: (context, state) {
          // extra is historically a bare workId String (edit mode); the scan
          // flow's not-found path hands over a map so the typed ISBN survives
          // into the blank form, and the borrow sheet's "not in the catalog?"
          // path passes a typed title plus `returnCreated` to get the new book
          // handed back to it (this route then pops with the created Work).
          final extra = state.extra;
          final map = extra is Map<String, dynamic> ? extra : const <String, dynamic>{};
          return AddEditBookScreen(
            workId: extra is String ? extra : map['workId'] as String?,
            initialIsbn: map['isbn'] as String?,
            initialTitle: map['title'] as String?,
            // T6's "Add a translation": the original's summary, pre-linking
            // the form's Translated-from row.
            initialOriginal: map['originalWork'] as Map<String, dynamic>?,
            returnCreated: map['returnCreated'] as bool? ?? false,
          );
        },
      ),
      GoRoute(
        path: Routes.revisions,
        name: 'revisions',
        builder: (context, state) => RevisionInboxScreen(),
      ),
      GoRoute(
        path: Routes.publicProfile,
        name: 'public-profile',
        builder: (context, state) => PublicProfileScreen(
          userId: state.pathParameters['userId']!,
          name: state.extra as String?,
        ),
      ),
      GoRoute(
        path: Routes.authorPicker,
        name: 'author-picker',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return AuthorPickerScreen(
            initialName: extra?['name'] as String?,
            initialIsMe: extra?['isMe'] as bool? ?? false,
          );
        },
      ),
      GoRoute(
        path: Routes.publisherPicker,
        name: 'publisher-picker',
        builder: (context, state) => PublisherPickerScreen(),
      ),
      GoRoute(
        path: Routes.seriesPicker,
        name: 'series-picker',
        builder: (context, state) => SeriesPickerScreen(
          initialName: (state.extra as Map<String, dynamic>?)?['name'] as String?,
        ),
      ),
      GoRoute(
        path: Routes.workPicker,
        name: 'work-picker',
        builder: (context, state) {
          // extra is historically a bare excludeWorkId String (the book
          // page's "Link existing"); the add form's Translated-from flow
          // passes a map to get the T2 original-picker flavour with the
          // stub-seed carried over.
          final extra = state.extra;
          final map = extra is Map<String, dynamic> ? extra : const <String, dynamic>{};
          return WorkPickerScreen(
            excludeWorkId: extra is String ? extra : map['excludeWorkId'] as String?,
            forOriginal: map['forOriginal'] as bool? ?? false,
            seed: map['seed'] as Map<String, dynamic>?,
          );
        },
      ),
      GoRoute(
        path: Routes.catalogAddEdition,
        name: 'catalog-add-edition',
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>? ?? const {};
          return AddEditionScreen(
            workId: args['workId'] as String,
            workTitle: args['title'] as String?,
          );
        },
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
        path: Routes.seriesBrowse,
        name: 'series-browse',
        builder: (context, state) => SeriesBrowseScreen(
          seriesId: state.pathParameters['seriesId']!,
          // A first-frame hint only — the list itself is fetched, never taken
          // from `extra`, so an entry point that carries none still works.
          seriesName: (state.extra as Map<String, dynamic>?)?['name'] as String?,
        ),
      ),
      // Deep-link / share-link targets — short paths that mirror kitabi.in.
      GoRoute(
        path: Routes.bookLink,
        name: 'book-link',
        builder: (context, state) =>
            BookLinkResolverScreen(workId: state.pathParameters['workId']!),
      ),
      GoRoute(
        path: Routes.authorLink,
        name: 'author-link',
        builder: (context, state) =>
            AuthorBrowseScreen(authorId: state.pathParameters['authorId']!),
      ),
      GoRoute(
        path: Routes.publisherLink,
        name: 'publisher-link',
        builder: (context, state) =>
            PublisherBrowseScreen(publisherId: state.pathParameters['publisherId']!),
      ),
      GoRoute(
        path: Routes.reviewEditor,
        name: 'review-editor',
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>? ?? const {};
          return ReviewEditorScreen(
            workId: state.pathParameters['workId']!,
            title: args['title'] as String?,
            author: args['author'] as String?,
            coverUrl: args['coverUrl'] as String?,
          );
        },
      ),
      GoRoute(
        path: Routes.bookDetail,
        name: 'book-detail',
        builder: (context, state) => BookDetailScreen(
          workId: state.pathParameters['workId']!,
          editionId: state.pathParameters['editionId']!,
        ),
      ),
      GoRoute(
        path: Routes.readingTimer,
        name: 'reading-timer',
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>? ?? const {};
          return ReadingTimerScreen(
            libraryEntryId: state.pathParameters['libraryEntryId']!,
            title: args['title'] as String?,
            author: args['author'] as String?,
            currentPage: args['currentPage'] as int?,
            pageCount: args['pageCount'] as int?,
            coverUrl: args['coverUrl'] as String?,
          );
        },
      ),
    ],
  );
  globalRouter = router;
  ref.onDispose(() {
    if (identical(globalRouter, router)) globalRouter = null;
  });
  return router;
});
