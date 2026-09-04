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
  _isbnStandingTests();
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

/// `isbnStandingIn` — the question the duplicate fork has to answer before it
/// offers the reader anything (owner report, 5 Sep 2026: a suggested book with
/// a different ISBN was offered as "this is it", and the reader's cover, page
/// count and ISBN were written onto a printing that wasn't theirs).
void _isbnStandingTests() {
  Map<String, dynamic> workWith(List<String?> isbns) => {
        'id': 'w1',
        'editions': [
          for (var i = 0; i < isbns.length; i++) {'id': 'e$i', 'isbn': isbns[i]},
        ],
      };

  group('isbnStandingIn', () {
    test('no number on the form settles nothing', () {
      expect(isbnStandingIn(workWith(['9788126419470']), '').standing, IsbnStanding.unknown);
      expect(isbnStandingIn(workWith(['9788126419470']), null).standing, IsbnStanding.unknown);
    });

    test('the entry holds this printing — and says which one', () {
      final verdict = isbnStandingIn(workWith(['111', '9788126419470']), '9788126419470');
      expect(verdict.standing, IsbnStanding.samePrinting);
      expect(verdict.edition?['id'], 'e1');
    });

    test('hyphens are spelling, not identity', () {
      final verdict = isbnStandingIn(workWith(['9788126419470']), '978-81-264-1947-0');
      expect(verdict.standing, IsbnStanding.samePrinting);
    });

    test('a number the entry does not hold is a printing it does not have', () {
      final verdict = isbnStandingIn(workWith(['9788126419470']), '9789388630016');
      expect(verdict.standing, IsbnStanding.newPrinting);
      expect(verdict.edition, isNull);
    });

    test('an entry whose printings carry no number cannot disagree', () {
      // The bare stub: its one edition may well be this very printing, never
      // given its number. Improving it in place is exactly right.
      expect(isbnStandingIn(workWith([null]), '9789388630016').standing, IsbnStanding.unknown);
      expect(isbnStandingIn(workWith([]), '9789388630016').standing, IsbnStanding.unknown);
    });

    test('one numbered printing is enough to disagree', () {
      final verdict = isbnStandingIn(workWith([null, '9788126419470']), '9789388630016');
      expect(verdict.standing, IsbnStanding.newPrinting);
    });
  });
}
