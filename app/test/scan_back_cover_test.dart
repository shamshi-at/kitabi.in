import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/features/catalog/presentation/add_edit_book_screen.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// The reworked "Scan back cover" flow (owner request, 2 Sep 2026).
///
/// The old flow always opened a capture and always clobbered the back-cover
/// slot with whatever came out of it. The new rules these pin:
///
///  * a form already holding an *uploaded* back cover asks whether to read
///    that photo or point the camera at the book — re-photographing what the
///    form already has is the camera as a punishment;
///  * "read the uploaded back cover" extracts from the slot's own URL, opens
///    no camera, and never touches the slot;
///  * with nothing re-readable (no back cover, or an external one the
///    extractor can't accept) the flow goes straight to the camera — no sheet.
///
/// A fresh capture never lands in the slot uninvited: whatever the slot holds,
/// a dialog asks first (replace the current photo, or adopt it when the slot
/// is empty). That leg (camera → upload → question) rides the platform camera
/// and Supabase Storage, so it stays with the on-device pass — these tests
/// prove the *branching*, which is where the old behaviour lived.
const _ownBack =
    'https://ref.supabase.co/storage/v1/object/public/covers/covers/back-1.jpg';
const _externalBack = 'https://covers.openlibrary.org/b/id/12345-L.jpg';
const _blurb = 'Snowbound on the Orient Express, a passenger lies dead.';

class _Fake extends ApiClient {
  int extractCalls = 0;
  String? extractedFront;
  String? extractedBack;

  @override
  Future<Map<String, dynamic>> extractFromCovers({String? frontUrl, String? backUrl}) async {
    extractCalls++;
    extractedFront = frontUrl;
    extractedBack = backUrl;
    return {'description': _blurb};
  }
}

Widget _app(_Fake fake, {Map<String, dynamic>? seed}) => ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(fake)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AddEditBookScreen(seed: seed),
      ),
    );

Future<void> _tapScan(WidgetTester tester) async {
  // The Description field (and its scan link) lives inside the collapsed
  // "More details" section — open it the way a reader does, if it isn't
  // already (a seed with enough data auto-expands it).
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
  // Bounded pumps, not pumpAndSettle: on the straight-to-camera branch the
  // test environment's picker never answers, so the slot spinner animates
  // indefinitely and pumpAndSettle would time out. Two frames plus the sheet's
  // slide-in is all the passing branch needs.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() {
    // Tall enough that the description field (and its scan link) lays out.
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('an uploaded back cover offers "read it" before the camera', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _Fake();
    await tester.pumpWidget(_app(fake, seed: {'back_cover_url': _ownBack}));
    await tester.pumpAndSettle();

    await _tapScan(tester);

    expect(find.text('Read the uploaded back cover'), findsOneWidget);
    expect(find.text('Capture it with the camera'), findsOneWidget);
    expect(fake.extractCalls, 0, reason: 'nothing runs until the reader chooses');
  });

  testWidgets('"read the uploaded back cover" extracts from the slot and asks nothing',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _Fake();
    await tester.pumpWidget(_app(fake, seed: {'back_cover_url': _ownBack}));
    await tester.pumpAndSettle();

    await _tapScan(tester);
    await tester.tap(find.text('Read the uploaded back cover'));
    await tester.pumpAndSettle();

    expect(fake.extractCalls, 1);
    expect(fake.extractedBack, _ownBack, reason: 'reads the photo the form already holds');
    expect(find.text(_blurb), findsOneWidget, reason: 'the blurb lands in Description');
    // No capture happened, so there is nothing to offer as a replacement.
    expect(find.text('Make this the back cover?'), findsNothing);
  });

  testWidgets('no back cover → no sheet, straight to the camera', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _Fake();
    await tester.pumpWidget(_app(fake));
    await tester.pumpAndSettle();

    // In a test the camera channel is a MissingPluginException, which the
    // flow reports as a quiet upload error — the assertion here is only that
    // no choice sheet stood in the way.
    await _tapScan(tester);

    expect(find.text('Read the uploaded back cover'), findsNothing);
    expect(fake.extractCalls, 0);
  });

  testWidgets('an external back cover cannot be re-read — no sheet either', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = _Fake();
    await tester.pumpWidget(_app(fake, seed: {'back_cover_url': _externalBack}));
    await tester.pumpAndSettle();

    await _tapScan(tester);

    // The extractor only accepts covers-bucket URLs, so "read the uploaded
    // back cover" would be a promise the form cannot keep.
    expect(find.text('Read the uploaded back cover'), findsNothing);
    expect(fake.extractCalls, 0);
  });
}
