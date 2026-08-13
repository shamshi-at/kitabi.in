import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/features/catalog/work_editions.dart';

/// Scanning a barcode used to shelve `editions.first` — which is the Work's
/// *representative* printing, not the one in the reader's hands. A 55-page
/// first edition on the shelf while holding a 240-page reprint makes every
/// progress figure lie (owner report, 13 Aug 2026).
Map<String, dynamic> _work({String? scannedId}) => {
      'id': 'w1',
      'title': 'Naalukett',
      'scanned_edition_id': scannedId,
      'editions': [
        {'id': 'e1', 'page_count': 55, 'publisher': {'name': 'Current Books'}},
        {'id': 'e2', 'page_count': 240, 'format': 'Paperback'},
      ],
    };

void main() {
  test('the scanned printing wins over the first one', () {
    expect(scannedEdition(_work(scannedId: 'e2'))?['id'], 'e2');
  });

  test('no scanned id — an API older than this app — falls back to the first', () {
    // Deploy order: an app newer than the server is normal, and must degrade
    // to the previous behaviour rather than to nothing.
    expect(scannedEdition(_work())?['id'], 'e1');
    final legacy = Map<String, dynamic>.from(_work())..remove('scanned_edition_id');
    expect(scannedEdition(legacy)?['id'], 'e1');
  });

  test('an id we do not hold falls back rather than returning nothing', () {
    expect(scannedEdition(_work(scannedId: 'gone'))?['id'], 'e1');
  });

  test('a work with no editions has no scanned one', () {
    expect(scannedEdition({'id': 'w1', 'editions': const []}), isNull);
  });

  test('the label says what actually tells two printings apart', () {
    expect(
      editionLabel({
        'publisher': {'name': 'DC Books'},
        'pub_date': '2011-04-01',
        'page_count': 240,
        'format': 'Paperback',
      }),
      'DC Books · 2011 · 240 pp · Paperback',
    );
    expect(editionLabel({'page_count': 55}), '55 pp');
    expect(editionLabel(const {}), '');
  });
}
