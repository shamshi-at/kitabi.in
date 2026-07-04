import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// API base URL — passed via --dart-define; empty is fine for now (every call
// simply fails until the API is deployed and this is set).
const _apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8000');

/// Thin Dio wrapper. JWT attach is the only interceptor for now; the 426
/// update-gate and retry/backoff interceptors are planned (CLAUDE.md) but
/// land with the sync engine in a later phase — no endpoint needs them yet.
class ApiClient {
  ApiClient() : _dio = Dio(BaseOptions(baseUrl: _apiBaseUrl)) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = Supabase.instance.client.auth.currentSession?.accessToken;
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

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
}

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());
