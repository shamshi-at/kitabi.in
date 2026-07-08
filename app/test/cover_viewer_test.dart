import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kitabi/features/library/presentation/cover_viewer.dart';
import 'package:kitabi/l10n/app_localizations.dart';

Widget _host() {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showCoverViewer(
              context,
              pages: const [
                (url: 'https://covers.example/front.jpg', label: 'Front cover'),
                (url: 'https://covers.example/back.jpg', label: 'Back cover'),
              ],
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('viewer opens on front, swipes to back, and closes', (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Front page first — caption is the uppercased label.
    expect(find.text('FRONT COVER'), findsOneWidget);
    expect(find.byType(PageView), findsOneWidget);

    // Swipe to the back cover.
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text('BACK COVER'), findsOneWidget);

    // Close returns to the host screen.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(PageView), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('single-page viewer shows no page dots', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showCoverViewer(
                context,
                pages: const [(url: 'https://covers.example/front.jpg', label: 'Front cover')],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('FRONT COVER'), findsOneWidget);
    expect(find.byType(AnimatedContainer), findsNothing); // the dots
  });
}
