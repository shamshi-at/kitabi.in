import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/features/connections/presentation/connection_loans_screen.dart';
import 'package:kitabi/features/library/providers/library_providers.dart';
import 'package:kitabi/l10n/app_localizations.dart';

LendingRecord _record(
  String id, {
  String direction = 'lent',
  String? entryId,
  String? editionId,
  String name = 'Anu',
  String? userId,
  required DateTime lent,
  DateTime? returned,
}) {
  return LendingRecord(
    id: id,
    userId: 'u1',
    direction: direction,
    libraryEntryId: entryId,
    editionId: editionId,
    borrowerName: name,
    borrowerUserId: userId,
    linkedLoanId: null,
    lentDate: lent,
    dueDate: null,
    returnedDate: returned,
    note: null,
    createdAt: lent,
    updatedAt: lent,
    deletedAt: null,
    syncStatus: 'synced',
    lastSyncedAt: null,
  );
}

CachedBook _book(String editionId) => CachedBook(
      editionId: editionId,
      workId: 'w-$editionId',
      title: 'Book $editionId',
      subtitle: null,
      authorNames: 'An Author',
      publisherName: null,
      coverUrl: null,
      language: null,
      pageCount: null,
      format: null,
      isbn: null,
      genreNames: null,
      firstPublishYear: null,
      seriesName: null,
      seriesNumber: null,
      cachedAt: DateTime(2026, 1, 1),
    );

void main() {
  test('bookLendingHistoryProvider merges lent (via entry) and borrowed (via edition), newest first',
      () async {
    final records = [
      LendingWithBook(record: _record('lent-old', entryId: 'le1', lent: DateTime(2026, 1, 5))),
      LendingWithBook(
          record: _record('borrowed',
              direction: 'borrowed', editionId: 'ed1', lent: DateTime(2026, 3, 1))),
      LendingWithBook(record: _record('lent-new', entryId: 'le1', lent: DateTime(2026, 6, 1))),
      LendingWithBook(record: _record('other-book', entryId: 'le9', lent: DateTime(2026, 5, 1))),
    ];
    final container = ProviderContainer(overrides: [
      allLendingProvider.overrideWith((ref) => Stream.value(records)),
    ]);
    addTearDown(container.dispose);

    // Let the stream deliver.
    await container.read(allLendingProvider.future);
    final history = container
        .read(bookLendingHistoryProvider((entryId: 'le1', editionId: 'ed1')))
        .valueOrNull;

    expect(history?.map((r) => r.id).toList(), ['lent-new', 'borrowed', 'lent-old']);
  });

  testWidgets('person page matches free-text names when there is no linked user', (tester) async {
    final records = [
      LendingWithBook(
          record: _record('r1', entryId: 'le1', name: 'Anu', lent: DateTime(2026, 6, 1)),
          book: _book('ed1')),
      LendingWithBook(
          record: _record('r2',
              direction: 'borrowed', editionId: 'ed2', name: 'Rahul', lent: DateTime(2026, 5, 1)),
          book: _book('ed2')),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allLendingProvider.overrideWith((ref) => Stream.value(records)),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ConnectionLoansScreen(name: 'Anu'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // Only Anu's loan shows (row + its typeset cover); Rahul's is filtered out.
    expect(find.text('Book ed1'), findsWidgets);
    expect(find.text('Book ed2'), findsNothing);
  });
}
