import '../../data/db/database.dart';

/// Builds a Goodreads-friendly CSV of the personal library — the data-out trust
/// feature that pairs with import. Pure (no I/O) so it's unit-testable.
String buildLibraryCsv(List<LibraryHit> hits) {
  const headers = [
    'Title',
    'Author',
    'ISBN',
    'Language',
    'Exclusive Shelf',
    'Date Started',
    'Date Read',
    'Favorite',
    'Notes',
  ];
  final buffer = StringBuffer()..writeln(headers.map(_escape).join(','));
  for (final hit in hits) {
    final e = hit.entry;
    final b = hit.book;
    buffer.writeln(
      [
        b.title,
        b.authorNames,
        b.isbn ?? '',
        b.language ?? '',
        e.status,
        _date(e.startDate),
        _date(e.finishDate),
        e.isFavorite ? 'yes' : '',
        e.notes ?? '',
      ].map(_escape).join(','),
    );
  }
  return buffer.toString();
}

String _date(DateTime? d) =>
    d == null ? '' : '${d.year}-${_two(d.month)}-${_two(d.day)}';

String _two(int n) => n.toString().padLeft(2, '0');

/// RFC-4180 quoting: wrap in quotes and double any embedded quotes when the
/// value contains a comma, quote, or newline.
String _escape(String value) {
  if (value.contains(RegExp('[",\n\r]'))) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}
