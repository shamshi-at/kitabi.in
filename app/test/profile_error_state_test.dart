import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/features/profile/presentation/profile_screen.dart';
import 'package:kitabi/features/profile/providers/profile_providers.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// Profile & settings used to render `Text('$err')`, so a failed /me put a raw
/// "DioException [bad response]: ... 401" on screen. It must show the same
/// friendly ErrorRetry the rest of the app uses.
void main() {
  final unauthorized = DioException(
    requestOptions: RequestOptions(path: '/me'),
    response: Response(requestOptions: RequestOptions(path: '/me'), statusCode: 401),
    type: DioExceptionType.badResponse,
  );

  Widget wrap(List<Override> overrides) => ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ProfileScreen(),
        ),
      );

  testWidgets('a failed /me shows a friendly retry, not the raw exception', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(wrap([
      meProvider.overrideWith((ref) async {
        attempts++;
        throw unauthorized;
      }),
    ]));
    await tester.pump();

    expect(find.textContaining('DioException'), findsNothing);
    expect(find.textContaining('401'), findsNothing);
    expect(find.text('Something went wrong.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    // Retry re-runs the fetch rather than being decorative.
    expect(attempts, 1);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(attempts, 2);
  });

  testWidgets('a failed score card degrades on its own, leaving the profile usable',
      (tester) async {
    await tester.pumpWidget(wrap([
      meProvider.overrideWith((ref) async => {
            'id': 'u1',
            'full_name': 'Reader',
            'preferred_languages': ['English'],
          }),
      scoreProvider.overrideWith((ref) async => throw unauthorized),
    ]));
    // Two frames: the card is only built once /me resolves, so its own future
    // settles a frame after the body appears.
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('DioException'), findsNothing);
    // The rest of the screen still rendered — the reputation card failing does
    // not take the profile down with it.
    expect(find.text('Reader'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    // Unmount so the profile body's pending timers are disposed cleanly
    // (same teardown as splash_test).
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
