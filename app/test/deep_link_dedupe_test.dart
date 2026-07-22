/// Guards the delivery rules in `core/deep_links.dart`.
///
/// A shared link reaches the app through up to three channels and each one
/// misbehaves differently, so the dedupe rules are the whole feature:
///
/// * a cold start delivers the SAME tap twice (stream + getInitialLink) — the
///   book page must open once, not twice (observed on an Android emulator);
/// * `getLatestLink()` on resume keeps returning the last link forever, so
///   plain app-switching must not re-open it;
/// * but a genuine re-tap of the same link later must still navigate.
///
/// The guard under test is pure timing/identity logic, reproduced here so it
/// can be exercised without the platform channel. Keep in step with
/// `DeepLinkListener._handle`.
library;

import 'package:flutter_test/flutter_test.dart';

/// Mirror of `DeepLinkListener`'s dedupe decision.
class LinkDedupe {
  static const echoWindow = Duration(milliseconds: 1500);

  Uri? lastHandled;
  DateTime? lastHandledAt;

  /// Returns true when the link should be routed.
  bool accept(Uri uri, DateTime now) {
    if (uri == lastHandled &&
        lastHandledAt != null &&
        now.difference(lastHandledAt!) < echoWindow) {
      return false;
    }
    lastHandled = uri;
    lastHandledAt = now;
    return true;
  }

  /// The resume path: identity-only, since getLatestLink() never goes stale.
  bool acceptFromResume(Uri uri, DateTime now) {
    if (uri == lastHandled) return false;
    return accept(uri, now);
  }
}

void main() {
  final t0 = DateTime(2026, 7, 23, 10);
  final book = Uri.parse('https://kitabi.in/b/cf2c9f06-471c-4068-809c-585571d5bbd6');
  final other = Uri.parse('https://kitabi.in/b/11111111-2222-3333-4444-555555555555');

  test('cold start delivers one tap twice — it opens the book once', () {
    final d = LinkDedupe();
    // Stream fires first, then getInitialLink resolves ~milliseconds later.
    expect(d.accept(book, t0), isTrue, reason: 'first delivery routes');
    expect(
      d.accept(book, t0.add(const Duration(milliseconds: 40))),
      isFalse,
      reason: 'the echo of the same tap must not push a second copy',
    );
  });

  test('re-tapping the same link later still opens it', () {
    final d = LinkDedupe();
    d.accept(book, t0);
    // Reader backs out to home, taps the same shared link again a minute on.
    expect(
      d.accept(book, t0.add(const Duration(minutes: 1))),
      isTrue,
      reason: 'past the echo window this is a deliberate tap, not an echo',
    );
  });

  test('a different book always routes, even back to back', () {
    final d = LinkDedupe();
    d.accept(book, t0);
    expect(d.accept(other, t0.add(const Duration(milliseconds: 40))), isTrue);
  });

  group('resume fallback', () {
    test('plain app-switching does not re-open the last link', () {
      final d = LinkDedupe();
      d.accept(book, t0);
      // getLatestLink() still reports `book` on every resume, forever.
      expect(d.acceptFromResume(book, t0.add(const Duration(minutes: 5))), isFalse);
      expect(d.acceptFromResume(book, t0.add(const Duration(hours: 2))), isFalse);
    });

    test('a link the stream missed is caught on resume', () {
      final d = LinkDedupe();
      d.accept(book, t0);
      // iOS delivered nothing for this tap; resume is the only report of it.
      expect(
        d.acceptFromResume(other, t0.add(const Duration(seconds: 3))),
        isTrue,
        reason: 'this is the warm-start miss the fallback exists for',
      );
    });
  });
}
