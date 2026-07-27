import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_states.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/db/database.dart';
import '../../../data/sync/sync_providers.dart';
import '../../../l10n/app_localizations.dart';

/// Surfaces the personal activity log (written server-side as a side effect of
/// mutations, pulled to the client). Private for now — the seed of the future
/// community feed (feature-map.md rule 15).
final activityLogProvider = StreamProvider.autoDispose<List<ActivityLogEntry>>((
  ref,
) {
  return ref.watch(appDatabaseProvider).activityLogDao.watchRecent();
});

/// What an activity row could resolve about its subject — the cached book (for
/// the title + cover the row leads with) and the route its tap opens. Either
/// can be null: an event for a book that was never cached still renders, as
/// the generic verb with no door.
class ActivityBookRef {
  const ActivityBookRef({this.title, this.author, this.coverUrl, this.route});

  final String? title;
  final String? author;
  final String? coverUrl;
  final String? route;
}

/// Resolves an event's entity back to its book *in the row itself* (a feed
/// with no subjects won't grow into the community feed — ux-review
/// 2026-07-28, #10). Family-cached per entry (drift rows have value
/// equality), so the list doesn't re-query on every rebuild.
final activityBookRefProvider = FutureProvider.autoDispose
    .family<ActivityBookRef, ActivityLogEntry>((ref, entry) async {
      final db = ref.watch(appDatabaseProvider);

      Future<CachedBook?> byEdition(String? editionId) async {
        if (editionId == null) return null;
        return db.cachedBooksDao.getByEditionId(editionId);
      }

      Future<CachedBook?> byEntry(String? entryId) async {
        if (entryId == null) return null;
        final e = await (db.select(
          db.libraryEntries,
        )..where((t) => t.id.equals(entryId))).getSingleOrNull();
        return byEdition(e?.editionId);
      }

      // Ratings/reviews attach to the Work (rule 17), so their cover lookup goes
      // through any cached edition of it.
      Future<CachedBook?> byWork(String? workId) async {
        if (workId == null) return null;
        return ((db.select(db.cachedBooks)
              ..where((t) => t.workId.equals(workId))
              ..limit(1)))
            .getSingleOrNull();
      }

      CachedBook? book;
      String? route;
      switch (entry.entityType) {
        case 'library_entry':
          book = await byEntry(entry.entityId);
          if (book != null) {
            route = Routes.bookDetailPath(book.workId, book.editionId);
          }
        case 'rating':
          String? workId;
          try {
            workId = (jsonDecode(entry.payload) as Map)['work_id'] as String?;
          } catch (_) {
            // Malformed payload — the row still renders, just without a door.
          }
          book = await byWork(workId);
          if (workId != null) route = '/b/$workId';
        case 'review':
          final r = await (db.select(
            db.reviews,
          )..where((t) => t.id.equals(entry.entityId))).getSingleOrNull();
          book = await byWork(r?.workId);
          if (r != null) route = '/b/${r.workId}';
        case 'lending_record':
          final lr = await (db.select(
            db.lendingRecords,
          )..where((t) => t.id.equals(entry.entityId))).getSingleOrNull();
          if (lr != null) {
            book =
                await byEdition(lr.editionId) ??
                await byEntry(lr.libraryEntryId);
            if (book != null) {
              route = Routes.bookDetailPath(book.workId, book.editionId);
            }
          }
      }
      return ActivityBookRef(
        title: book?.title,
        author: book?.authorNames,
        coverUrl: book?.coverUrl,
        route: route,
      );
    });

class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final activity = ref.watch(activityLogProvider);

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        foregroundColor: AppColors.ink,
        title: Text(
          l10n.activityTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      body: SafeArea(
        top: false,
        child: activity.when(
          loading: () => ListSkeleton(),
          error: (err, _) =>
              ErrorRetry(onRetry: () => ref.invalidate(activityLogProvider)),
          data: (entries) => entries.isEmpty
              ? EmptyState(
                  icon: Icons.history,
                  // Its own title — repeating the app-bar title directly
                  // beneath itself read as a stutter.
                  title: l10n.activityEmptyTitle,
                  body: l10n.activityEmpty,
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: AppColors.line),
                  itemBuilder: (context, i) => _ActivityRow(entry: entries[i]),
                ),
        ),
      ),
    );
  }
}

class _ActivityRow extends ConsumerWidget {
  const _ActivityRow({required this.entry});

  final ActivityLogEntry entry;

  IconData get _icon {
    switch (entry.eventType) {
      case 'added_book':
        return Icons.add_circle_outline;
      case 'finished_book':
        return Icons.check_circle_outline;
      case 'rated_book':
        return Icons.star_border;
      case 'wrote_review':
        return Icons.rate_review_outlined;
      case 'lent_book':
        return Icons.swap_horiz;
      default:
        return Icons.circle_outlined;
    }
  }

  /// The row's sentence — "Finished {title}" when the book resolved, the
  /// generic verb otherwise. An event type this app version doesn't know
  /// renders as a localized "Activity", never raw snake_case.
  String _label(AppLocalizations l10n, String? title) {
    switch (entry.eventType) {
      case 'added_book':
        return title != null
            ? l10n.activityAddedBookTitled(title)
            : l10n.activityAddedBook;
      case 'finished_book':
        return title != null
            ? l10n.activityFinishedBookTitled(title)
            : l10n.activityFinishedBook;
      case 'rated_book':
        return title != null
            ? l10n.activityRatedBookTitled(title)
            : l10n.activityRatedBook;
      case 'wrote_review':
        return title != null
            ? l10n.activityWroteReviewTitled(title)
            : l10n.activityWroteReview;
      case 'lent_book':
        return title != null
            ? l10n.activityLentBookTitled(title)
            : l10n.activityLentBook;
      default:
        return l10n.activityGeneric;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final bookRef = ref.watch(activityBookRefProvider(entry)).valueOrNull;
    final route = bookRef?.route;
    final days = DateUtils.dateOnly(
      DateTime.now(),
    ).difference(DateUtils.dateOnly(entry.occurredAt)).inDays;

    return InkWell(
      // No door, no tap — and no chevron pretending otherwise.
      onTap: route == null ? null : () => context.push(route),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            if (bookRef?.title != null)
              TypesetCover(
                title: bookRef!.title!,
                author: bookRef.author,
                coverUrl: bookRef.coverUrl,
                width: 24,
                height: 35,
              )
            else
              SizedBox(
                width: 24,
                child: Icon(_icon, size: 18, color: AppColors.oxblood),
              ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                _label(l10n, bookRef?.title),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              l10n.activityWhen(days),
              style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
            ),
            if (route != null) ...[
              SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 15, color: AppColors.inkSoft),
            ],
          ],
        ),
      ),
    );
  }
}
