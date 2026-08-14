import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/features/insights/providers/insights_providers.dart';
import 'package:kitabi/features/insights/reading_pace.dart';
import 'package:kitabi/features/library/widgets/time_to_finish.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// 40 pp/h measured over 12 sittings, ~5h20m a week, ~1h12m per sitting.
const _measured = ReadingPace(
  pagesPerHour: 40,
  sampleSessions: 12,
  byLanguage: {},
  weeklySeconds: 19200,
  medianSittingSeconds: 4320,
);

LibraryEntry _entry({String status = 'pending', int? currentPage}) {
  final stamp = DateTime(2026, 7, 1);
  return LibraryEntry(
    id: 'le1',
    userId: 'u1',
    createdAt: stamp,
    updatedAt: stamp,
    deletedAt: null,
    syncStatus: 'synced',
    lastSyncedAt: null,
    serverSeq: null,
    editionId: 'ed1',
    status: status,
    ownership: 'owned',
    startDate: null,
    finishDate: null,
    currentPage: currentPage,
    isFavorite: false,
    notes: null,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required int? pageCount,
  LibraryEntry? entry,
  ReadingPace pace = _measured,
  ({double pagesPerHour, int sessions})? bookPace,
  TimeToFinishVariant variant = TimeToFinishVariant.card,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        readingPaceProvider.overrideWith((ref) => pace),
        bookPaceProvider.overrideWith((ref, id) => bookPace),
        readingSessionsStreamProvider
            .overrideWith((ref) => Stream.value(const <ReadingSession>[])),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: TimeToFinish(
              pageCount: pageCount,
              entry: entry,
              variant: variant,
              onAddPageCount: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a book not started shows the whole book, in three units', (tester) async {
    await _pump(tester, pageCount: 400, entry: _entry());

    expect(find.text('10h 0m'), findsOneWidget); // 400 pages at 40 pp/h
    expect(find.textContaining('400 pages'), findsOneWidget);
    expect(find.text('≈ 9'), findsOneWidget); // sittings
    expect(find.textContaining('≈ 2 weeks'), findsOneWidget);
    expect(find.textContaining('from 12 sittings'), findsOneWidget);
  });

  testWidgets('a book in progress counts only what is left', (tester) async {
    await _pump(tester, pageCount: 400, entry: _entry(status: 'reading', currentPage: 300));

    expect(find.text('2h 30m'), findsOneWidget); // 100 pages left
    expect(find.textContaining('100 pages'), findsOneWidget);
    expect(find.textContaining("you'd finish around"), findsOneWidget);
  });

  testWidgets(
      "the book's own pace quotes the book's own sitting count, never the global one",
      (tester) async {
    // Regression (found on-device, 26 Jul 2026): the footnote read "over 12
    // sittings" — the reader's whole sample — in a sentence that is explicitly
    // about this book. Plausible enough to ship, and simply false.
    await _pump(
      tester,
      pageCount: 400,
      entry: _entry(status: 'reading', currentPage: 100),
      bookPace: (pagesPerHour: 20, sessions: 3),
    );

    expect(find.textContaining('over 3 sittings'), findsOneWidget);
    expect(find.textContaining('over 12 sittings'), findsNothing);
    expect(find.textContaining('Your usual is 40'), findsOneWidget);
    expect(find.text('15h 0m'), findsOneWidget); // 300 pages at the book's 20 pp/h
  });

  testWidgets('an unmeasured reader is asked, not given a borrowed number',
      (tester) async {
    // Was: a grey "at a typical 40 pages/hour" plus derived units. On a
    // 176-page screenplay with one one-minute sitting that produced
    // "≈ 150 sittings" and "≈ 149 weeks at your rate" — arithmetic working
    // perfectly on a sample that means nothing, over a label claiming it was
    // the reader's (owner report, 14 Aug 2026). On a book they own, the block
    // now asks instead of guessing.
    await _pump(tester, pageCount: 400, entry: _entry(), pace: ReadingPace.empty);

    expect(find.text('Not enough reading yet to tell you'), findsOneWidget);
    expect(find.textContaining('of 3 timed sittings'), findsOneWidget);
    // Nothing on screen may look like an answer.
    expect(find.textContaining('at a typical'), findsNothing);
    expect(find.textContaining('weeks'), findsNothing);
    expect(find.text('sittings'), findsNothing);
    expect(find.textContaining('at your rate'), findsNothing);
  });

  testWidgets('a book you do not own keeps the typical-pace hours', (tester) async {
    // P7's deciding screen: there is nothing to ask a reader *for* here, and
    // "roughly this long at a typical pace" is the entire point of showing it
    // on a book they are considering.
    await _pump(tester, pageCount: 400, pace: ReadingPace.empty);

    expect(find.textContaining('at a typical 40 pages/hour'), findsOneWidget);
    expect(find.text('Not enough reading yet to tell you'), findsNothing);
  });

  testWidgets('no page count asks for the one number that fixes it', (tester) async {
    await _pump(tester, pageCount: null, entry: _entry());

    expect(find.textContaining('how long this book is'), findsOneWidget);
    expect(find.text('How long is it?'), findsOneWidget);
    expect(find.textContaining('Hidden from'), findsOneWidget);
  });

  testWidgets('the strip renders nothing at all without a page count', (tester) async {
    await _pump(tester, pageCount: null, variant: TimeToFinishVariant.strip);

    expect(find.textContaining('How long is it?'), findsNothing);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('the strip works with no library entry — a book you do not own', (tester) async {
    await _pump(tester, pageCount: 320, variant: TimeToFinishVariant.strip);

    expect(find.textContaining('8h 0m for you'), findsOneWidget);
  });
}
