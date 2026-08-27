import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kitabi/core/widgets/report_review.dart';
import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/data/repositories/repositories.dart';
import 'package:kitabi/data/sync/sync_providers.dart';
import 'package:kitabi/l10n/app_localizations.dart';

/// The report-a-review flag: shows only on someone else's review, asks why,
/// sends the fixed wire token for the chosen reason, and tells the truth when
/// the report can't be sent — offline distinguished from a real failure.

class _Fake extends ApiClient {
  final calls = <(String, String?)>[];
  Object? throwOnReport;

  @override
  Future<void> reportReview(String reviewId, {String? reason}) async {
    if (throwOnReport != null) throw throwOnReport!;
    calls.add((reviewId, reason));
  }
}

Widget _app(_Fake fake, {required String reviewerId}) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(fake),
      sessionContextProvider.overrideWith(
        (ref) async => const SessionContext(userId: 'me', deviceId: 'd1'),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: ReportReviewButton(reviewId: 'r1', reviewerId: reviewerId),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('reporting another reader\'s review sends the wire token', (tester) async {
    final fake = _Fake();
    await tester.pumpWidget(_app(fake, reviewerId: 'other'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.flag_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Report this review'), findsOneWidget);

    await tester.tap(find.text('Spam or advertising'));
    await tester.pumpAndSettle();

    expect(fake.calls, [('r1', 'Spam')]);
    expect(find.text('Thanks — a moderator will take a look.'), findsOneWidget);
  });

  testWidgets('the flag never shows on the reader\'s own review', (tester) async {
    final fake = _Fake();
    await tester.pumpWidget(_app(fake, reviewerId: 'me'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.flag_outlined), findsNothing);
  });

  testWidgets('dismissing the sheet sends nothing', (tester) async {
    final fake = _Fake();
    await tester.pumpWidget(_app(fake, reviewerId: 'other'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.flag_outlined));
    await tester.pumpAndSettle();
    // Tap outside the sheet to dismiss it.
    await tester.tapAt(const Offset(200, 40));
    await tester.pumpAndSettle();

    expect(fake.calls, isEmpty);
  });

  testWidgets('offline is reported as offline, not as a generic failure', (tester) async {
    final fake = _Fake()
      ..throwOnReport = DioException(
        requestOptions: RequestOptions(path: '/catalog/reviews/r1/report'),
        type: DioExceptionType.connectionError,
      );
    await tester.pumpWidget(_app(fake, reviewerId: 'other'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.flag_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Something else'));
    await tester.pumpAndSettle();

    expect(
      find.text("You're offline — try reporting again once you're connected."),
      findsOneWidget,
    );
  });
}
