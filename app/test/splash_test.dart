import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/core/auth/auth_providers.dart';
import 'package:kitabi/features/splash/presentation/splash_screen.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// The splash watches the bootstrap so it can offer a retry when setup fails
/// (13 Aug 2026), so it needs a scope. `AsyncData` = the ordinary path.
Widget _wrap(Widget child, {Object? bootstrapError}) => ProviderScope(
      overrides: [
        bootstrapProvider.overrideWith((ref) {
          if (bootstrapError != null) throw bootstrapError;
        }),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );

void main() {
  testWidgets('splash shows the brand name, tagline and loading status', (tester) async {
    await tester.pumpWidget(_wrap(const SplashScreen()));
    // Let the staggered intro run to completion.
    await tester.pump(const Duration(milliseconds: 1700));

    expect(find.text('Kitabi'), findsOneWidget);
    expect(find.text('Beyond the Bookshelf'), findsOneWidget);
    expect(find.text('Opening your reading room…'), findsOneWidget);

    // Tear down so the repeating loader's ticker is disposed cleanly.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failed setup says so, and offers a way forward', (tester) async {
    // The router holds a signed-in reader here until the profile bootstrap
    // succeeds. Before 13 Aug 2026 a failure walked them into the language
    // picker instead, whose first save could only 404 — so the one thing this
    // screen must never do is spin silently.
    await tester.pumpWidget(_wrap(const SplashScreen(), bootstrapError: Exception('no network')));
    await tester.pump(const Duration(milliseconds: 1700));

    expect(find.text("Couldn't finish setting up your account."), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Opening your reading room…'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });
}
