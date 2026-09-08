import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/sync/sync_providers.dart';
import 'package:kitabi/features/profile/providers/profile_providers.dart';
import 'package:kitabi/features/share/presentation/period_card_data.dart';
import 'package:kitabi/features/share/presentation/share_period_sheet.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// The recap link in the share sheet (8 Sep 2026).
///
/// The link is *derived* — handle plus window — so there is no round trip and
/// nothing to mint, but that also means it is guessable, and the two things
/// standing between a reader and an unwanted public page are a handle they
/// chose and a switch they turned on. Both halves are asserted here, including
/// the states where no link may be printed at all.
Widget _host(ProviderContainer container, {required String recapKey}) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSharePeriodSheet(
                context,
                dataBuilder: (_) => const PeriodCardData(
                  heroValue: '4',
                  heroLabel: 'books · september',
                  subLine: '307 pages',
                  closingLine: 'A month with a book in hand.',
                ),
                initialCaption: 'A month with a book in hand.',
                recapKey: recapKey,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

ProviderContainer _container(Map<String, dynamic> me) {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  return ProviderContainer(overrides: [
    appDatabaseProvider.overrideWithValue(db),
    apiClientProvider.overrideWithValue(ApiClient()),
    meProvider.overrideWith((ref) async => me),
  ]);
}

void main() {
  late final void Function(FlutterErrorDetails, String) reportOriginal;

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    reportOriginal = reportTestException;
    reportTestException = (details, desc) {
      if (details.exception.toString().contains('GoogleFonts')) return;
      reportOriginal(details, desc);
    };
  });
  tearDownAll(() => reportTestException = reportOriginal);

  Future<void> settle(WidgetTester tester, [int frames = 10]) async {
    for (var i = 0; i < frames; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('a published reader gets the link, and it rides the caption', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = _container({'username': 'shamshi', 'recaps_visible': true});
    addTearDown(container.dispose);

    await tester.pumpWidget(_host(container, recapKey: '2026-09'));
    await tester.tap(find.text('open'));
    await settle(tester);

    // Shown without its scheme — nobody types "https://".
    expect(find.text('kitabi.in/reader/shamshi/recap/2026-09'), findsWidgets);

    // And in the caption, which is what actually reaches the recipient now
    // that the text ships alongside the image.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, contains('https://kitabi.in/reader/shamshi/recap/2026-09'));
    expect(field.controller!.text, startsWith('A month with a book in hand.'));
  });

  testWidgets('a reader who has not published recaps is offered the switch, not a link',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = _container({'username': 'shamshi', 'recaps_visible': false});
    addTearDown(container.dispose);

    await tester.pumpWidget(_host(container, recapKey: '2026-09'));
    await tester.tap(find.text('open'));
    await settle(tester);

    expect(find.textContaining('kitabi.in/reader/'), findsNothing);
    expect(find.text('Add a link others can open'), findsOneWidget);
    // What it means, said before it is done rather than after.
    expect(find.textContaining('Anyone with this link can see'), findsOneWidget);
  });

  testWidgets('a reader with no handle is sent to claim one', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = _container({'username': null, 'recaps_visible': true});
    addTearDown(container.dispose);

    await tester.pumpWidget(_host(container, recapKey: '2026-09'));
    await tester.tap(find.text('open'));
    await settle(tester);

    expect(find.textContaining('kitabi.in/reader/'), findsNothing);
    expect(find.text('Pick a username to share a link'), findsOneWidget);
  });
}
