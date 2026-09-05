import '../../data/db/daos/library_daos.dart';

/// One book as a shelf names it: the Work (shared record) and the Edition
/// (this printing) — exactly the two ids the book page's route takes.
class BookRef {
  const BookRef({required this.workId, required this.editionId});

  BookRef.fromHit(LibraryHit hit)
      : workId = hit.book.workId,
        editionId = hit.book.editionId;

  final String workId;
  final String editionId;

  @override
  bool operator ==(Object other) =>
      other is BookRef && other.workId == workId && other.editionId == editionId;

  @override
  int get hashCode => Object.hash(workId, editionId);

  @override
  String toString() => 'BookRef($workId, $editionId)';
}

/// The ordered list a book page was opened *from* — a shelf, the whole
/// library, a filtered grid — so the page can be swiped to its neighbours
/// (owner request, 6 Sep 2026).
///
/// Passed as the book route's `extra`. Deliberately a hint, never a
/// dependency: the page renders from its path ids alone, and every entry
/// point that can't assemble a list (a share link, a notification tap, a
/// cover on Home, the catalogue) simply gets a page that doesn't swipe. The
/// list is the reader's, in the reader's order — the grid's sort and filter
/// applied — because "the next book" means the next one *they* can see.
class BookBrowseContext {
  const BookBrowseContext(this.books);

  BookBrowseContext.fromHits(Iterable<LibraryHit> hits)
      : books = [for (final h in hits) BookRef.fromHit(h)];

  final List<BookRef> books;

  /// Where [editionId] sits in the list, or -1 when it isn't there — the
  /// pager then shows the plain page rather than guessing a neighbour. Matched
  /// on the Edition, not the Work: a reader with two printings of one book has
  /// two covers on the shelf, and swiping must walk both.
  int indexOf(String editionId) => books.indexWhere((b) => b.editionId == editionId);

  bool get isEmpty => books.isEmpty;
  int get length => books.length;
}
