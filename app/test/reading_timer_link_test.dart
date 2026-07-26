import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/core/deep_links.dart';

/// A tap on the iOS Live Activity arrives as a custom-scheme link, and that
/// scheme is *shared with the Supabase OAuth callback*. Getting this wrong
/// doesn't degrade the timer — it breaks sign-in — so the classification has
/// its own test rather than living only inside the listener.
void main() {
  test('a Live Activity tap becomes the timer route for that book', () {
    expect(
      readingTimerRouteFor(Uri.parse('in.kitabi.kitabi://reading-timer/le-42')),
      '/reading-timer/le-42',
    );
  });

  test('the OAuth callback on the same scheme is left alone', () {
    // supabase_flutter's own listener must keep seeing this untouched.
    expect(
      readingTimerRouteFor(Uri.parse('in.kitabi.kitabi://login-callback/#access_token=abc')),
      isNull,
    );
  });

  test('shared https links are not ours either', () {
    expect(
      readingTimerRouteFor(Uri.parse('https://kitabi.in/b/abc-123')),
      isNull,
    );
  });

  test('a malformed link with no entry id routes nowhere', () {
    expect(readingTimerRouteFor(Uri.parse('in.kitabi.kitabi://reading-timer')), isNull);
    expect(readingTimerRouteFor(Uri.parse('in.kitabi.kitabi://reading-timer/')), isNull);
  });

  test('scheme matching is case-insensitive, as iOS may hand it back', () {
    expect(
      readingTimerRouteFor(Uri.parse('IN.KITABI.KITABI://reading-timer/le-7')),
      '/reading-timer/le-7',
    );
  });
}
