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
