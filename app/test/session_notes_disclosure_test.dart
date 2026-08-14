import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/features/library/presentation/note_page.dart';
import 'package:kitabi/features/library/providers/library_providers.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// "If a new note page is opened, we should provide an option to see the added
/// notes from the same session" (owner request, 14 Aug 2026).
///
/// The rule worth pinning is the exclusion: the note you are *editing* is the
/// page you are on, not a destination to offer — an editor that lists itself
/// invites a reader to navigate in a circle.
ReadingNote _note({required String id, required String body, int? page}) {
  final stamp = DateTime(2026, 8, 14, 10);
  return ReadingNote(
    id: id,
    userId: 'u1',
    createdAt: stamp,
    updatedAt: stamp,
    deletedAt: null,
    syncStatus: 'synced',
    lastSyncedAt: null,
    serverSeq: null,
    libraryEntryId: 'entry-1',
    sessionId: 's1',
    body: body,
    pageStart: page,
    pageEnd: null,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required List<ReadingNote> notes,
  ReadingNote? editing,
}) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  tester.view.physicalSize = const Size(430, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      sessionNotesProvider('s1').overrideWith((ref) => Stream.value(notes)),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: NotePage(
        libraryEntryId: 'entry-1',
        sessionId: 's1',
        sessionStartedAt: DateTime(2026, 8, 14, 10),
        existing: editing,
        startReadOnly: editing != null,
      ),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

/// The note page keeps a live clock ticking (that is the point — "the timer
/// never paused" has to be visible). Tear the tree down inside the test body:
/// the pending-timer invariant is checked before tearDowns run.
Future<void> _close(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('the sitting is offered, collapsed, with its count', (tester) async {
    await _pump(tester, notes: [
      _note(id: 'n1', body: 'The village is a character, not a setting.', page: 76),
      _note(id: 'n2', body: 'Ravi keeps arriving at places he already left.', page: 84),
    ]);

    expect(find.text('Notes from this sitting · 2'), findsOneWidget);
    // Collapsed: the writing space is the scarce resource here (N2), so the
    // bodies stay behind one tap.
    expect(find.textContaining('The village is a character'), findsNothing);
    await _close(tester);
  });

  testWidgets('opening it shows the notes, page first', (tester) async {
    await _pump(tester, notes: [
      _note(id: 'n1', body: 'The village is a character, not a setting.', page: 76),
    ]);

    await tester.tap(find.text('Notes from this sitting · 1'));
    await tester.pumpAndSettle();

    expect(find.textContaining('The village is a character'), findsOneWidget);
    expect(find.text('p. 76'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('the note being edited is not offered as a destination', (tester) async {
    final editing = _note(id: 'n1', body: 'The one I am editing right now.', page: 76);
    await _pump(
      tester,
      notes: [editing, _note(id: 'n2', body: 'A different thought.', page: 84)],
      editing: editing,
    );

    // One other note, not two: listing the current page would let a reader
    // navigate in a circle.
    expect(find.text('Notes from this sitting · 1'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('a sitting with nothing in it offers nothing', (tester) async {
    await _pump(tester, notes: const []);

    expect(find.textContaining('Notes from this sitting'), findsNothing);
    await _close(tester);
  });

  testWidgets('the only note being the edited one offers nothing', (tester) async {
    final editing = _note(id: 'n1', body: 'The only one.', page: 76);
    await _pump(tester, notes: [editing], editing: editing);

    expect(find.textContaining('Notes from this sitting'), findsNothing);
    await _close(tester);
  });
}
