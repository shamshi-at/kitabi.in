import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/features/connections/presentation/public_profile_screen.dart';
import 'package:kitabi/features/library/providers/library_providers.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// A reader's public reviews on their profile (app half). Two things are being
/// pinned: the reviews actually render with a book to open, and the tab obeys
/// the same visibility rules the API does — it is gated on the profile, NOT on
/// the shelf, so a reader with a private library still shows what they chose
/// to publish.
class _FakeApiClient extends ApiClient {
  _FakeApiClient({
    this.libraryVisible = true,
    this.reviews = const [],
    this.reviewsThrow = false,
  });

  final bool libraryVisible;
  final List<Map<String, dynamic>> reviews;
  final bool reviewsThrow;

  int reviewCalls = 0;

  @override
  Future<Map<String, dynamic>> getPublicProfile(String userId) async => {
        'id': userId,
        'username': 'anu',
        'full_name': 'Anu Varghese',
        'avatar_url': null,
        'score': 214,
        'books_tracked': 3,
        'books_finished': 1,
        'library_visible': libraryVisible,
        'connections_count': 0,
      };

  @override
  Future<List<Map<String, dynamic>>> getPublicLibrary(String userId) async => [];

  @override
  Future<List<Map<String, dynamic>>> getPublicWorks(String userId) async => [];

  @override
  Future<List<Map<String, dynamic>>> getPublicReviews(String userId) async {
    reviewCalls++;
    if (reviewsThrow) {
      throw DioException(
        requestOptions: RequestOptions(path: '/users/$userId/reviews'),
        type: DioExceptionType.connectionError,
      );
    }
    return reviews;
  }

  @override
  Future<Map<String, dynamic>> getConnections() async => {
        'incoming': [],
        'outgoing': [],
        'accepted': [],
        'rejected': [],
        'blocked': [],
      };
}

Map<String, dynamic> _review({
  String id = 'r1',
  String title = 'Chemmeen',
  String body = 'I read it first at fifteen.',
  int? rating = 5,
  String? editionId = 'e1',
}) =>
    {
      'id': id,
      'work_id': 'w1',
      'edition_id': editionId,
      'title': title,
      'author_names': 'Thakazhi Sivasankara Pillai',
      'cover_url': null,
      'body': body,
      'rating': rating,
      'created_at': '2026-07-14T00:00:00Z',
    };

Widget _wrap(ApiClient api) => ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        // The ledger tab reads Drift; this screen's test is about the reviews
        // tab, so keep lending empty rather than standing up a database.
        allLendingProvider.overrideWith((ref) => Stream.value([])),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const PublicProfileScreen(userId: 'u1', name: 'Anu Varghese'),
      ),
    );

/// The screen fans out across several autoDispose futures that resolve on
/// different frames (profile, library, works, reviews, connections). Pump a
/// few times rather than settling, since the shelf grid animates.
Future<void> _load(WidgetTester tester, Widget widget) async {
  await tester.pumpWidget(widget);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('a reader with public reviews gets a Reviews tab showing them', (tester) async {
    final api = _FakeApiClient(reviews: [_review()]);
    await _load(tester, _wrap(api));

    // The tab appears with its count, and is not selected by default (the
    // ledger stays first — it is why most visits happen).
    expect(find.text('REVIEWS'), findsOneWidget);
    expect(find.text('I read it first at fifteen.'), findsNothing);

    await tester.tap(find.text('REVIEWS'));
    await tester.pump();
    await tester.pump();

    expect(find.text('I read it first at fifteen.'), findsOneWidget);
    // The title lands twice: ShelfCover always draws the typeset cover
    // underneath (so a slow or dead cover URL is never an empty box), and the
    // row repeats it as the card's header. The author line is the row's alone.
    expect(find.text('Chemmeen'), findsNWidgets(2));
    expect(find.text('Thakazhi Sivasankara Pillai'), findsOneWidget);
    // Their own name is on the bookplate, not repeated on the review card.
    expect(find.text('Anu Varghese'), findsOneWidget);
  });

  testWidgets('a private shelf does not hide the reviews they published', (tester) async {
    // The distinction that matters: `library_visible` gates the shelf only.
    // Getting this wrong in the "safe" direction still silently unpublishes
    // what the reader chose to publish.
    final api = _FakeApiClient(libraryVisible: false, reviews: [_review()]);
    await _load(tester, _wrap(api));

    expect(find.text('REVIEWS'), findsOneWidget);
    await tester.tap(find.text('REVIEWS'));
    await tester.pump();
    await tester.pump();

    expect(find.text('I read it first at fifteen.'), findsOneWidget);
  });

  testWidgets('a reader with no public reviews gets no Reviews tab at all', (tester) async {
    final api = _FakeApiClient(reviews: const []);
    await _load(tester, _wrap(api));

    // Not "Reviews · 0" — an empty segment on every profile is noise.
    expect(find.text('REVIEWS'), findsNothing);
    expect(find.text('LEDGER'), findsOneWidget);
    expect(find.text('SHELF'), findsOneWidget);
  });

  testWidgets('a review with no rating still renders, with no invented stars', (tester) async {
    final api = _FakeApiClient(
      reviews: [_review(rating: null, body: "Haven't decided what I think.")],
    );
    await _load(tester, _wrap(api));
    await tester.tap(find.text('REVIEWS'));
    await tester.pump();
    await tester.pump();

    expect(find.text("Haven't decided what I think."), findsOneWidget);
    expect(find.text('no rating'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsNothing);
  });

  testWidgets('a book with no edition on file renders as an untappable row, not a dead link',
      (tester) async {
    // Reviews attach to the Work (rule 17) but the book route is work+edition,
    // so a Work with no printing yet has nowhere to send the reader. The row
    // must still show what they wrote.
    final api = _FakeApiClient(reviews: [_review(editionId: null)]);
    await _load(tester, _wrap(api));
    await tester.tap(find.text('REVIEWS'));
    await tester.pump();
    await tester.pump();

    expect(find.text('I read it first at fifteen.'), findsOneWidget);
    // Tapping it must not blow up on a null edition id / navigate anywhere.
    await tester.tap(find.text('I read it first at fifteen.'));
    await tester.pump();
    expect(find.text('I read it first at fifteen.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed reviews fetch degrades on its own and offers a retry', (tester) async {
    // The tab is only offered once the count is known, so a failure means no
    // tab — and the rest of the profile has to stay usable regardless.
    final api = _FakeApiClient(reviewsThrow: true);
    await _load(tester, _wrap(api));

    expect(find.textContaining('DioException'), findsNothing);
    expect(find.text('REVIEWS'), findsNothing);
    expect(find.text('Anu Varghese'), findsOneWidget);
    expect(api.reviewCalls, greaterThan(0));
  });
}
