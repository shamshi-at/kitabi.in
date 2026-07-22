import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/features/catalog/presentation/author_browse_screen.dart';
import 'package:kitabi/features/catalog/providers/catalog_providers.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// A "This is me" claim is queued for manual review, so the author page must
/// look different depending on *who* is looking: the claimant sees a pending
/// notice, everyone else sees the author exactly as it was.
void main() {
  const authorId = 'a1';

  Map<String, dynamic> body({
    String? linkedUserId,
    bool claimPending = false,
  }) =>
      {
        'author': {
          'id': authorId,
          'name': 'Benyamin',
          'linked_user_id': linkedUserId,
          'claim_pending': claimPending,
        },
        'works': <Map<String, dynamic>>[],
      };

  Widget wrap(Map<String, dynamic> data) => ProviderScope(
        overrides: [
          authorWorksProvider(authorId).overrideWith((ref) async => data),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AuthorBrowseScreen(authorId: authorId),
        ),
      );

  testWidgets('the claimant sees a pending notice instead of the button', (tester) async {
    await tester.pumpWidget(wrap(body(claimPending: true)));
    await tester.pump();

    expect(find.text('Pending review'), findsOneWidget);
    expect(find.text('This is me'), findsNothing, reason: 'already claimed — do not re-offer');
  });

  testWidgets('everyone else still sees the unclaimed author and the button', (tester) async {
    // The same author, same moment, viewed by anyone but the claimant: the
    // server reports claim_pending false and the old (null) link.
    await tester.pumpWidget(wrap(body()));
    await tester.pump();

    expect(find.text('Pending review'), findsNothing);
    expect(find.text('This is me'), findsOneWidget);
  });

  testWidgets('an approved link shows neither the button nor the notice', (tester) async {
    await tester.pumpWidget(wrap(body(linkedUserId: 'u9')));
    await tester.pump();

    expect(find.text('This is me'), findsNothing);
    expect(find.text('Pending review'), findsNothing);
    expect(find.text('View their Kitabi profile'), findsOneWidget);
  });

  testWidgets('a payload without claim_pending is treated as not pending', (tester) async {
    // An API older than this change simply omits the field; the page must not
    // throw on the missing key (CLAUDE.md, 21 Jul: tolerate the other shape).
    await tester.pumpWidget(wrap({
      'author': {'id': authorId, 'name': 'Benyamin', 'linked_user_id': null},
      'works': <Map<String, dynamic>>[],
    }));
    await tester.pump();

    expect(find.text('This is me'), findsOneWidget);
    expect(find.text('Pending review'), findsNothing);
  });
}
