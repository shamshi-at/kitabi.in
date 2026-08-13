import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kitabi/core/auth/auth_providers.dart';

/// The gate that decides whether a signed-in reader may leave the splash.
///
/// A failed bootstrap used to be treated as "resolved, carry on": the reader
/// landed on the language picker with no profile row, its first save was a
/// PATCH /me that could only 404, and nothing ever called bootstrap again —
/// a one-way door into an error, restart or not (owner report, 13 Aug 2026).
///
/// These pin the rule the router now follows, in isolation from the real
/// router's auth/onboarding gates: **never walk past a bootstrap that has never
/// succeeded — but never yank an established session back either.**
bool holdsOnSplash(AsyncValue<void> bootstrap) =>
    bootstrap.isLoading || (bootstrap.hasError && !bootstrap.hasValue);

void main() {
  group('the splash gate', () {
    test('holds while the bootstrap is still resolving', () {
      expect(holdsOnSplash(const AsyncLoading<void>()), isTrue);
    });

    test('holds when the bootstrap failed and never succeeded', () {
      expect(
        holdsOnSplash(AsyncError<void>(Exception('network'), StackTrace.empty)),
        isTrue,
        reason: 'walking past this is what produced an inescapable 404',
      );
    });

    test('lets a successful bootstrap through', () {
      expect(holdsOnSplash(const AsyncData<void>(null)), isFalse);
    });

    test('does NOT yank an established session back to the splash', () {
      // A background re-run that errors *after* a good bootstrap — a token
      // refresh in a tunnel. The reader keeps using the app.
      final refreshFailed = AsyncError<void>(Exception('tunnel'), StackTrace.empty)
          .copyWithPrevious(const AsyncData<void>(null));
      expect(holdsOnSplash(refreshFailed), isFalse);
    });
  });

  testWidgets('a widget can render a retry affordance from the failed state',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bootstrapProvider.overrideWith((ref) => throw Exception('no network')),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              final bootstrap = ref.watch(bootstrapProvider);
              return Scaffold(
                body: holdsOnSplash(bootstrap) && bootstrap.hasError
                    ? OutlinedButton(onPressed: () {}, child: const Text('Retry'))
                    : const Text('Home'),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
  });
}
