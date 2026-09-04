/// Picking one printing out of a Work's `editions` list.
///
/// A Work carries every printing anyone has catalogued, and they differ in
/// exactly the fields a reader cares about — page count, cover, publisher,
/// ISBN. So "which edition?" is never a throwaway question, and
/// `editions.first` is never the answer on its own: it put the 55-page first
/// printing on the shelf when the reader had scanned a 240-page reprint in
/// their hand (owner report, 13 Aug 2026).
library;

/// Every edition of [work], as maps, in the order the server sent them.
List<Map<String, dynamic>> editionsOf(Map<String, dynamic> work) =>
    (work['editions'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

/// The printing a scan resolved to.
///
/// `GET /catalog/isbn/{isbn}` returns the whole Work plus `scanned_edition_id`
/// — the one printing that actually carries the barcode. The fallback to the
/// first edition is for an API deployed behind this app (CLAUDE.md: an app
/// newer than the server is a normal deploy-order state), not a preference.
Map<String, dynamic>? scannedEdition(Map<String, dynamic> work) {
  final editions = editionsOf(work);
  if (editions.isEmpty) return null;
  final scannedId = work['scanned_edition_id'] as String?;
  if (scannedId != null) {
    for (final edition in editions) {
      if (edition['id'] == scannedId) return edition;
    }
  }
  return editions.first;
}

/// A one-line description of a printing, for the chooser: what actually tells
/// two printings of the same book apart. Empty when the catalogue knows
/// nothing distinguishing about it — the caller falls back to a label.
String editionLabel(Map<String, dynamic> edition) {
  final publisher = (edition['publisher'] as Map?)?['name'] as String?;
  final pages = edition['page_count'];
  final format = edition['format'] as String?;
  final year = (edition['pub_date'] as String?)?.split('-').first;
  return [
    if (publisher != null && publisher.trim().isNotEmpty) publisher.trim(),
    if (year != null && year.isNotEmpty) year,
    if (pages != null) '$pages pp',
    if (format != null && format.isNotEmpty) format,
  ].join(' · ');
}

/// An ISBN reduced to what actually identifies it: digits and a trailing X.
/// Readers type hyphens, scanners don't, and OpenLibrary is inconsistent — so
/// two spellings of one number must never read as two printings.
String? normalizeIsbn(String? raw) {
  if (raw == null) return null;
  final cleaned = raw.toUpperCase().replaceAll(RegExp(r'[^0-9X]'), '');
  return cleaned.isEmpty ? null : cleaned;
}

/// Where the number on the add form stands against the printings a matched
/// Work already holds. See [isbnStandingIn].
enum IsbnStanding {
  /// Nothing to compare: no ISBN on the form, or no printing on the entry
  /// carries one. A bare stub is the common case, and improving it in place is
  /// exactly right.
  unknown,

  /// The entry already holds this exact number — the reader is looking at
  /// their own printing. Details captured here belong on *that* edition.
  samePrinting,

  /// The entry holds printings and none of them is this number. The reader is
  /// holding a printing the catalogue does not have.
  newPrinting,
}

/// Read [isbn] against [work]'s printings.
///
/// This is the question the duplicate fork has to answer before it offers the
/// reader anything, and it used to be left to the reader's reading of a label.
/// "This is it — add my covers and details" is true of the *book* and false of
/// the *printing*: everything that fork carries (cover, page count, ISBN,
/// format, publisher) is edition-level, so on a different printing it lands on
/// somebody else's row and quietly corrupts it (owner report, 5 Sep 2026).
///
/// [newPrinting] is deliberately conservative. It needs a positive signal —
/// at least one catalogued printing carrying a *different* number — because an
/// entry whose editions have no ISBNs at all may well be this very printing,
/// never given its number. An ISBN that got here has already been looked up
/// and not found, so it cannot be a silent duplicate of anything.
({IsbnStanding standing, Map<String, dynamic>? edition}) isbnStandingIn(
  Map<String, dynamic> work,
  String? isbn,
) {
  final wanted = normalizeIsbn(isbn);
  if (wanted == null) return (standing: IsbnStanding.unknown, edition: null);
  var sawAnyIsbn = false;
  for (final edition in editionsOf(work)) {
    final held = normalizeIsbn(edition['isbn'] as String?);
    if (held == null) continue;
    sawAnyIsbn = true;
    if (held == wanted) return (standing: IsbnStanding.samePrinting, edition: edition);
  }
  return (
    standing: sawAnyIsbn ? IsbnStanding.newPrinting : IsbnStanding.unknown,
    edition: null,
  );
}
