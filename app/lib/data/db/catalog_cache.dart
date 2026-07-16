import 'package:drift/drift.dart';

import '../api/api_client.dart';
import 'database.dart';

/// Writes the catalog fields a library-grid card needs into the local
/// read-only cache (CLAUDE.md rule 2: fetched/cached for offline reading).
/// Called whenever the app has just fetched full Work+Edition data anyway —
/// adding a book to the library is the natural, cheap moment to do this,
/// since by definition the data was just loaded from the API.
Future<void> cacheBookForOffline(
  AppDatabase db,
  Map<String, dynamic> work,
  Map<String, dynamic> edition,
) async {
  final authors = (work['authors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  final genres = (work['genres'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  final publisher = edition['publisher'] as Map<String, dynamic>?;
  final series = edition['series'] as Map<String, dynamic>?;

  await db.cachedBooksDao.upsert(
    CachedBooksCompanion.insert(
      editionId: edition['id'] as String,
      workId: work['id'] as String,
      title: work['title'] as String,
      subtitle: Value(work['subtitle'] as String?),
      authorNames: authors.map((a) => a['name'] as String).join(', '),
      publisherName: Value(publisher?['name'] as String?),
      seriesName: Value(series?['name'] as String?),
      seriesNumber: Value(edition['series_number'] as int?),
      isbn: Value(edition['isbn'] as String?),
      language: Value(edition['language'] as String?),
      pageCount: Value(edition['page_count'] as int?),
      format: Value(edition['format'] as String?),
      coverUrl: Value(edition['cover_url'] as String?),
      firstPublishYear: Value(work['first_publish_year'] as int?),
      genreNames: Value(genres.map((g) => g['name'] as String).join(', ')),
      form: Value(work['form'] as String?),
    ),
  );
}

/// Hydrate the catalog data for borrowed books so they can render (cover, title,
/// author). A borrowed book was never added by this reader — it arrived as a
/// mirrored loan record carrying only an edition id — so it isn't in the cache.
/// Fetches the Work by edition and caches it. Online-only; failures are skipped.
Future<int> cacheBorrowedBooks(AppDatabase db, ApiClient api) async {
  final editionIds = await db.lendingRecordsDao.activeBorrowedEditionIds();
  var cached = 0;
  for (final editionId in editionIds) {
    if (await db.cachedBooksDao.getByEditionId(editionId) != null) continue;
    try {
      final work = await api.getWorkByEdition(editionId);
      final editions = (work['editions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final edition = editions.firstWhere(
        (e) => e['id'] == editionId,
        orElse: () => editions.isNotEmpty ? editions.first : <String, dynamic>{},
      );
      if (edition.isNotEmpty) {
        await cacheBookForOffline(db, work, edition);
        cached++;
      }
    } catch (_) {
      // offline or gone — try again next refresh
    }
  }
  return cached;
}

/// Hydrate the catalog cache for OWNED library entries with no cached-book
/// row — the fresh-install gap: a sync pull restores `library_entries`
/// (Layer 2, synced) but `cached_books` is a device-local Layer-1 cache, so
/// on a new device every entry silently vanished from the grid's inner join
/// (home counted 5 books while the library showed 0). Fetches each missing
/// edition's Work and caches it. Cheap when nothing is missing (local reads
/// only); online-only for the fetches — failures skip and retry next call.
Future<int> cacheMissingLibraryBooks(AppDatabase db, ApiClient api) async {
  final entries = await db.libraryEntriesDao.watchActive().first;
  final editionIds = {for (final e in entries) e.editionId};
  var cached = 0;
  for (final editionId in editionIds) {
    if (await db.cachedBooksDao.getByEditionId(editionId) != null) continue;
    try {
      final work = await api.getWorkByEdition(editionId);
      final editions = (work['editions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final edition = editions.firstWhere(
        (e) => e['id'] == editionId,
        orElse: () => editions.isNotEmpty ? editions.first : <String, dynamic>{},
      );
      if (edition.isNotEmpty) {
        await cacheBookForOffline(db, work, edition);
        cached++;
      }
    } catch (_) {
      // offline or gone — try again next refresh
    }
  }
  return cached;
}

/// Re-fetch catalog data for every cached book that still has no cover and
/// refresh its cache row — so covers added upstream after a book was cached
/// (e.g. a metadata backfill) show up in the grid/home without re-adding the
/// book. Online-only: each fetch that fails (offline, not found) is skipped, so
/// this is safe to call opportunistically. Returns how many gained a cover.
///
/// Bounded by design: it only touches cover-less rows, so once a book has a
/// cover it's never re-fetched. Works are de-duplicated so a multi-edition Work
/// is fetched once. SCALE: fine for a personal library; if it ever grows large,
/// batch the fetch behind one endpoint.
Future<int> refreshMissingCovers(AppDatabase db, ApiClient api) async {
  final missing = await db.cachedBooksDao.withoutCover();
  if (missing.isEmpty) return 0;

  final missingEditionIds = {for (final b in missing) b.editionId};
  final workIds = {for (final b in missing) b.workId};
  var gained = 0;

  for (final workId in workIds) {
    Map<String, dynamic> work;
    try {
      work = await api.getWork(workId);
    } catch (_) {
      continue; // offline or gone — leave the cache as-is
    }
    final editions = (work['editions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final edition in editions) {
      if (!missingEditionIds.contains(edition['id'])) continue;
      await cacheBookForOffline(db, work, edition);
      if (edition['cover_url'] != null) gained++;
    }
  }
  return gained;
}
