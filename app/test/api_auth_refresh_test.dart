import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/data/api/api_client.dart';

/// The 401 path in [ApiClient]: refresh once, replay, and sign out when the
/// refresh token is dead too. Before this, a 401 surfaced as a raw
/// DioException on whatever screen made the call (Profile & settings).
///
/// The seam is a fake [HttpClientAdapter], not an interceptor: a request
/// interceptor that calls `handler.reject` short-circuits straight to the
/// caller without running the auth interceptor's onError, so faking at that
/// layer would test nothing. Swapping the adapter drives the real chain.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.statuses);

  /// Status code to serve per call; the last entry repeats.
  final List<int> statuses;

  /// Authorization header seen on each request, in order.
  final List<String?> seen = [];
  int _call = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options.headers['Authorization'] as String?);
    final status = statuses[_call.clamp(0, statuses.length - 1)];
    _call++;
    return ResponseBody.fromString(
      '{"ok": true}',
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  ({_FakeAdapter transport, ApiClient client}) build({
    required List<int> statuses,
    required SessionRefresher refreshSession,
    TokenReader? readToken,
    Future<void> Function()? onAuthLost,
  }) {
    final client = ApiClient(
      readToken: readToken,
      refreshSession: refreshSession,
      onAuthLost: onAuthLost,
    );
    final transport = _FakeAdapter(statuses);
    client.dio.httpClientAdapter = transport;
    return (transport: transport, client: client);
  }

  test('401 refreshes the token once and replays the request with the new one', () async {
    var token = 'stale';
    var refreshes = 0;
    final h = build(
      statuses: [401, 200],
      readToken: () => token,
      refreshSession: () async {
        refreshes++;
        return token = 'fresh';
      },
    );

    await expectLater(h.client.getMe(), completion({'ok': true}));
    expect(refreshes, 1);
    // The replay must carry the *refreshed* token, not the stale one — the
    // header is rebuilt by onRequest, which re-reads per request.
    expect(h.transport.seen, ['Bearer stale', 'Bearer fresh']);
  });

  test('a failed refresh signs out and still surfaces the 401', () async {
    var signedOut = false;
    final h = build(
      statuses: [401],
      readToken: () => 'stale',
      refreshSession: () async => throw StateError('refresh token expired'),
      onAuthLost: () async => signedOut = true,
    );

    await expectLater(
      h.client.getMe(),
      throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'status', 401)),
    );
    expect(signedOut, isTrue);
    expect(h.transport.seen, ['Bearer stale'], reason: 'must not replay without a token');
  });

  test('a refresh that returns no session signs out', () async {
    var signedOut = false;
    final h = build(
      statuses: [401],
      readToken: () => 'stale',
      refreshSession: () async => null,
      onAuthLost: () async => signedOut = true,
    );

    await expectLater(h.client.getMe(), throwsA(isA<DioException>()));
    expect(signedOut, isTrue);
  });

  test('a 401 on the replay is not retried again — no infinite loop', () async {
    var refreshes = 0;
    final h = build(
      statuses: [401, 401],
      readToken: () => 'stale',
      refreshSession: () async {
        refreshes++;
        return 'fresh';
      },
      onAuthLost: () async {},
    );

    await expectLater(h.client.getMe(), throwsA(isA<DioException>()));
    expect(refreshes, 1, reason: 'one refresh per request, however many 401s come back');
    expect(h.transport.seen.length, 2);
  });

  test('concurrent 401s coalesce into a single refresh', () async {
    var token = 'stale';
    var refreshes = 0;
    final h = build(
      statuses: [401, 401, 401, 200, 200, 200],
      readToken: () => token,
      refreshSession: () async {
        refreshes++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return token = 'fresh';
      },
    );

    // Three requests in flight, all rejected — a sync drain's shape.
    await Future.wait([h.client.getMe(), h.client.getMe(), h.client.getMe()]);
    expect(refreshes, 1, reason: 'three 401s must not fire three refreshes');
  });

  test('a 401 with no session at all does not refresh or sign out', () async {
    var refreshes = 0;
    var signedOut = false;
    final h = build(
      statuses: [401],
      readToken: () => null,
      refreshSession: () async {
        refreshes++;
        return 'fresh';
      },
      onAuthLost: () async => signedOut = true,
    );

    await expectLater(h.client.getMe(), throwsA(isA<DioException>()));
    expect(refreshes, 0);
    expect(signedOut, isFalse);
    expect(h.transport.seen, [null]);
  });

  test('non-401 errors are untouched by the auth path', () async {
    var refreshes = 0;
    final h = build(
      statuses: [500],
      readToken: () => 'good',
      refreshSession: () async {
        refreshes++;
        return 'fresh';
      },
    );

    await expectLater(h.client.getMe(), throwsA(isA<DioException>()));
    expect(refreshes, 0);
  });
}
