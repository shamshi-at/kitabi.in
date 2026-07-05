import 'package:dio/dio.dart';
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
        onError: (error, handler) {
          if (error.response?.statusCode == 426) onUpdateRequired?.call();
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

  /// Catalog-only search (title / author / exact ISBN) — Phase 2 scope.
  /// The "in your library" merge lands once the personal library (Phase 3)
  /// and its Drift cache exist; for now every result is a catalog work.
  Future<List<Map<String, dynamic>>> searchCatalog(String query) async {
    final res = await _dio.get('/catalog/search', queryParameters: {'q': query});
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

  Future<Map<String, dynamic>> getWork(String workId) async {
    final res = await _dio.get('/catalog/works/$workId');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateWork(String workId, Map<String, dynamic> patch) async {
    final res = await _dio.patch('/catalog/works/$workId', data: patch);
    return res.data as Map<String, dynamic>;
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

  /// Update an edition's fields (e.g. a user-uploaded cover URL) — S7b.
  Future<Map<String, dynamic>> updateEdition(String editionId, Map<String, dynamic> patch) async {
    final res = await _dio.patch('/catalog/editions/$editionId', data: patch);
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getAuthorWorks(String authorId) async {
    final res = await _dio.get('/catalog/authors/$authorId');
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
