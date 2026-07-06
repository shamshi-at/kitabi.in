import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/features/splash/presentation/splash_screen.dart';
import 'package:kitabi/l10n/app_localizations.dart';

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
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
}
