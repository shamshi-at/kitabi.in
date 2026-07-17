import '../../data/db/database.dart';

/// Reading stats derived from the library — pure and unit-testable (no widgets,
/// no clock). `year == null` means "all time".
class InsightsStats {
  InsightsStats({
    required this.booksRead,
    required this.pagesRead,
    required this.currentlyReading,
    required this.booksPerMonth,
    required this.pagesPerMonth,
    required this.languageMix,
    this.topAuthor,
    this.topAuthorCount = 0,
    this.longestBookTitle,
    this.longestBookPages = 0,
  });

  final int booksRead;
  final int pagesRead;
  final int currentlyReading;

  /// The most-finished author (first listed author of each read book) and how
  /// many of their books were finished — null/0 until two finishes share one.
  final String? topAuthor;
  final int topAuthorCount;

  /// The longest finished book (by page count) — null until something with a
  /// page count is finished.
  final String? longestBookTitle;
  final int longestBookPages;

  /// Mean pages per finished book, over the books that carry a page count.
  int get avgPagesPerBook {
    if (booksRead == 0 || pagesRead == 0) return 0;
    return (pagesRead / booksRead).round();
  }

  /// Finished-books count per calendar month (index 0 = Jan). Meaningful when a
  /// specific year is selected; for "all time" it aggregates every year's months.
  final List<int> booksPerMonth;

  /// Pages read per calendar month (index 0 = Jan).
  final List<int> pagesPerMonth;

  /// Finished-books count per language, most-read first.
  final Map<String, int> languageMix;

  int get busiestMonthCount =>
      booksPerMonth.isEmpty ? 0 : booksPerMonth.reduce((a, b) => a > b ? a : b);

  int get peakPagesMonth =>
      pagesPerMonth.isEmpty ? 0 : pagesPerMonth.reduce((a, b) => a > b ? a : b);
}

InsightsStats computeInsights(List<LibraryHit> hits, {int? year}) {
  bool inYear(DateTime? d) => year == null ? true : (d != null && d.year == year);

  // The date a book counts as finished on. Not every read book has an explicit
  // finish date — only the book page's status sheet sets one, so a book marked
  // read any other way (an older row, a CSV import) has none, and would then
  // vanish from every year-scoped stat: Home showed "2 read" while Insights
  // 2026 showed 0 books / 0 pages (owner report, 17 Jul 2026). Fall back to
  // when the row was last touched, so a read book always lands in some year.
  DateTime? finishedOn(LibraryHit h) => h.entry.finishDate ?? h.entry.updatedAt;

  final read = hits
      .where((h) => h.entry.status == 'read' && inYear(finishedOn(h)))
      .toList();
  final perMonth = List<int>.filled(12, 0);
  final pagesMonth = List<int>.filled(12, 0);
  final languages = <String, int>{};
  final authors = <String, int>{};
  String? longestTitle;
  var longestPages = 0;
  for (final h in read) {
    final f = finishedOn(h);
    if (f != null) {
      perMonth[f.month - 1]++;
      pagesMonth[f.month - 1] += h.book.pageCount ?? 0;
    }
    final lang = (h.book.language?.trim().isNotEmpty ?? false) ? h.book.language! : 'Unknown';
    languages[lang] = (languages[lang] ?? 0) + 1;
    // First listed author stands for the book (co-authored books credit the
    // lead — good enough for a "most-read" superlative).
    final author = h.book.authorNames.split(',').first.trim();
    if (author.isNotEmpty) authors[author] = (authors[author] ?? 0) + 1;
    final pages = h.book.pageCount ?? 0;
    if (pages > longestPages) {
      longestPages = pages;
      longestTitle = h.book.title;
    }
  }
  final sortedLanguages = Map.fromEntries(
    languages.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
  );
  final topAuthorEntry = authors.entries.isEmpty
      ? null
      : (authors.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first;

  return InsightsStats(
    booksRead: read.length,
    pagesRead: read.fold<int>(0, (sum, h) => sum + (h.book.pageCount ?? 0)),
    currentlyReading: hits.where((h) => h.entry.status == 'reading').length,
    booksPerMonth: perMonth,
    pagesPerMonth: pagesMonth,
    languageMix: sortedLanguages,
    // A superlative needs at least a pair — "most-read author: 1 book" is noise.
    topAuthor: (topAuthorEntry != null && topAuthorEntry.value >= 2) ? topAuthorEntry.key : null,
    topAuthorCount: (topAuthorEntry != null && topAuthorEntry.value >= 2)
        ? topAuthorEntry.value
        : 0,
    longestBookTitle: longestTitle,
    longestBookPages: longestPages,
  );
}
