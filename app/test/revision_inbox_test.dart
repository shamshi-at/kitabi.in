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

  @override
  Future<List<Map<String, dynamic>>> pendingRevisions() async => pending;

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
}
