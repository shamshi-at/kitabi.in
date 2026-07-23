import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/features/catalog/presentation/revision_inbox_screen.dart';
import 'package:kitabi/l10n/app_localizations.dart';

class _FakeApiClient extends ApiClient {
  List<Map<String, dynamic>> pending = [];
  String? approvedId;
  String? rejectedId;

  List<Map<String, dynamic>> claims = [];
  String? withdrawnId;

  @override
  Future<List<Map<String, dynamic>>> pendingRevisions() async => pending;

  @override
  Future<List<Map<String, dynamic>>> myAuthorClaims() async => claims;

  @override
  Future<void> withdrawAuthorClaim(String claimId) async {
    withdrawnId = claimId;
    claims = [];
  }

  @override
  Future<void> approveRevision(String revisionId) async {
    approvedId = revisionId;
    pending = [];
  }

  @override
  Future<void> rejectRevision(String revisionId) async {
    rejectedId = revisionId;
    pending = [];
  }
}

Widget _wrap(_FakeApiClient fake) {
  return ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(fake)],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const RevisionInboxScreen(),
    ),
  );
}

Map<String, dynamic> _revision() => {
      'id': 'rev-1',
      'work_id': 'w-1',
      'work_title': 'ചെമ്മീൻ',
      'proposed_by_name': 'Anu',
      'payload': {'description': 'A better blurb.', 'first_publish_year': 1956},
      'status': 'pending',
      'created_at': '2026-07-08T10:00:00Z',
    };

void main() {
  testWidgets('inbox lists a pending edit with its changes and proposer', (tester) async {
    final fake = _FakeApiClient()..pending = [_revision()];
    await tester.pumpWidget(_wrap(fake));
    await tester.pumpAndSettle();

    expect(find.text('ചെമ്മീൻ'), findsOneWidget);
    expect(find.text('Suggested by Anu'), findsOneWidget);
    expect(find.textContaining('A better blurb.', findRichText: true), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
  });

  testWidgets('approving applies the edit and empties the inbox', (tester) async {
    final fake = _FakeApiClient()..pending = [_revision()];
    await tester.pumpWidget(_wrap(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();

    expect(fake.approvedId, 'rev-1');
    expect(find.text('Edit approved and applied.'), findsOneWidget);
    expect(find.textContaining('Nothing to review'), findsOneWidget);
  });

  testWidgets('rejecting discards the edit', (tester) async {
    final fake = _FakeApiClient()..pending = [_revision()];
    await tester.pumpWidget(_wrap(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();

    expect(fake.rejectedId, 'rev-1');
    expect(find.text('Edit rejected.'), findsOneWidget);
  });

  // A filed "This is me" claim had nowhere to show and no way back — the
  // button said "pending review", this screen listed revisions only, and a
  // mis-tap was permanent (owner report, 23 Jul 2026).
  Map<String, dynamic> claim({String status = 'pending'}) => {
        'id': 'claim-1',
        'author_id': 'a-1',
        'author_name': 'Kamala Das',
        'status': status,
        'created_at': '2026-07-23T10:00:00Z',
      };

  testWidgets('a pending claim is listed with a way to withdraw it', (tester) async {
    final fake = _FakeApiClient()..claims = [claim()];
    await tester.pumpWidget(_wrap(fake));
    await tester.pumpAndSettle();

    expect(find.text('YOUR AUTHOR CLAIMS'), findsOneWidget);
    expect(find.text('Kamala Das'), findsOneWidget);
    expect(find.text('Waiting for review'), findsOneWidget);
    expect(find.text('Withdraw'), findsOneWidget);
  });

  testWidgets('withdrawing asks first, then removes the claim', (tester) async {
    final fake = _FakeApiClient()..claims = [claim()];
    await tester.pumpWidget(_wrap(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Withdraw'));
    await tester.pumpAndSettle();
    expect(find.text('Withdraw this claim?'), findsOneWidget);

    await tester.tap(find.text('Withdraw').last);
    await tester.pumpAndSettle();

    expect(fake.withdrawnId, 'claim-1');
    expect(find.text('Claim withdrawn'), findsOneWidget);
    expect(find.text('Kamala Das'), findsNothing);
  });

  testWidgets('a decided claim shows its outcome and cannot be withdrawn', (tester) async {
    final fake = _FakeApiClient()..claims = [claim(status: 'rejected')];
    await tester.pumpWidget(_wrap(fake));
    await tester.pumpAndSettle();

    expect(find.text('Not approved'), findsOneWidget);
    expect(find.text('Withdraw'), findsNothing);
  });
}
