import '../../data/db/database.dart';

/// Reading stats derived from the library — pure and unit-testable (no widgets,
/// no clock). `year == null` means "all time".
class InsightsStats {
  const InsightsStats({
    required this.booksRead,
    required this.pagesRead,
    required this.currentlyReading,
    required this.booksPerMonth,
  });

  final int booksRead;
  final int pagesRead;
  final int currentlyReading;

  /// Finished-books count per calendar month (index 0 = Jan). Meaningful when a
  /// specific year is selected; for "all time" it aggregates every year's months.
  final List<int> booksPerMonth;

  int get busiestMonthCount => booksPerMonth.isEmpty ? 0 : booksPerMonth.reduce((a, b) => a > b ? a : b);
}

InsightsStats computeInsights(List<LibraryHit> hits, {int? year}) {
  bool inYear(DateTime? d) => year == null ? true : (d != null && d.year == year);

  final read = hits
      .where((h) => h.entry.status == 'read' && inYear(h.entry.finishDate))
      .toList();
  final perMonth = List<int>.filled(12, 0);
  for (final h in read) {
    final f = h.entry.finishDate;
    if (f != null) perMonth[f.month - 1]++;
  }

  return InsightsStats(
    booksRead: read.length,
    pagesRead: read.fold<int>(0, (sum, h) => sum + (h.book.pageCount ?? 0)),
    currentlyReading: hits.where((h) => h.entry.status == 'reading').length,
    booksPerMonth: perMonth,
  );
}
