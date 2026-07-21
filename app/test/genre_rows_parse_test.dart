import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/data/api/api_client.dart';

/// `/catalog/browse/genres` gained work counts on 21 Jul 2026, changing its
/// rows from bare names to `{name, work_count}`. Two things bit here on-device
/// and both are worth pinning:
///
/// 1. `.cast<Map<String, dynamic>>()` is **lazy** — a wrong element type sails
///    past the API client and only throws when the list is iterated, which
///    landed the error inside the add form's `build()` and red-screened it,
///    far from the cause. Parsing eagerly keeps failures at the boundary.
/// 2. An API deployed *behind* the app still returns the old shape. That skew
///    lasts as long as a deploy does, and it must not cost the reader the
///    whole add form.
void main() {
  test('reads the current shape, keeping counts', () {
    final rows = ApiClient.parseGenreRows([
      {'name': 'Science fiction', 'work_count': 128},
      {'name': 'Fiction', 'work_count': 54},
    ]);

    expect(rows, hasLength(2));
    expect(rows.first['name'], 'Science fiction');
    expect(rows.first['work_count'], 128);
  });

  test('tolerates an older API still sending bare names', () {
    final rows = ApiClient.parseGenreRows(['Biography', 'Fiction']);

    expect(rows.map((r) => r['name']), ['Biography', 'Fiction']);
    // No count to show — the picker simply omits it rather than inventing one.
    expect(rows.every((r) => r['work_count'] == null), isTrue);
  });

  test('is eager, so a bad row cannot explode later inside build', () {
    // The lazy-cast bug: this list would pass `.cast()` untouched and throw on
    // first iteration. Parsing drops what it can't read, right here.
    final rows = ApiClient.parseGenreRows([
      {'name': 'Fiction', 'work_count': 3},
      42,
      null,
    ]);

    expect(rows, hasLength(1));
    expect(rows.single['name'], 'Fiction');
  });

  test('an empty catalogue is an empty list, not a crash', () {
    expect(ApiClient.parseGenreRows([]), isEmpty);
  });
}
