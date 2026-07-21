import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/core/languages.dart';
import 'package:kitabi/core/widgets/select_sheet.dart';
import 'package:kitabi/l10n/app_localizations.dart';

void main() {
  group('kLanguages', () {
    test('leads with the Indian shelf, Malayalam first', () {
      expect(kLanguages.first, 'Malayalam');
      expect(
        kLanguages.indexOf('Hindi'), lessThan(kLanguages.indexOf('Arabic')),
        reason: 'the Indian block comes before the world block',
      );
    });

    test('covers the major world languages a translated original may be in', () {
      for (final lang in ['Spanish', 'French', 'German', 'Russian', 'Japanese', 'Portuguese']) {
        expect(kLanguages, contains(lang));
      }
    });

    test('has no duplicates', () {
      expect(kLanguages.toSet().length, kLanguages.length);
    });
  });

  group('languageOptions', () {
    test('puts the reader\'s profile languages first, rest in canonical order', () {
      final opts = languageOptions(['Spanish', 'Malayalam']);
      expect(opts.sublist(0, 2), ['Spanish', 'Malayalam']);
      // Everything else follows, exactly once.
      expect(opts.toSet().length, opts.length);
      expect(opts.length, kLanguages.length);
      expect(opts, containsAll(kLanguages));
    });

    test('with no profile languages falls back to the full canonical list', () {
      expect(languageOptions(const []), kLanguages);
    });

    test('keeps a preferred language the app no longer lists', () {
      final opts = languageOptions(['Klingon']);
      expect(opts.first, 'Klingon');
      expect(opts.length, kLanguages.length + 1);
    });
  });

  group('openSelectSheet', () {
    Future<void> pumpHost(WidgetTester tester, VoidCallback Function(BuildContext) onTap) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: onTap(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('long lists get a search box that filters options', (tester) async {
      String? picked;
      await pumpHost(
        tester,
        (context) => () => openSelectSheet(
              context,
              title: 'Choose language',
              current: null,
              options: [for (final lang in kLanguages) SelectOption(lang, lang)],
              onChanged: (v) => picked = v,
            ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'span');
      await tester.pumpAndSettle();

      expect(find.text('Spanish'), findsOneWidget);
      expect(find.text('Malayalam'), findsNothing);

      await tester.tap(find.text('Spanish'));
      await tester.pumpAndSettle();
      expect(picked, 'Spanish');
    });

    testWidgets('short lists stay a plain tap-list without a search box', (tester) async {
      await pumpHost(
        tester,
        (context) => () => openSelectSheet(
              context,
              title: 'Choose format',
              current: 'Paperback',
              options: const [
                SelectOption('Paperback', 'Paperback'),
                SelectOption('Hardcover', 'Hardcover'),
              ],
              onChanged: (_) {},
            ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.text('Hardcover'), findsOneWidget);
    });
  });
}
