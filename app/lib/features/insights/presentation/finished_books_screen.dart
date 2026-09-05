import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../library/book_browse_context.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../data/db/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../period.dart';
import '../providers/insights_providers.dart';
import 'almanac_widgets.dart';

/// What the Books finished row opens (B4): the list the number was always
/// standing in for — every finished book in the window with started →
/// finished and the days between. Every row is a door to the book page, and
/// the goal's ✎ lives here (the almanac has no ring, so "of 30" is edited
/// where the 30 is explained).
class FinishedBooksArgs {
  const FinishedBooksArgs({required this.range, this.year, this.showGoal = false, this.customTitle});

  final PeriodRange range;

  /// Set for the year window — null inside it means all time. Only drives
  /// the title; the [range] does the filtering.
  final int? year;
  final bool showGoal;

  /// A non-year window's own title ("Finished · August") — the same page
  /// serves Month and the 3/6-month stretches, filtered.
  final String? customTitle;
}

class FinishedBooksScreen extends ConsumerWidget {
  const FinishedBooksScreen({super.key, this.args});

  final FinishedBooksArgs? args;

  Future<void> _editGoal(BuildContext context, WidgetRef ref, int current) async {
    final l10n = AppLocalizations.of(context)!;
    final repo = await ref.read(libraryRepositoryProvider.future);
    if (!context.mounted) return;
    final controller = TextEditingController(text: '$current');
    final goal = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.insightsGoalDialogTitle),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.insightsGoalDialogHint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.bookCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text)),
            child: Text(l10n.bookSave),
          ),
        ],
      ),
    );
    if (goal == null || goal <= 0) return;
    await repo.setReadingGoal(goal);
    ref.invalidate(readingGoalProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    // A guard, not a path: this screen is only ever pushed from Insights with
    // args in hand — but a route must not crash without them.
    final effective = args ??
        FinishedBooksArgs(
          range: rangeFor(InsightsPeriod.year, year: DateTime.now().year),
          year: DateTime.now().year,
          showGoal: true,
        );
    final hits = ref.watch(libraryWithBooksProvider).valueOrNull ?? const <LibraryHit>[];
    final ratings = ref.watch(ratingsByWorkIdProvider).valueOrNull ?? const <String, int>{};
    final goal = ref.watch(readingGoalProvider).valueOrNull ?? 30;

    // Same finished-on fallback as computeInsights — a read book with no
    // explicit finish date lands on when its row was last touched, so it
    // appears in some window instead of vanishing.
    DateTime finishedOn(LibraryHit h) => h.entry.finishDate ?? h.entry.updatedAt;
    final finished = hits
        .where((h) => h.entry.status == 'read' && effective.range.contains(finishedOn(h)))
        .toList()
      ..sort((a, b) => finishedOn(b).compareTo(finishedOn(a)));

    final title = effective.customTitle ??
        (effective.year != null
            ? l10n.insightsFinishedInYear(effective.year!)
            : l10n.insightsFinishedAllTime);

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        title: Text(title),
        actions: [
          if (effective.showGoal)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: InkWell(
                onTap: () => _editGoal(context, ref, goal),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Row(
                    children: [
                      Text(
                        l10n.insightsGoalHeader(goal).toUpperCase(),
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: AppColors.inkSoft,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.edit, size: 13, color: AppColors.oxblood),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          AlmanacHead(
            left: l10n.insightsFinishedHeader(finished.length),
            right: effective.showGoal && effective.year == DateTime.now().year
                ? _paceNote(l10n, finished.length, goal)
                : null,
          ),
          if (finished.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  l10n.insightsFinishedEmpty,
                  style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                ),
              ),
            )
          else
            for (final hit in finished)
              _FinishedRow(
                hit: hit,
                rating: ratings[hit.book.workId],
                finishedOn: finishedOn(hit),
                onTap: () => context.push(
                  Routes.bookDetailPath(hit.book.workId, hit.book.editionId),
                  // The finished list, newest first, so the page swipes
                  // through it the way the library grid does.
                  extra: BookBrowseContext.fromHits(finished),
                ),
              ),
        ],
      ),
    );
  }

  String? _paceNote(AppLocalizations l10n, int read, int goal) {
    final now = DateTime.now();
    final dayOfYear = now.difference(DateTime(now.year)).inDays + 1;
    final expected = (goal * dayOfYear / 365).floor();
    final diff = read - expected;
    if (diff > 0) return l10n.insightsAhead(diff);
    if (diff < 0) return l10n.insightsBehind(-diff);
    return l10n.insightsOnTrack;
  }
}

class _FinishedRow extends StatelessWidget {
  const _FinishedRow({
    required this.hit,
    required this.rating,
    required this.finishedOn,
    required this.onTap,
  });

  final LibraryHit hit;
  final int? rating;
  final DateTime finishedOn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final fmt = DateFormat('d MMM');
    final start = hit.entry.startDate;

    final String dateLine;
    final String subLine;
    if (start != null && !finishedOn.isBefore(start)) {
      dateLine = '${fmt.format(start)} → ${fmt.format(finishedOn)}';
      final days = finishedOn.difference(start).inDays + 1;
      subLine = l10n.insightsFinishedDays(days);
    } else {
      dateLine = l10n.insightsFinishedOnDate(fmt.format(finishedOn));
      subLine = l10n.insightsStartNotRecorded;
    }

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            TypesetCover(
              title: hit.book.title,
              author: hit.book.authorNames.split(',').first.trim(),
              coverUrl: hit.book.coverUrl,
              width: 26,
              height: 38,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hit.book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.fraunces(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.oxblood,
                    ),
                  ),
                  Text(
                    hit.book.authorNames.split(',').first.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  dateLine,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.ink),
                ),
                const SizedBox(height: 1),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      subLine,
                      style: TextStyle(
                        fontSize: 9,
                        color: AppColors.inkSoft,
                        fontStyle:
                            start == null ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                    if (rating case final stars?) ...[
                      Text(' · ', style: TextStyle(fontSize: 9, color: AppColors.inkSoft)),
                      for (var i = 1; i <= 5; i++)
                        Icon(
                          i <= stars ? Icons.star : Icons.star_border,
                          size: 9,
                          color: AppColors.gold,
                        ),
                    ] else ...[
                      Text(
                        ' · ${l10n.insightsNotRated}',
                        style: TextStyle(fontSize: 9, color: AppColors.inkSoft),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
