import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/core/widgets/ticker_text.dart';

Widget _host(Widget child, {double width = 80, bool reduceMotion = false}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: SizedBox(width: width, child: child)),
    ),
  );
}

void main() {
  const style = TextStyle(fontSize: 14, fontFamily: 'Roboto');

  testWidgets('fitting text renders as a plain static Text', (tester) async {
    await tester.pumpWidget(_host(TickerText('Ash', style: style)));
    expect(find.text('Ash'), findsOneWidget);
    expect(find.byType(ClipRect), findsNothing);
    // Nothing scheduled — pumping far ahead changes nothing.
    await tester.pump(const Duration(seconds: 10));
    expect(find.byType(ClipRect), findsNothing);
  });

  testWidgets('overflowing text runs one ticker pass and settles back', (tester) async {
    await tester.pumpWidget(_host(
      TickerText('A very long title that cannot possibly fit', style: style),
    ));
    expect(find.byType(ClipRect), findsOneWidget);

    Offset offsetNow() {
      final transform = tester.widget<Transform>(find.descendant(
        of: find.byType(ClipRect),
        matching: find.byType(Transform),
      ));
      return Offset(transform.transform.getTranslation().x, 0);
    }

    // Lead-in: still at the start.
    await tester.pump(const Duration(milliseconds: 1100));
    expect(offsetNow().dx, 0);

    // Mid-run (lead-in 1.2s + ~40% of the 7s timeline): slid left.
    await tester.pump(const Duration(milliseconds: 2900));
    expect(offsetNow().dx, lessThan(0));

    // After the full pass: settled back at the start, run does not loop.
    await tester.pump(const Duration(seconds: 7));
    expect(offsetNow().dx, 0);
    await tester.pump(const Duration(seconds: 8));
    expect(offsetNow().dx, 0);
  });

  testWidgets('recycled state with new text gets a fresh single run', (tester) async {
    Offset offsetNow() {
      final transform = tester.widget<Transform>(find.descendant(
        of: find.byType(ClipRect),
        matching: find.byType(Transform),
      ));
      return Offset(transform.transform.getTranslation().x, 0);
    }

    await tester.pumpWidget(_host(
      TickerText('First very long title that cannot possibly fit', style: style),
    ));
    await tester.pump(const Duration(seconds: 16)); // full pass done
    expect(offsetNow().dx, 0);

    // Same element, new book (no key): must reset and run once more.
    await tester.pumpWidget(_host(
      TickerText('Second very long title that cannot possibly fit', style: style),
    ));
    // First tick anchors the restarted ticker's epoch; then advance mid-slide.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 3900));
    expect(offsetNow().dx, lessThan(0));
    await tester.pump(const Duration(seconds: 8));
    expect(offsetNow().dx, 0);
  });

  testWidgets(
      'new text with a new startDelay reuses the single ticker '
      '(regression: grid recycle / live cover preview threw "multiple tickers")',
      (tester) async {
    // TypesetCover derives startDelay from the title hash, so a recycled grid
    // cell — and the add-form's live preview on every keystroke — changes text
    // and startDelay together. The old code disposed and recreated the
    // AnimationController for that case, creating a second Ticker on a
    // SingleTickerProviderStateMixin: the build threw and the cover painted a
    // 100000px RenderErrorBox ("BOTTOM OVERFLOWED BY 99873 PIXELS").
    await tester.pumpWidget(_host(
      TickerText(
        'First very long title that cannot possibly fit',
        style: style,
        startDelay: const Duration(milliseconds: 1200),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 500)); // mid-run: ticker live

    await tester.pumpWidget(_host(
      TickerText(
        'Second very long title that cannot possibly fit',
        style: style,
        startDelay: const Duration(milliseconds: 1740),
      ),
    ));
    expect(tester.takeException(), isNull);

    // The rebuilt timeline (new lead-in baked into its weights) still runs a
    // full pass and settles back.
    Offset offsetNow() {
      final transform = tester.widget<Transform>(find.descendant(
        of: find.byType(ClipRect),
        matching: find.byType(Transform),
      ));
      return Offset(transform.transform.getTranslation().x, 0);
    }

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 4500));
    expect(offsetNow().dx, lessThan(0));
    await tester.pump(const Duration(seconds: 9));
    expect(offsetNow().dx, 0);
  });

  testWidgets('reduced motion falls back to static ellipsis', (tester) async {
    await tester.pumpWidget(_host(
      TickerText('A very long title that cannot possibly fit', style: style),
      reduceMotion: true,
    ));
    expect(find.byType(ClipRect), findsNothing);
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.overflow, TextOverflow.ellipsis);
    await tester.pump(const Duration(seconds: 10)); // nothing scheduled
  });
}
