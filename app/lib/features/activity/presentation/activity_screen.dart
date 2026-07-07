import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_states.dart';
import '../../../data/db/database.dart';
import '../../../data/sync/sync_providers.dart';
import '../../../l10n/app_localizations.dart';

/// Surfaces the personal activity log (written server-side as a side effect of
/// mutations, pulled to the client). Private for now — the seed of the future
/// community feed (feature-map.md rule 15).
final activityLogProvider = StreamProvider.autoDispose<List<ActivityLogEntry>>((ref) {
  return ref.watch(appDatabaseProvider).activityLogDao.watchRecent();
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
        title: Text(l10n.activityTitle, style: Theme.of(context).textTheme.titleLarge),
      ),
      body: SafeArea(
        top: false,
        child: activity.when(
          loading: () => ListSkeleton(),
          error: (err, _) => ErrorRetry(onRetry: () => ref.invalidate(activityLogProvider)),
          data: (entries) => entries.isEmpty
              ? EmptyState(
                  icon: Icons.history,
                  title: l10n.activityTitle,
                  body: l10n.activityEmpty,
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.line),
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

  (IconData, String) _describe(AppLocalizations l10n) {
    switch (entry.eventType) {
      case 'added_book':
        return (Icons.add_circle_outline, l10n.activityAddedBook);
      case 'finished_book':
        return (Icons.check_circle_outline, l10n.activityFinishedBook);
      case 'rated_book':
        return (Icons.star_border, l10n.activityRatedBook);
      case 'wrote_review':
        return (Icons.rate_review_outlined, l10n.activityWroteReview);
      case 'lent_book':
        return (Icons.swap_horiz, l10n.activityLentBook);
      default:
        return (Icons.circle_outlined, entry.eventType);
    }
  }

  /// Resolve the event's entity back to a book route via the local DB —
  /// events reference the syncable rows (entries, ratings, reviews, loans),
  /// all of which lead to an edition or a work.
  Future<String?> _bookRoute(WidgetRef ref) async {
    final db = ref.read(appDatabaseProvider);

    Future<String?> byEdition(String? editionId) async {
      if (editionId == null) return null;
      final book = await db.cachedBooksDao.getByEditionId(editionId);
      return book == null ? null : Routes.bookDetailPath(book.workId, book.editionId);
    }

    Future<String?> byEntry(String? entryId) async {
      if (entryId == null) return null;
      final e = await (db.select(db.libraryEntries)..where((t) => t.id.equals(entryId)))
          .getSingleOrNull();
      return byEdition(e?.editionId);
    }

    switch (entry.entityType) {
      case 'library_entry':
        return byEntry(entry.entityId);
      case 'rating':
        final workId = (jsonDecode(entry.payload) as Map)['work_id'] as String?;
        return workId == null ? null : '/b/$workId';
      case 'review':
        final r = await (db.select(db.reviews)..where((t) => t.id.equals(entry.entityId)))
            .getSingleOrNull();
        return r == null ? null : '/b/${r.workId}';
      case 'lending_record':
        final lr = await (db.select(db.lendingRecords)..where((t) => t.id.equals(entry.entityId)))
            .getSingleOrNull();
        if (lr == null) return null;
        return await byEdition(lr.editionId) ?? byEntry(lr.libraryEntryId);
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final (icon, label) = _describe(l10n);
    final days = DateUtils.dateOnly(DateTime.now()).difference(DateUtils.dateOnly(entry.occurredAt)).inDays;

    return InkWell(
      onTap: () async {
        final route = await _bookRoute(ref);
        if (route != null && context.mounted) context.push(route);
      },
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.oxblood),
            SizedBox(width: 12),
            Expanded(
              child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            Text(
              l10n.activityWhen(days),
              style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
            ),
            SizedBox(width: 6),
            Icon(Icons.chevron_right, size: 15, color: AppColors.inkSoft),
          ],
        ),
      ),
    );
  }
}
