// The fork sheet on a real phone, with every answer showing.
//
// "Kitabi already has this book" can have seven answers once the merge option
// is offered, and they do not fit a phone screen. The sheet was the one
// `showModalBottomSheet` in this file without `isScrollControlled`, and its
// body was a plain Column — so the default half-screen cap clipped the list
// with no way to scroll it, and the last answers were simply unreachable
// (owner report on TestFlight, 5 Sep 2026).
//
// Driven SHORT but not narrow: 1000x700. The bug is vertical — the sheet has
// more answers than height — and the other sheet tests miss it only because
// they run at 2400 tall. Width stays generous on purpose: the test font's
// metrics are wider than the real one, so a true 390pt viewport overflows the
// author row here while rendering fine on the device, and chasing that would
// be testing the harness rather than the sheet.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:kitabi/core/router/app_router.dart';
import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/features/catalog/presentation/add_edit_book_screen.dart';
import 'package:kitabi/l10n/app_localizations.dart';

Map<String, dynamic> _match(String id, String title) => {
      'id': id,
      'title': title,
      'first_publish_year': 2008,
      'authors': [
        {'id': 'a1', 'name': 'O. V. Vijayan'},
      ],
      'edition': {'id': 'e-$id', 'cover_url': null},
    };

class _Fake extends ApiClient {
  List<Map<String, dynamic>> similar = const [];

  @override
  Future<List<Map<String, dynamic>>> similarWorks(String title) async => similar;
}

Widget _app(_Fake fake) => ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(fake)],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: GoRouter(routes: [
          GoRoute(path: '/', builder: (c, s) => AddEditBookScreen()),
          GoRoute(path: Routes.catalogAdd, builder: (c, s) => const SizedBox.shrink()),
        ]),
      ),
    );

Future<void> _openFork(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).first, 'Dharmapuranam');
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Dharmapuranam').last);
  await tester.pumpAndSettle();
}

void main() {
  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('every answer is reachable on a short screen', (tester) async {
    await phone(tester);
    final fake = _Fake()
      ..similar = [
        _match('11111111-1111-1111-1111-111111111111', 'Dharmapuranam'),
        _match('22222222-2222-2222-2222-222222222222', 'Dharmapuranm'),
      ];
    await tester.pumpWidget(_app(fake));
    await tester.pumpAndSettle();
    await _openFork(tester);

    // The first answer is visible without doing anything.
    expect(find.text('I own this one — put it on my shelf'), findsOneWidget);

    // The last one is the whole point: it exists, and it can be brought into
    // view. `ensureVisible` throws if nothing scrollable holds it.
    final last = find.text('Different book, same title — keep typing');
    expect(last, findsOneWidget);
    await tester.ensureVisible(last);
    await tester.pumpAndSettle();

    // …and it is a real target once there, not merely painted off-screen.
    await tester.tap(last);
    await tester.pumpAndSettle();
  });

  testWidgets('the book it is asking about does not scroll away', (tester) async {
    await phone(tester);
    final fake = _Fake()
      ..similar = [
        _match('11111111-1111-1111-1111-111111111111', 'Dharmapuranam'),
        _match('22222222-2222-2222-2222-222222222222', 'Dharmapuranm'),
      ];
    await tester.pumpWidget(_app(fake));
    await tester.pumpAndSettle();
    await _openFork(tester);

    expect(find.text('Kitabi already has this book.'), findsOneWidget);
    await tester.ensureVisible(find.text('Different book, same title — keep typing'));
    await tester.pumpAndSettle();
    // Still there after scrolling to the bottom of the answers — a list of
    // choices with nothing saying what they are about is worse than a scroll.
    expect(find.text('Kitabi already has this book.'), findsOneWidget);
  });

  testWidgets('the short sheet still fits without scrolling', (tester) async {
    await phone(tester);
    // One match, nothing captured: no merge option, no "add my details".
    final fake = _Fake()..similar = [_match('11111111-1111-1111-1111-111111111111', 'Chemmeen')];
    await tester.pumpWidget(_app(fake));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Chemmeen');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chemmeen').last);
    await tester.pumpAndSettle();

    expect(find.text('These are all the same book'), findsNothing);
    expect(find.text('I own this one — put it on my shelf'), findsOneWidget);
    expect(find.text('Different book, same title — keep typing'), findsOneWidget);
  });
}
