import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// API base URL — passed via --dart-define; empty is fine for now (every call
// simply fails until the API is deployed and this is set).
const _apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8000');

/// The client version, sent as `X-App-Version` so the API's update-gate can
/// force old builds to upgrade. Keep in step with pubspec.yaml.
const kAppVersion = '0.1.0';

/// Thin Dio wrapper: attaches the JWT + app version on every request, and
/// surfaces the 426 update-gate (CLAUDE.md) via [onUpdateRequired].
class ApiClient {
  ApiClient({this.onUpdateRequired}) : _dio = Dio(BaseOptions(baseUrl: _apiBaseUrl)) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.headers['X-App-Version'] = kAppVersion;
          final token = Supabase.instance.client.auth.currentSession?.accessToken;
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 426) {
            onUpdateRequired?.call();
            return handler.next(error);
          }
          // Retry transient network failures with exponential backoff (300ms,
          // 600ms, 1.2s). Only connection/timeout errors — never a real HTTP
          // response (4xx/5xx). Sync ops carry op UUIDs, so a retried POST is
          // idempotent server-side.
          const retryable = {
            DioExceptionType.connectionError,
            DioExceptionType.connectionTimeout,
            DioExceptionType.receiveTimeout,
            DioExceptionType.sendTimeout,
          };
          final attempt = (error.requestOptions.extra['retry_attempt'] as int?) ?? 0;
          if (retryable.contains(error.type) && attempt < 3) {
            await Future<void>.delayed(Duration(milliseconds: 300 * (1 << attempt)));
            final opts = error.requestOptions..extra['retry_attempt'] = attempt + 1;
            try {
              return handler.resolve(await _dio.fetch<dynamic>(opts));
            } on DioException catch (e) {
              return handler.next(e);
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  /// Called when the server rejects this build as too old (HTTP 426).
  final void Function()? onUpdateRequired;

  final Dio _dio;

  /// Idempotent — safe to call on every sign-in, not just the first.
  Future<void> bootstrap() => _dio.post('/auth/bootstrap');

  Future<Map<String, dynamic>> getMe() async {
    final res = await _dio.get('/me');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateMe(Map<String, dynamic> patch) async {
    final res = await _dio.patch('/me', data: patch);
    return res.data as Map<String, dynamic>;
  }

  Future<void> deleteMe() => _dio.delete('/me');

  /// Reputation breakdown — `{total, books_added, authors_added, …}`.
  Future<Map<String, dynamic>> getScore() async {
    final res = await _dio.get('/me/score');
    return res.data as Map<String, dynamic>;
  }

  /// Live username availability check — `{username, available}`.
  Future<bool> usernameAvailable(String username) async {
    final res = await _dio.get('/me/username-available', queryParameters: {'username': username});
    return (res.data as Map<String, dynamic>)['available'] as bool? ?? false;
  }

  /// Find Kitabi users by username handle (lending) — each `{id, username,
  /// full_name?, avatar_url?}`.
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final res = await _dio.get('/users/search', queryParameters: {'q': query});
    return (res.data as List).cast<Map<String, dynamic>>();
  }

  /// Another reader's public profile — 404s when they've opted out.
  Future<Map<String, dynamic>> getPublicProfile(String userId) async {
    final res = await _dio.get('/users/$userId/profile');
    return res.data as Map<String, dynamic>;
  }

  /// The books on a reader's public shelf — 404s unless both their profile
  /// and library are public.
  Future<List<Map<String, dynamic>>> getPublicLibrary(String userId) async {
    final res = await _dio.get('/users/$userId/library');
    return (res.data as List).cast<Map<String, dynamic>>();
  }

  /// The "Works" tab on a reader's public profile — every catalog Work whose
  /// author is linked to them. Gated only on the profile itself being public,
  /// independent of their library visibility.
  Future<List<Map<String, dynamic>>> getPublicWorks(String userId) async {
    final res = await _dio.get('/users/$userId/works');
    return (res.data as List).cast<Map<String, dynamic>>();
  }

  // --- Push notifications (FCM device tokens) ---

  /// Register this install's FCM token for the signed-in user.
  Future<void> registerDevice(String token, String platform) =>
      _dio.post('/devices', data: {'token': token, 'platform': platform});

  /// Drop this token on sign-out.
  Future<void> unregisterDevice(String token) =>
      _dio.delete('/devices', data: {'token': token});

  // --- Lending connections (peer-to-peer consent layer) ---

  /// The connections screen in one call: `{incoming, outgoing, accepted}`, each
  /// a list of `{id, status, role, other:{id,username,full_name}, created_at}`.
  Future<Map<String, dynamic>> getConnections() async {
    final res = await _dio.get('/connections');
    return (res.data as Map).cast<String, dynamic>();
  }

  /// Ask to connect with a Kitabi user (or accept, if they already asked you).
  /// Idempotent. Returns `{status, connection_id?}`.
  Future<Map<String, dynamic>> requestConnection(String addresseeId) async {
    final res = await _dio.post('/connections', data: {'addressee_id': addresseeId});
    return (res.data as Map).cast<String, dynamic>();
  }

  /// Where the caller stands with one user: `{status, connection_id?}` — status
  /// is none/pending_out/pending_in/accepted/denied.
  Future<Map<String, dynamic>> connectionStatus(String userId) async {
    final res = await _dio.get('/connections/status/$userId');
    return (res.data as Map).cast<String, dynamic>();
  }

  Future<void> acceptConnection(String connectionId) =>
      _dio.post('/connections/$connectionId/accept');

  /// Deny an incoming request, cancel one you sent, or disconnect an accepted one.
  Future<void> declineConnection(String connectionId) =>
      _dio.post('/connections/$connectionId/decline');

  /// Block the other party — terminal; they can't re-send requests past it.
  Future<void> blockConnection(String connectionId) =>
      _dio.post('/connections/$connectionId/block');

  /// Undo a block (blocker only).
  Future<void> unblockConnection(String connectionId) =>
      _dio.post('/connections/$connectionId/unblock');

  /// Nudge a connected borrower to return a book (push). 403 if not connected.
  /// The cover URL rides along as the notification's rich image.
  Future<void> remindToReturn(String userId, String bookTitle, {String? bookCoverUrl}) =>
      _dio.post('/connections/remind', data: {
        'user_id': userId,
        'book_title': bookTitle,
        'book_cover_url': ?bookCoverUrl,
      });

  /// Catalog-only search (title / author / exact ISBN) — Phase 2 scope.
  /// The "in your library" merge lands once the personal library (Phase 3)
  /// and its Drift cache exist; for now every result is a catalog work.
  Future<List<Map<String, dynamic>>> searchCatalog(String query) async {
    final res = await _dio.get('/catalog/search', queryParameters: {'q': query});
    return (res.data as List).cast<Map<String, dynamic>>();
  }

  /// Global search (S4) — books, authors, and publishers in one round-trip.
  /// Returns `{works, authors, publishers}`. The personal-library section is
  /// searched separately on-device (Drift), not here.
  Future<Map<String, dynamic>> searchAll(String query) async {
    final res = await _dio.get('/catalog/search/all', queryParameters: {'q': query});
    return res.data as Map<String, dynamic>;
  }

  /// Discover/browse — every catalog book / author / publisher, alphabetical
  /// and paged (offset pagination). Layer 1 is server-authoritative, so these
  /// read straight from the catalog API.
  Future<List<Map<String, dynamic>>> browseWorks({
    int limit = 40,
    int offset = 0,
    String? language,
    String? form,
    String? genre,
    String sort = 'title',
  }) async {
    final res = await _dio.get(
      '/catalog/browse/works',
      queryParameters: {
        'limit': limit,
        'offset': offset,
        'sort': sort,
        'language': ?language,
        'form': ?form,
        'genre': ?genre,
      },
    );
    return (res.data as List).cast<Map<String, dynamic>>();
  }

  /// Distinct catalog languages — powers the browse language filter.
  Future<List<String>> browseLanguages() async {
    final res = await _dio.get('/catalog/browse/languages');
    return (res.data as List).cast<String>();
  }

  /// Literary forms present in the catalog — the browse Type filter offers
  /// only what it can actually return.
  Future<List<String>> browseForms() async {
    final res = await _dio.get('/catalog/browse/forms');
    return (res.data as List).cast<String>();
  }

  /// Genres carried by at least one work, commonest first, each with its
  /// `work_count` — `[{name, work_count}]`. The browse filter wants only the
  /// names; the add form's genre picker shows the count, which is what steers
  /// a reader onto the established spelling instead of a near-duplicate.
  ///
  /// Parsed element by element rather than with `.cast()` on purpose. `.cast()`
  /// is lazy: a wrong element type sails through here and only throws when the
  /// list is later iterated — which lands the error inside a widget `build()`,
  /// red-screening the add form far from the cause (caught on-device,
  /// 21 Jul 2026). An API older than this build still returns bare name
  /// strings, and a deploy-order skew shouldn't cost the reader the form, so
  /// that shape is tolerated with a null count.
  Future<List<Map<String, dynamic>>> browseGenres() async {
    final res = await _dio.get('/catalog/browse/genres');
    return parseGenreRows(res.data as List);
  }

  /// The genre-row parser, split out so the shape tolerance above is testable
  /// without standing up a Dio adapter.
  @visibleForTesting
  static List<Map<String, dynamic>> parseGenreRows(List<dynamic> rows) => [
        for (final row in rows)
          if (row is Map) Map<String, dynamic>.from(row)
          else if (row is String) {'name': row, 'work_count': null},
      ];

  Future<List<Map<String, dynamic>>> browseAuthors({
    int limit = 40,
    int offset = 0,
    String sort = 'name',
  }) async {
    final res = await _dio.get(
      '/catalog/browse/authors',
      queryParameters: {'limit': limit, 'offset': offset, 'sort': sort},
    );
    return (res.data as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> browsePublishers({
    int limit = 40,
    int offset = 0,
    String sort = 'name',
  }) async {
    final res = await _dio.get(
      '/catalog/browse/publishers',
      queryParameters: {'limit': limit, 'offset': offset, 'sort': sort},
    );
    return (res.data as List).cast<Map<String, dynamic>>();
  }

  /// ISBN scan flow (S7) — local match first, else OpenLibrary, cached
  /// server-side either way.
  Future<Map<String, dynamic>> lookupIsbn(String isbn) async {
    final res = await _dio.get('/catalog/isbn/$isbn');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createWork(Map<String, dynamic> payload) async {
    final res = await _dio.post('/catalog/works', data: payload);
    return res.data as Map<String, dynamic>;
  }

  /// Typo-tolerant duplicate check for the add-book form: the closest catalog
  /// matches for the title being typed (server-side trigram similarity), best
  /// first. Empty when nothing is close.
  Future<List<Map<String, dynamic>>> similarWorks(String title) async {
    final res = await _dio.get('/catalog/works/similar', queryParameters: {'title': title});
    return (res.data as List).cast<Map<String, dynamic>>();
  }

  /// Cover-photo extraction (S7b rescue path) — reads title/authors/publisher/
  /// blurb off the already-uploaded cover photo URL(s) so the add-book form can
  /// prefill itself for a book no catalog knows. 503 (`extraction_disabled`)
  /// when the server has no LLM key; the form shows a quiet "unavailable".
  Future<Map<String, dynamic>> extractFromCovers({String? frontUrl, String? backUrl}) async {
    final res = await _dio.post('/catalog/cover-extract', data: {
      'front_url': ?frontUrl,
      'back_url': ?backUrl,
    });
    return res.data as Map<String, dynamic>;
  }

  /// The Work containing an edition — used to hydrate a borrowed book the reader
  /// never added themselves (their loan record only has the edition id).
  Future<Map<String, dynamic>> getWorkByEdition(String editionId) async {
    final res = await _dio.get('/catalog/editions/$editionId');
    return (res.data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getWork(String workId) async {
    final res = await _dio.get('/catalog/works/$workId');
    return res.data as Map<String, dynamic>;
  }

  /// Every public review on a book (newest first — sorting for display
  /// happens client-side over this list) plus the community rating picture
  /// (`rating_average`, `rating_count`, `rating_distribution`) computed from
  /// every rating on the work, not just reviewed ones. Reviewer identity is
  /// resolved server-side on every fetch, so re-opening the book page always
  /// reflects the reviewer's current profile visibility.
  Future<Map<String, dynamic>> getWorkReviews(String workId) async {
    final res = await _dio.get('/catalog/works/$workId/reviews');
    return res.data as Map<String, dynamic>;
  }

  /// Wiki-style edit — the response wrapper says whether the change applied
  /// live (`applied: true`, contributor or unowned work) or was queued as a
  /// pending revision for the contributor to approve.
  Future<Map<String, dynamic>> updateWork(String workId, Map<String, dynamic> patch) async {
    final res = await _dio.patch('/catalog/works/$workId', data: patch);
    return res.data as Map<String, dynamic>;
  }

  /// The approval inbox — pending edits to books this reader contributed.
  Future<List<Map<String, dynamic>>> pendingRevisions() async {
    final res = await _dio.get('/catalog/revisions/pending');
    return (res.data as List).cast<Map<String, dynamic>>();
  }

  Future<void> approveRevision(String revisionId) async {
    await _dio.post('/catalog/revisions/$revisionId/approve');
  }

  Future<void> rejectRevision(String revisionId) async {
    await _dio.post('/catalog/revisions/$revisionId/reject');
  }

  /// Typeahead for the add/edit form's author field (dropdown-cum-add-new).
  Future<List<Map<String, dynamic>>> searchAuthors(String query) async {
    final res = await _dio.get('/catalog/authors', queryParameters: {'q': query});
    return (res.data as List).cast<Map<String, dynamic>>();
  }

  /// Typeahead for the add/edit form's publisher field.
  Future<List<Map<String, dynamic>>> searchPublishers(String query) async {
    final res = await _dio.get('/catalog/publishers', queryParameters: {'q': query});
    return (res.data as List).cast<Map<String, dynamic>>();
  }

  /// Author picker "add new" — create a catalog author with details
  /// (name, image, primary language, bio). Idempotent on name server-side.
  Future<Map<String, dynamic>> createAuthor(Map<String, dynamic> payload) async {
    final res = await _dio.post('/catalog/authors', data: payload);
    return res.data as Map<String, dynamic>;
  }

  /// Publisher picker "add new" — create a catalog publisher with details.
  Future<Map<String, dynamic>> createPublisher(Map<String, dynamic> payload) async {
    final res = await _dio.post('/catalog/publishers', data: payload);
    return res.data as Map<String, dynamic>;
  }

  /// Update an edition's fields (e.g. a user-uploaded cover URL) — S7b.
  Future<Map<String, dynamic>> updateEdition(String editionId, Map<String, dynamic> patch) async {
    final res = await _dio.patch('/catalog/editions/$editionId', data: patch);
    return res.data as Map<String, dynamic>;
  }

  /// Add another edition (printing/ISBN) to an existing Work — returns the new
  /// edition.
  Future<Map<String, dynamic>> createEdition(
    String workId,
    Map<String, dynamic> payload,
  ) async {
    final res = await _dio.post('/catalog/works/$workId/editions', data: payload);
    return res.data as Map<String, dynamic>;
  }

  /// Link two Works as translations of one another (shared translation group).
  /// [relation] records the direction: 'original' — the other work is
  /// [workId]'s original; 'translation' — the other work is a translation of
  /// [workId]; 'sibling' — direction unknown, group-link only.
  Future<void> linkTranslation(
    String workId,
    String otherWorkId, {
    String relation = 'sibling',
  }) async {
    await _dio.post(
      '/catalog/works/$workId/link-translation',
      data: {'other_work_id': otherWorkId, 'relation': relation},
    );
  }

  Future<Map<String, dynamic>> getAuthorWorks(String authorId) async {
    final res = await _dio.get('/catalog/authors/$authorId');
    return res.data as Map<String, dynamic>;
  }

  /// "This is me" — self-link an existing, unclaimed Author row to the
  /// signed-in reader. First to claim wins; throws (409) if someone already
  /// linked it.
  Future<Map<String, dynamic>> linkAuthor(String authorId) async {
    final res = await _dio.post('/catalog/authors/$authorId/link');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getPublisherWorks(String publisherId) async {
    final res = await _dio.get('/catalog/publishers/$publisherId');
    return res.data as Map<String, dynamic>;
  }

  /// Reasoned recommendations (S11). Returns `{enabled, picks}`; `enabled` is
  /// false when the server has no LLM key configured (feature dormant).
  Future<Map<String, dynamic>> getRecommendations() async {
    final res = await _dio.get('/recommendations');
    return res.data as Map<String, dynamic>;
  }

  /// Import (S2) — parse a Goodreads/generic CSV and match rows to the catalog.
  /// Returns `{format, total, matched, rows}`.
  Future<Map<String, dynamic>> importPreview(String csv) async {
    final res = await _dio.post('/import/preview', data: {'csv': csv});
    return res.data as Map<String, dynamic>;
  }

  /// Sync engine wire calls — see data/sync/sync_engine.dart.
  Future<List<Map<String, dynamic>>> syncPush(List<Map<String, dynamic>> ops) async {
    final res = await _dio.post('/sync/push', data: {'ops': ops});
    return ((res.data as Map<String, dynamic>)['results'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> syncPull({required int cursor, int limit = 500}) async {
    final res = await _dio.get('/sync/pull', queryParameters: {'cursor': cursor, 'limit': limit});
    return res.data as Map<String, dynamic>;
  }
}

/// Set to true when the API returns 426 (this build is too old) — the router
/// then forces the blocking update screen.
final updateRequiredProvider = StateProvider<bool>((ref) => false);

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    onUpdateRequired: () => ref.read(updateRequiredProvider.notifier).state = true,
  ),
);
