import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/features/library/session_pages.dart';

/// Pages gained per sitting, for the reading log. The whole point of the
/// null-not-zero contract is that the UI can omit the figure — a "+0" against a
/// real hour of reading reads as a failure to record it.
void main() {
  var seq = 0;
  ReadingSession session({int? pageStart, int? pageEnd}) {
    seq++;
    final at = DateTime(2026, 7, 27, 9, seq);
    return ReadingSession(
      id: 's$seq',
      userId: 'u1',
      libraryEntryId: 'e1',
      startedAt: at,
      endedAt: at.add(const Duration(minutes: 30)),
      durationSeconds: 1800,
      pageStart: pageStart,
      pageEnd: pageEnd,
      createdAt: at,
      updatedAt: at,
      syncStatus: 'synced',
    );
  }

  group('sessionPagesRead', () {
    test('counts the pages between start and end', () {
      expect(sessionPagesRead(session(pageStart: 260, pageEnd: 302)), 42);
    });

    test('is null when the sitting recorded no pages', () {
      expect(sessionPagesRead(session()), isNull);
      expect(sessionPagesRead(session(pageStart: 260)), isNull);
      expect(sessionPagesRead(session(pageEnd: 302)), isNull);
    });

    test('is null, not zero, when the sitting ended where it started', () {
      expect(sessionPagesRead(session(pageStart: 260, pageEnd: 260)), isNull);
    });

    test('is null when the sitting went backwards through the book', () {
      expect(sessionPagesRead(session(pageStart: 302, pageEnd: 260)), isNull);
    });
  });

  group('totalPagesRead', () {
    test('sums only the sittings that recorded pages', () {
      final total = totalPagesRead([
        session(pageStart: 190, pageEnd: 214),
        session(),
        session(pageStart: 214, pageEnd: 260),
        session(pageStart: 260, pageEnd: 260),
        session(pageStart: 260, pageEnd: 302),
      ]);
      expect(total, 24 + 46 + 42);
    });

    test('is null when nothing recorded pages, so the header can drop it', () {
      expect(totalPagesRead([session(), session(pageStart: 12)]), isNull);
      expect(totalPagesRead(const []), isNull);
    });
  });
}
