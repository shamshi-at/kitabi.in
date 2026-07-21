import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/features/library/presentation/session_page_entry.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// R1's page entry — the block every stop surface shares. Three behaviours are
/// the reason it exists, and all three are easy to regress:
///
/// * tapping the number **replaces** it (no backspacing a 3-digit page),
/// * −/+ nudge it for the common "off by one" case,
/// * a page that would walk progress *backwards* can't be saved.
void main() {
  late TextEditingController page;
  late TextEditingController total;
  late FocusNode focus;
  PageEntryError? lastError;

  setUp(() {
    page = TextEditingController();
    total = TextEditingController();
    focus = FocusNode();
    lastError = null;
  });

  tearDown(() {
    page.dispose();
    total.dispose();
    focus.dispose();
  });

  Future<void> pump(
    WidgetTester tester, {
    int? pageCount,
    int? pageStart,
    String initial = '',
    Duration duration = const Duration(minutes: 60),
  }) async {
    page.text = initial;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: SessionPageEntry(
            pageController: page,
            totalController: total,
            pageFocusNode: focus,
            pageCount: pageCount,
            pageStart: pageStart,
            duration: duration,
            onValidityChanged: (e) => lastError = e,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('focusing the number selects it all, so typing replaces it',
      (tester) async {
    await pump(tester, pageCount: 724, pageStart: 260, initial: '260');

    focus.requestFocus();
    await tester.pumpAndSettle();

    // The whole value is selected — the next keystroke overwrites "260"
    // rather than appending to it.
    expect(page.selection.baseOffset, 0);
    expect(page.selection.extentOffset, 3);
  });

  testWidgets('the steppers nudge by one, and long-press by ten', (tester) async {
    await pump(tester, pageCount: 724, pageStart: 260, initial: '300');

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(page.text, '301');

    await tester.tap(find.byIcon(Icons.remove));
    await tester.pumpAndSettle();
    expect(page.text, '300');

    await tester.longPress(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(page.text, '310');
  });

  testWidgets('a stepper will not push the page past the end of the book',
      (tester) async {
    await pump(tester, pageCount: 302, pageStart: 260, initial: '302');

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(page.text, '302'); // clamped, not 303
    expect(lastError, isNull);
  });

  testWidgets('a page below where the sitting began is rejected', (tester) async {
    await pump(tester, pageCount: 724, pageStart: 260, initial: '260');

    await tester.enterText(find.byType(TextField).first, '88');
    await tester.pumpAndSettle();

    // This is the "don't down-log" guard: 88 is almost always a typo, and
    // accepting it would walk the reader's progress backwards.
    expect(lastError, PageEntryError.belowStart);
    // The message points at the one place that *can* walk progress back,
    // rather than just refusing.
    expect(find.textContaining('correct earlier progress'), findsOneWidget);
  });

  testWidgets('a page beyond the book is rejected with its real length',
      (tester) async {
    await pump(tester, pageCount: 724, pageStart: 260, initial: '260');

    await tester.enterText(find.byType(TextField).first, '9999');
    await tester.pumpAndSettle();

    expect(lastError, PageEntryError.aboveTotal);
    expect(find.textContaining('724 pages'), findsOneWidget);
  });

  testWidgets('clearing the number is not an error — it just means no page',
      (tester) async {
    await pump(tester, pageCount: 724, pageStart: 260, initial: '300');
    expect(lastError, isNull);

    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();

    expect(lastError, isNull);
  });

  testWidgets('a valid page shows what it means: pages read and pace',
      (tester) async {
    await pump(
      tester,
      pageCount: 724,
      pageStart: 260,
      initial: '302',
      duration: const Duration(hours: 1),
    );

    // 42 pages in an hour, and 302/724 ≈ 42%.
    expect(find.textContaining('42 pages'), findsOneWidget);
    expect(find.textContaining('42 pages/hr'), findsOneWidget);
    expect(find.textContaining('42%'), findsOneWidget);
  });

  testWidgets('the total is asked for only when the catalogue has none',
      (tester) async {
    await pump(tester, pageCount: 724, pageStart: 260, initial: '300');
    expect(find.textContaining('How long is this book?'), findsNothing);

    await pump(tester, pageCount: null, pageStart: 60, initial: '88');
    expect(find.textContaining('How long is this book?'), findsOneWidget);
    // And it says why — the total improves the shared catalogue.
    expect(find.textContaining('every other reader'), findsOneWidget);
  });

  testWidgets('with no known total there is nothing to exceed', (tester) async {
    await pump(tester, pageCount: null, pageStart: 60, initial: '60');

    await tester.enterText(find.byType(TextField).first, '5000');
    await tester.pumpAndSettle();

    expect(lastError, isNull);
  });
}
