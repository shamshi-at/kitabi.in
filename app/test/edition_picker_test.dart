import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/features/catalog/presentation/edition_picker.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// "Which printing is yours?" is a real question when the catalogue holds
/// several, and a non-question when it holds one. The chooser has to know the
/// difference, or a reader who owns the only printing of a book gets a sheet
/// with one row in it.
const _editions = [
  {
    'id': 'e1',
    'page_count': 55,
    'publisher': {'name': 'Current Books'},
  },
  {'id': 'e2', 'page_count': 240, 'format': 'Paperback'},
];

Future<Map<String, dynamic>?> _run(
  WidgetTester tester,
  List<Map<String, dynamic>> editions,
) async {
  Map<String, dynamic>? picked;
  var done = false;
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () async {
          picked = await chooseEdition(context, editions);
          done = true;
        },
        child: const Text('go'),
      ),
    ),
  ));
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  if (done) return picked;
  return null; // sheet still open — the caller drives it and reads `picked`
}

void main() {
  testWidgets('one printing is not a question', (tester) async {
    final picked = await _run(tester, [_editions.first]);
    expect(picked?['id'], 'e1');
    expect(find.text('Which printing is yours?'), findsNothing);
  });

  testWidgets('several printings are told apart by page count', (tester) async {
    await _run(tester, _editions);
    expect(find.text('Which printing is yours?'), findsOneWidget);
    // The page count is the figure a reader recognises on their own copy.
    expect(find.text('Current Books · 55 pp'), findsOneWidget);
    expect(find.text('240 pp · Paperback'), findsOneWidget);
  });

  testWidgets('picking the reprint returns the reprint', (tester) async {
    Map<String, dynamic>? picked;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async => picked = await chooseEdition(context, _editions),
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('240 pp · Paperback'));
    await tester.pumpAndSettle();
    expect(picked?['id'], 'e2');
  });

  testWidgets('dismissing the sheet shelves nothing', (tester) async {
    Map<String, dynamic>? picked;
    var returned = false;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            picked = await chooseEdition(context, _editions);
            returned = true;
          },
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    // Tap the scrim — a dismissed question must not become an answer.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(returned, isTrue);
    expect(picked, isNull);
  });
}
