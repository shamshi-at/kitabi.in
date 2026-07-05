import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/features/share/presentation/book_share_card.dart';
import 'package:kitabi/l10n/app_localizations.dart';

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('share card shows title, author, blurb and the catalog-average caption',
      (tester) async {
    await tester.pumpWidget(
      _wrap(const BookShareCard(
        title: 'The Covenant of Water',
        author: 'Abraham Verghese',
        coverUrl: null,
        blurb: 'A sweeping saga of three generations bound by water.',
        catalogRating: 4.0,
      )),
    );
    await tester.pump();

    expect(find.text('The Covenant of Water'), findsWidgets); // card + typeset cover
    expect(find.text('Abraham Verghese'), findsWidgets);
    expect(find.textContaining('sweeping saga'), findsOneWidget);
    expect(find.text('catalog avg'), findsOneWidget);
  });

  testWidgets('personal-endorsement card swaps the blurb for the review and "your rating"',
      (tester) async {
    await tester.pumpWidget(
      _wrap(const BookShareCard(
        title: 'Khasakkinte Itihasam',
        author: 'O.V. Vijayan',
        coverUrl: null,
        blurb: 'A neutral catalog blurb.',
        catalogRating: 4.0,
        personalRating: 5,
        personalReview: 'The book that rewired how I read Malayalam.',
      )),
    );
    await tester.pump();

    expect(find.text('your rating'), findsOneWidget);
    expect(find.textContaining('rewired how I read'), findsOneWidget);
    expect(find.textContaining('neutral catalog blurb'), findsNothing); // review replaces blurb
  });
}
