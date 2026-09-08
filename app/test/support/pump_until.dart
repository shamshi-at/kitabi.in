import 'package:flutter_test/flutter_test.dart';

/// Pump until something is true, rather than for a fixed number of frames.
///
/// Why this exists: the reading-timer tests settled with a hand-tuned loop
/// (`for (var i = 0; i < 12; i++) …`), which is a budget measured on whichever
/// machine happened to run them last. On a loaded CI runner racing a
/// deliberately-slow fake API, that budget ran out before the screen finished
/// its work, and the assertion that followed read the previous frame — so
/// `app-ci` was red from 5 Sep 2026 with two tests that pass locally every
/// time. Halving the budget here reproduces the CI failure exactly, which is
/// how it was identified as a race in the *test* rather than flake.
///
/// A condition plus a generous timeout is machine-independent: a fast machine
/// leaves on the first frame, a slow one takes the frames it needs, and a real
/// regression still fails — with a message that says what never happened
/// instead of an assertion about the wrong frame.
///
/// `tester.pumpAndSettle()` is not the answer for these screens: the timer
/// animates a sweeping hand for the whole sitting, so there is never a frame
/// with no pending animation and pumpAndSettle times out by design.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  String? reason,
  Duration timeout = const Duration(seconds: 10),
  Duration step = const Duration(milliseconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    // Real time, so awaited work off the test's zone (a fake network call, a
    // drift query) actually progresses between frames.
    await tester.runAsync(() => Future<void>.delayed(step));
    await tester.pump(step);
    if (condition()) return;
    if (!DateTime.now().isBefore(deadline)) {
      fail('timed out after ${timeout.inSeconds}s waiting for ${reason ?? 'condition'}');
    }
  }
}

/// [pumpUntil] for the common case: wait until a finder matches.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  String? reason,
  Duration timeout = const Duration(seconds: 10),
}) =>
    pumpUntil(
      tester,
      () => finder.evaluate().isNotEmpty,
      reason: reason ?? finder.describeMatch(Plurality.one),
      timeout: timeout,
    );

/// Pump a few real frames when there is nothing specific to wait for — a
/// settle with no condition, kept short on purpose so it is never mistaken for
/// one.
Future<void> pumpFrames(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Let fire-and-forget work started by the screen finish before the test ends.
///
/// Needed *because* the waits above are conditional: a test that leaves the
/// moment its assertion is satisfiable can now outrun a fake network call the
/// screen never awaited, and the binding fails the test with "a Timer is still
/// pending even after the widget tree was disposed". This is wall-clock, so it
/// drains the same on a slow machine as on a fast one.
Future<void> drainPendingTimers(WidgetTester tester) => pumpFrames(tester, 25);
