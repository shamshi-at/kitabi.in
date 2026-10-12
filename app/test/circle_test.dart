import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kitabi/data/api/api_client.dart';
import 'package:kitabi/data/db/database.dart';
import 'package:kitabi/data/repositories/repositories.dart';
import 'package:kitabi/data/sync/library_dedupe.dart';
import 'package:kitabi/data/sync/sync_engine.dart';
import 'package:kitabi/features/circle/circle_models.dart';
import 'package:kitabi/features/circle/circle_providers.dart';
import 'package:kitabi/features/circle/widgets/circle_home_card.dart';
import 'package:kitabi/features/circle/widgets/circle_widgets.dart';
import 'package:kitabi/l10n/app_localizations.dart';
import 'package:sqlite3/sqlite3.dart';

/// "Your circle" (docs/circle-reading-mockups.html). The privacy rules live on
/// the server and are tested there (api/tests/test_circle.py); what the app
/// owns is parsing what the server sends, the per-book hide switch riding the
/// sync engine, and rendering nothing when there is nothing to say.

/// Fixtures written from `api/app/schemas/circle.py`, never from the widgets
/// that read them (CLAUDE.md, 9 Aug 2026: a fixture copied from the renderer
/// only proves the code agrees with itself).
const _anu = {
  'user_id': 'u-anu',
  'name': 'Anu Thomas',
  'avatar_url': null,
  'status': 'read',
  'read_count': 2,
  'finished_on': '2026-08-20',
  'started_on': null,
  'rating': 5,
  'review': 'The Bhima I never knew I needed.',
  'owns': false,
  'owned_edition_id': null,
  'owned_edition_label': null,
};
const _faisal = {
  'user_id': 'u-faisal',
  'name': 'Faisal P',
  'avatar_url': null,
  'status': null,
  'read_count': 0,
  'finished_on': null,
  'started_on': null,
  'rating': null,
  'review': null,
  'owns': true,
  'owned_edition_id': 'e-faisal',
  'owned_edition_label': 'DC Books, 2019',
};
const _workBody = {
  'invite': null,
  'people': [_anu, _faisal],
  'read_count': 1,
  'reading_count': 0,
  'owns_count': 1,
  'avg_rating': 5.0,
  'translations': [
    {
      'work_id': 'w-en',
      'edition_id': 'e-en',
      'title': 'Second Turn',
      'language': 'English',
      'read_count': 1,
      'names': ['Joseph Mathew'],
    },
  ],
};

class _SyncApi extends ApiClient {
  final List<Map<String, dynamic>> pushed = [];
  Map<String, dynamic> nextPull = {'changes': [], 'next_cursor': 0, 'has_more': false};

  @override
  Future<List<Map<String, dynamic>>> syncPush(List<Map<String, dynamic>> ops) async {
    pushed.addAll(ops);
    return [
      for (final op in ops) {'op_id': op['op_id'], 'status': 'applied', 'server_seq': 1},
    ];
  }

  @override
  Future<Map<String, dynamic>> syncPull({required int cursor, int limit = 500}) async => nextPull;

  @override
  Future<Map<String, dynamic>> getWorkByEdition(String editionId) async =>
      {'id': 'w', 'title': 't', 'authors': const [], 'genres': const [], 'editions': const []};
}

Map<String, dynamic> _pulledEntry({Object? circleHidden = _absent}) => {
      'id': 'le-1',
      'user_id': 'user-1',
      'edition_id': 'e-1',
      'status': 'read',
      'ownership': 'owned',
      'start_date': null,
      'finish_date': null,
      'current_page': null,
      'is_favorite': false,
      'notes': null,
      if (circleHidden != _absent) 'circle_hidden': circleHidden,
      'created_at': '2026-10-01T10:00:00+00:00',
      'updated_at': '2026-10-02T10:00:00+00:00',
      'deleted_at': null,
      'server_seq': 7,
    };
const _absent = Object();

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('parsing', () {
    test('a book page answer parses every field the server sends', () {
      final c = CircleWork.fromJson(Map<String, dynamic>.from(_workBody));
      expect(c.readers.single.name, 'Anu Thomas');
      expect(c.readers.single.readCount, 2);
      expect(c.readers.single.finishedOn, DateTime(2026, 8, 20));
      expect(c.owners.single.ownedEditionId, 'e-faisal');
      expect(c.owners.single.shortName, 'Faisal');
      expect(c.translations.single.editionId, 'e-en');
      expect(c.isEmpty, isFalse);
    });

    test('an invite-only answer and an empty one both render as nothing', () {
      expect(CircleWork.fromJson({'invite': 3}).invite, 3);
      expect(CircleWork.fromJson(const {}).isEmpty, isTrue);
    });

    test('an older payload missing fields degrades instead of throwing', () {
      final p = CirclePerson.fromJson({'user_id': 'u', 'name': '@anu'});
      expect(p.status, isNull);
      expect(p.owns, isFalse);
      expect(p.shortName, '@anu');
      expect(CircleSignal.parseAll({'invite': 2}), isEmpty);
      expect(CirclePickResponse.fromJson({'invite': null, 'pick': null}).pick, isNull);
    });

    test('ratings alone share nothing', () {
      expect(
        CircleSharing.fromMe({'circle_share_ratings': true}).any,
        isFalse,
      );
      expect(CircleSharing.fromMe({'circle_share_owned': true}).any, isTrue);
    });
  });

  group('the invitation', () {
    final now = DateTime(2026, 10, 13);
    test('shows until dismissed, then waits a week, then is gone after two', () {
      expect(InviteDismissals.parse(null).allowsShowing(now), isTrue);
      final once = InviteDismissals.parse(InviteDismissals.parse(null).bumped(now));
      expect(once.allowsShowing(now.add(const Duration(days: 3))), isFalse);
      expect(once.allowsShowing(now.add(const Duration(days: 8))), isTrue);
      final twice = InviteDismissals.parse(once.bumped(now));
      expect(twice.allowsShowing(now.add(const Duration(days: 400))), isFalse);
    });
  });

  group('keep this one to myself', () {
    late AppDatabase db;
    late _SyncApi api;
    const session = SessionContext(userId: 'user-1', deviceId: 'device-1');

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      api = _SyncApi();
    });
    tearDown(() => db.close());

    test('is written locally and pushed as an update', () async {
      final repo = LibraryRepository(db, session);
      final id = await repo.add(editionId: 'e-1');
      await repo.setCircleHidden(id, true);

      expect((await db.libraryEntriesDao.getById(id))!.circleHidden, isTrue);
      await SyncEngine(db, api).syncNow('user-1');
      final update = api.pushed.firstWhere((op) => op['op_type'] == 'update');
      expect(update['payload'], {'circle_hidden': true});
    });

    test('a pull from an API that predates the flag never un-hides a book', () async {
      await db.libraryEntriesDao.insertOne(
        LibraryEntriesCompanion.insert(
          id: 'le-1',
          userId: 'user-1',
          editionId: 'e-1',
          circleHidden: const Value(true),
        ),
      );
      api.nextPull = {
        'changes': [
          {'entity': 'library_entries', 'data': _pulledEntry()},
        ],
        'next_cursor': 7,
        'has_more': false,
      };
      await SyncEngine(db, api).syncNow('user-1');
      expect((await db.libraryEntriesDao.getById('le-1'))!.circleHidden, isTrue);

      api.nextPull = {
        'changes': [
          {'entity': 'library_entries', 'data': _pulledEntry(circleHidden: false)},
        ],
        'next_cursor': 8,
        'has_more': false,
      };
      await SyncEngine(db, api).syncNow('user-1');
      expect(
        (await db.libraryEntriesDao.getById('le-1'))!.circleHidden,
        isFalse,
        reason: 'an explicit answer from another device does apply',
      );
    });

    test('merging duplicate copies keeps a book hidden if either copy was', () async {
      for (final (id, hidden) in [('a', false), ('b', true)]) {
        await db.libraryEntriesDao.insertOne(
          LibraryEntriesCompanion.insert(
            id: id,
            userId: 'user-1',
            editionId: 'e-1',
            circleHidden: Value(hidden),
          ),
        );
      }
      await healDuplicateLibraryEntries(db, userId: 'user-1', deviceId: 'device-1');
      final survivor = await db.libraryEntriesDao.getByEditionId('e-1');
      expect(survivor!.circleHidden, isTrue);
    });
  });

  group('migration v14 → v15', () {
    late Directory dir;
    late File file;
    void device(Database db) => db.config.doubleQuotedStringLiterals = false;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('kitabi_circle_migration');
      file = File('${dir.path}/app.sqlite');
    });
    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('adds circle_hidden, keeps every entry, and is safe to re-run', () async {
      final seed = AppDatabase.forTesting(NativeDatabase(file, setup: device));
      await seed.customStatement('SELECT 1');
      await seed.customStatement('ALTER TABLE library_entries DROP COLUMN circle_hidden');
      await seed.customStatement(
        'INSERT INTO library_entries (id, user_id, created_at, updated_at, sync_status, '
        "edition_id) VALUES ('le-1', 'u1', 1, 1, 'synced', 'e-1')",
      );
      await seed.customStatement('PRAGMA user_version = 14');
      await seed.close();

      final db = AppDatabase.forTesting(NativeDatabase(file, setup: device));
      final entry = await db.libraryEntriesDao.getById('le-1');
      expect(entry, isNotNull);
      expect(entry!.circleHidden, isFalse);
      await db.close();

      // A half-applied upgrade (column there, version not stamped) replays.
      final again = AppDatabase.forTesting(NativeDatabase(file, setup: device));
      await again.customStatement('PRAGMA user_version = 14');
      await again.close();
      final reopened = AppDatabase.forTesting(NativeDatabase(file, setup: device));
      expect(await reopened.libraryEntriesDao.getById('le-1'), isNotNull);
      await reopened.close();
    });
  });

  group('widgets', () {
    Widget host(Widget child, List<Override> overrides) => ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: SingleChildScrollView(child: child)),
          ),
        );

    /// Fraunces isn't bundled in tests; its "not in assets" report is noise.
    /// Returns the restorer, which must run before the test body ends.
    void Function() quietFonts() {
      final original = reportTestException;
      reportTestException = (details, description) {
        if (details.exception.toString().contains('GoogleFonts')) return;
        original(details, description);
      };
      return () => reportTestException = original;
    }

    testWidgets('a search row names faces first', (tester) async {
      final signal = CircleSignal.fromJson({
        'read_count': 4,
        'readers': [_anu, {..._anu, 'user_id': 'u-l', 'name': 'Lakshmi R'}],
        'avg_rating': 4.5,
      });
      await tester.pumpWidget(host(CircleSearchLine(signal: signal), const []));
      expect(find.text('Anu, Lakshmi & 2 more read this · ★ 4.5'), findsOneWidget);
    });

    testWidgets('the book page card: headline, quote and the lending door', (tester) async {
      final restore = quietFonts();
      await tester.pumpWidget(host(
        const BookCircleSection(workId: 'w-1', title: 'Randamoozham'),
        [
          circleWorkProvider('w-1').overrideWith(
            (ref) async => CircleWork.fromJson(Map<String, dynamic>.from(_workBody)),
          ),
        ],
      ));
      await tester.pump();
      expect(find.text('1 of your connections has read this'), findsOneWidget);
      expect(find.text('“The Bhima I never knew I needed.”'), findsOneWidget);
      expect(find.text('Faisal has a copy'), findsOneWidget);
      expect(find.text('Ask to borrow ›'), findsOneWidget);
      expect(find.text('Joseph Mathew also read it as Second Turn'), findsOneWidget);
      restore();
    });

    testWidgets('silence is the empty state', (tester) async {
      for (final body in <CircleWork?>[null, const CircleWork(), const CircleWork(invite: 3)]) {
        await tester.pumpWidget(host(
          const BookCircleSection(workId: 'w-2', title: 'Manju'),
          [circleWorkProvider('w-2').overrideWith((ref) async => body)],
        ));
        await tester.pump();
        expect(find.text('YOUR CIRCLE'), findsNothing);
      }
    });

    testWidgets("Home's card is one sentence about one friend", (tester) async {
      final restore = quietFonts();
      final pick = CirclePickResponse.fromJson({
        'invite': null,
        'pick': {
          'kind': 'loved',
          'work': {
            'id': 'w-1',
            'title': 'Randamoozham',
            'first_publish_year': 1984,
            'aggregate_rating': 4.3,
            'authors': [
              {'id': 'a', 'name': 'M. T. Vasudevan Nair'},
            ],
            'edition': {'id': 'e-1', 'cover_url': null},
          },
          'person': {..._anu, 'owns': true, 'owned_edition_id': 'e-anu'},
          'people': [],
          'also_read_count': 3,
          'my_rating': null,
        },
      });
      await tester.pumpWidget(host(
        const CircleHomeCard(),
        [circlePickProvider.overrideWith((ref) async => pick)],
      ));
      await tester.pump();
      expect(find.text('FROM YOUR CIRCLE'), findsOneWidget);
      expect(find.text('Anu finished “Randamoozham”'), findsOneWidget);
      expect(find.text('Also read by 3 others in your circle'), findsOneWidget);
      expect(find.text('Ask Anu to lend'), findsOneWidget);
      restore();
    });

    testWidgets('no pick and nobody sharing: Home shows nothing', (tester) async {
      await tester.pumpWidget(host(
        const CircleHomeCard(),
        [
          circlePickProvider.overrideWith(
            (ref) async => const CirclePickResponse(invite: 0),
          ),
        ],
      ));
      await tester.pump();
      expect(find.text('YOUR CIRCLE'), findsNothing);
      expect(find.text('FROM YOUR CIRCLE'), findsNothing);
    });
  });
}
