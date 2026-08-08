import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kitabi/core/widgets/image_source_sheet.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// The chained-capture sheet: after a camera capture fills one cover side of a
/// coverless book, it offers the other side right away, so both covers come
/// from one camera run (instead of tap slot → capture → come back → tap the
/// other slot → capture).
Widget _host({required bool nextIsBack, required ValueSetter<bool> onResult}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async {
              onResult(await showChainedCoverSheet(context, nextIsBack: nextIsBack));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('after the front, offers the back — capture returns true', (tester) async {
    bool? result;
    await tester.pumpWidget(_host(nextIsBack: true, onResult: (r) => result = r));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Front cover added'), findsOneWidget);
    expect(find.text('Now capture the back cover'), findsOneWidget);

    await tester.tap(find.text('Now capture the back cover'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('after the back, offers the front — the chain works both ways', (tester) async {
    bool? result;
    await tester.pumpWidget(_host(nextIsBack: false, onResult: (r) => result = r));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Back cover added'), findsOneWidget);
    expect(find.text('Now capture the front cover'), findsOneWidget);

    await tester.tap(find.text('Now capture the front cover'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('skip returns false', (tester) async {
    bool? result;
    await tester.pumpWidget(_host(nextIsBack: true, onResult: (r) => result = r));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('dismissing the sheet (tap the scrim) counts as skip, not a crash',
      (tester) async {
    bool? result;
    await tester.pumpWidget(_host(nextIsBack: true, onResult: (r) => result = r));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(200, 40)); // well above the sheet
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
