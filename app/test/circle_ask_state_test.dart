import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kitabi/features/circle/circle_models.dart';
import 'package:kitabi/features/circle/circle_providers.dart';
import 'package:kitabi/features/circle/widgets/circle_home_card.dart';
import 'package:kitabi/features/circle/widgets/circle_widgets.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// Owner request, 14 Oct 2026: no "ask to borrow" for a book already on your
/// shelves, and once you've asked — from any screen — every surface says
/// "Requested" instead of offering to ask again. The server decides both
/// (`can_ask`, `asked`); these pin that every surface listens.

Map<String, dynamic> _faisal({bool asked = false}) => {
  'user_id': 'u-faisal',
  'name': 'Faisal P',
  'status': null,
  'owns': true,
  'owned_edition_id': 'e-faisal',
  'owned_edition_label': 'DC Books, 2019',
  'asked': asked,
};

CircleWork _work({required bool canAsk, bool asked = false}) =>
    CircleWork.fromJson({
      'people': [_faisal(asked: asked)],
      'owns_count': 1,
      'can_ask': canAsk,
    });

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Widget host(Widget child, List<Override> overrides) => ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );

  /// Fraunces isn't bundled in tests; its "not in assets" report is noise.
  void Function() quietFonts() {
    final original = reportTestException;
    reportTestException = (details, description) {
      if (details.exception.toString().contains('GoogleFonts')) return;
      original(details, description);
    };
    return () => reportTestException = original;
  }

  Future<void> pumpCard(WidgetTester t, CircleWork work) async {
    await t.pumpWidget(
      host(const BookCircleSection(workId: 'w-1', title: 'Kaalam'), [
        circleWorkProvider('w-1').overrideWith((ref) async => work),
      ]),
    );
    await t.pump();
  }

  testWidgets('book page: askable', (t) async {
    final restore = quietFonts();
    await pumpCard(t, _work(canAsk: true));
    expect(find.text('Faisal has a copy'), findsWidgets);
    expect(find.text('Ask to borrow ›'), findsOneWidget);
    restore();
  });

  testWidgets('book page: already asked reads Requested, and is not a button', (
    t,
  ) async {
    final restore = quietFonts();
    await pumpCard(t, _work(canAsk: true, asked: true));
    expect(find.text('Requested ✓'), findsOneWidget);
    expect(find.text('Ask to borrow ›'), findsNothing);
    restore();
  });

  testWidgets('book page: a book already on my shelves offers no ask', (
    t,
  ) async {
    final restore = quietFonts();
    await pumpCard(t, _work(canAsk: false));
    expect(find.text('Ask to borrow ›'), findsNothing);
    expect(find.textContaining('has a copy'), findsNothing);
    expect(
      find.text('YOUR CIRCLE'),
      findsNothing,
      reason: 'nothing left to say',
    );
    restore();
  });

  testWidgets('search line follows the same two rules', (t) async {
    Future<String?> line(Map<String, dynamic> body) async {
      await t.pumpWidget(
        host(CircleSearchLine(signal: CircleSignal.fromJson(body)), const []),
      );
      return t
          .widgetList<Text>(find.textContaining('Faisal'))
          .map((w) => w.data)
          .whereType<String>()
          .firstOrNull;
    }

    final base = {'owns_count': 1};
    expect(
      await line({
        ...base,
        'owners': [_faisal()],
      }),
      'Faisal has a copy · ask to borrow',
    );
    expect(
      await line({
        ...base,
        'owners': [_faisal(asked: true)],
      }),
      'You asked Faisal to lend it',
    );
    expect(
      await line({
        ...base,
        'can_ask': false,
        'owners': [_faisal()],
      }),
      'Faisal has a copy',
    );
  });

  testWidgets("Home's borrow card says Requested once asked", (t) async {
    final restore = quietFonts();
    final pick = CirclePickResponse.fromJson({
      'pick': {
        'kind': 'borrow',
        'work': {
          'id': 'w-1',
          'title': 'Kaalam',
          'authors': [],
          'edition': {'id': 'e-1', 'cover_url': null},
        },
        'person': _faisal(asked: true),
      },
    });
    await t.pumpWidget(
      host(const CircleHomeCard(), [
        circlePickProvider.overrideWith((ref) async => pick),
      ]),
    );
    await t.pump();
    expect(find.text('Requested ✓'), findsOneWidget);
    expect(find.text('Ask Faisal to lend'), findsNothing);
    restore();
  });
}
