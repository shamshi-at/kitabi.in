import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/features/circle/circle_models.dart';
import 'package:kitabi/features/circle/circle_providers.dart';
import 'package:kitabi/features/lending/presentation/borrow_asks_section.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// Asks to borrow on the Lending tab. Owner report, 14 Oct 2026: an ask was a
/// push and nothing else — the tap led nowhere that mentioned it, and the app
/// kept no trace of it.

/// Written from `api/app/schemas/circle.py` (BorrowAsksOut), not from the widget.
const _body = {
  'incoming': [
    {
      'id': 'req-1',
      'person': {
        'user_id': 'u-anu',
        'name': 'Anu Thomas',
        'username': 'anu',
        'avatar_url': null,
      },
      'work_id': 'w-1',
      'edition_id': 'e-1',
      'title': 'Kaalam',
      'author': 'M. T. Vasudevan Nair',
      'cover_url': null,
      'created_at': '2026-10-14T08:00:00Z',
    },
  ],
  'outgoing': [
    {
      'id': 'req-2',
      'person': {
        'user_id': 'u-ben',
        'name': 'Ben Test',
        'username': null,
        'avatar_url': null,
      },
      'work_id': 'w-2',
      'edition_id': 'e-2',
      'title': 'Chemmeen',
      'author': null,
      'cover_url': null,
      'created_at': '2026-10-14T09:00:00Z',
    },
  ],
};

class _Api extends ApiClient {
  final declined = <String>[];

  @override
  Future<void> circleDeclineBorrowAsk(String requestId) async =>
      declined.add(requestId);

  @override
  Future<Map<String, dynamic>> circleBorrowAsks() async => {
    'incoming': [],
    'outgoing': [],
  };
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget host(List<Override> overrides) => ProviderScope(
    overrides: overrides,
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: BorrowAsksSection())),
    ),
  );

  test(
    'parses both directions, and drops a malformed row instead of throwing',
    () {
      final asks = BorrowAsks.fromJson({
        ..._body,
        'incoming': [
          ...(_body['incoming']! as List),
          {'id': 'broken'},
        ],
      });
      expect(asks.incoming.single.personShortName, 'Anu');
      expect(asks.incoming.single.personUsername, 'anu');
      expect(asks.outgoing.single.title, 'Chemmeen');
      expect(BorrowAsks.fromJson(const {}).isEmpty, isTrue);
    },
  );

  testWidgets('an ask waits on the Lending tab with Lend it and Not now', (
    tester,
  ) async {
    final api = _Api();
    await tester.pumpWidget(
      host([
        apiClientProvider.overrideWithValue(api),
        borrowAsksProvider.overrideWith(
          (ref) async => BorrowAsks.fromJson(_body),
        ),
      ]),
    );
    await tester.pump();

    expect(find.text('ASKED TO BORROW'), findsOneWidget);
    expect(find.text('Anu would like to borrow “Kaalam”'), findsOneWidget);
    expect(find.text('Lend it'), findsOneWidget);
    expect(
      find.text('You asked Ben for “Chemmeen” — waiting for them'),
      findsOneWidget,
    );

    await tester.tap(find.text('Not now'));
    await tester.pump();
    expect(api.declined, ['req-1']);
    expect(find.text('Anu would like to borrow “Kaalam”'), findsNothing);
  });

  testWidgets('nothing asked: the section takes no space', (tester) async {
    await tester.pumpWidget(
      host([
        borrowAsksProvider.overrideWith((ref) async => const BorrowAsks()),
      ]),
    );
    await tester.pump();
    expect(find.text('ASKED TO BORROW'), findsNothing);
    expect(tester.getSize(find.byType(BorrowAsksSection)).height, 0);
  });
}
