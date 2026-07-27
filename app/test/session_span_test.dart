import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/core/format_duration.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// The reading log's clock span. Three rules, each of which would read as a
/// plain lie if it regressed: the ordinary case shows both ends, a sitting that
/// crossed midnight says so, and a row whose end isn't after its start falls
/// back to the start rather than printing a backwards range.
void main() {
  Future<String> span(WidgetTester tester, DateTime start, DateTime end) async {
    late String out;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        out = formatSessionSpan(
          context,
          AppLocalizations.of(context)!,
          startedAt: start,
          endedAt: end,
        );
        return const SizedBox.shrink();
      }),
    ));
    return out;
  }

  testWidgets('shows start and end', (tester) async {
    final out = await span(
      tester,
      DateTime(2026, 7, 27, 19, 42),
      DateTime(2026, 7, 27, 20, 31),
    );
    expect(out, '7:42 PM – 8:31 PM');
  });

  testWidgets('marks a sitting that ran past midnight', (tester) async {
    final out = await span(
      tester,
      DateTime(2026, 7, 27, 23, 40),
      DateTime(2026, 7, 28, 0, 25),
    );
    expect(out, '11:40 PM – 12:25 AM (+1)');
  });

  testWidgets('falls back to the start when the end is not after it', (tester) async {
    final at = DateTime(2026, 7, 27, 8, 5);
    expect(await span(tester, at, at), '8:05 AM');
    expect(await span(tester, at, at.subtract(const Duration(minutes: 3))), '8:05 AM');
  });
}
