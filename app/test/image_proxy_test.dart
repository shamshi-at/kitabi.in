import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/core/widgets/image_proxy.dart';

/// Every catalogue image lives in the Supabase `covers` bucket, and every byte
/// that leaves it is metered — the app fetched them straight from the bucket
/// on each install, which is how a 99 MB bucket produced 5.7 GB of egress in
/// a month (Supabase grace period, 7 Sep 2026). The web already served covers
/// through kitabi.in's edge proxy; the app now does too, and this pins the
/// rewrite to the proxy's own allowlist (`landing-page/functions/img/c.js`).
void main() {
  const bucket =
      'https://abcdefghijklmnop.supabase.co/storage/v1/object/public/covers/covers/x.jpg';
  const openLibrary = 'https://covers.openlibrary.org/b/id/12345-L.jpg';

  test('a bucket cover goes through the edge proxy on the share origin', () {
    final out = proxiedImageUrl(bucket, base: 'https://kitabi.in');
    expect(out, 'https://kitabi.in/img/c?u=${Uri.encodeComponent(bucket)}');
    // The whole source survives the round trip, so the proxy can vet it.
    expect(Uri.parse(out).queryParameters['u'], bucket);
  });

  test('an OpenLibrary hotlink goes through it too', () {
    expect(proxiedImageUrl(openLibrary, base: 'https://kitabi.in'),
        startsWith('https://kitabi.in/img/c?u='));
  });

  test('the default base is the share origin', () {
    expect(proxiedImageUrl(bucket), startsWith('https://kitabi.in/img/c?u='));
  });

  test('anything the proxy would refuse is passed through untouched', () {
    for (final url in [
      // http: the proxy refuses a downgrade.
      'http://covers.openlibrary.org/b/id/1-L.jpg',
      // A host that only *contains* an allowed one.
      'https://evil.example/covers.openlibrary.org/x.jpg',
      'https://notsupabase.co/x.jpg',
      'https://x.supabase.co.evil.example/x.jpg',
      // A reader's own photo somewhere else, a data URI, an empty string.
      'https://example.com/cover.jpg',
      'data:image/png;base64,AAAA',
      '',
    ]) {
      expect(proxiedImageUrl(url), url, reason: url);
    }
  });

  test('a URL already on the proxy is not proxied twice', () {
    final once = proxiedImageUrl(bucket);
    expect(proxiedImageUrl(once), once);
  });
}
