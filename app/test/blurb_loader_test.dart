import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/features/catalog/presentation/add_edit_book_screen.dart';
import 'package:kitabi/features/catalog/presentation/form_widgets.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// The Description field shows a loader while the blurb half of a cover read
/// is still in flight (owner request, 6 Sep 2026).
///
/// The read leaves as two calls: the identity fields land in a second or two
/// and the form drops its full-screen overlay right then, while the blurb —
/// a paragraph, a thousand tokens in Malayalam — arrives up to ten seconds
/// later. In between, an empty Description read as "found nothing". The
/// fake here holds the blurb call open on a completer so the test can look at
/// the field during exactly that gap.
const _ownBack =
    'https://ref.supabase.co/storage/v1/object/public/covers/covers/back-1.jpg';
const _blurb = 'Snowbound on the Orient Express, a passenger lies dead.';

class _Fake extends ApiClient {
  final blurb = Completer<Map<String, dynamic>>();

  @override
  Future<Map<String, dynamic>> extractFromCovers({
    String? frontUrl,
    String? backUrl,
    String? part,
  }) async {
    if (part == 'description') return blurb.future;
    return const {'title': 'Murder on the Orient Express'};
  }
}

Widget _app(_Fake fake) => ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(fake)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AddEditBookScreen(seed: const {'back_cover_url': _ownBack}),
      ),
    );

Future<void> _startRead(WidgetTester tester) async {
  if (find.text('Scan back cover').evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      find.text('More details'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('More details'));
    await tester.pumpAndSettle();
  }
  await tester.scrollUntilVisible(
    find.text('Scan back cover'),
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Scan back cover'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text('Read the uploaded back cover'));
  // Bounded pumps: the blurb spinner animates for as long as the call is
  // open, so pumpAndSettle would never return.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('the empty Description shows a loader until the blurb lands', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _Fake();
    await tester.pumpWidget(_app(fake));
    await tester.pumpAndSettle();

    await _startRead(tester);

    // Identity is in, the overlay is gone — and the blurb is still coming.
    expect(find.byType(FieldLoadingNotice), findsOneWidget);
    expect(find.text('Reading the blurb from your cover…'), findsOneWidget);

    fake.blurb.complete({'description': _blurb});
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(FieldLoadingNotice), findsNothing);
    expect(find.text(_blurb), findsOneWidget);
  });

  testWidgets('an empty blurb answer clears the loader too', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _Fake();
    await tester.pumpWidget(_app(fake));
    await tester.pumpAndSettle();

    await _startRead(tester);
    expect(find.byType(FieldLoadingNotice), findsOneWidget);

    fake.blurb.complete(const {});
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(FieldLoadingNotice), findsNothing);
  });
}
