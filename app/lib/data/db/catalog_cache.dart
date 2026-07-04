import 'package:drift/drift.dart';

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
    ),
  );
}
