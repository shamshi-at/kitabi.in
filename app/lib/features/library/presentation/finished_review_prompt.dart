import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/haptics.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/sheet_grabber.dart';
import '../../../data/db/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/sync/sync_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../catalog/providers/catalog_providers.dart';
import '../providers/library_providers.dart';

/// The one gentle nudge to review a book the moment it is finished.
///
/// It lived on the book page's reading card, so it only ever fired on the one
/// finish the book page performs: tapping "Read" in the status row. Every
/// other way a book becomes finished — the timer's "I finished the book", the
/// quick-stop sheet's tick, and above all simply *typing the last page*, which
/// [autoFinishIfOnLastPage] has always treated as finishing it — marked the
/// book read in silence (owner report, 3 Sep 2026). Finishing a book is one
/// moment with several doors, and the nudge belongs to the moment.
///
/// Takes a [ProviderContainer] and a context to show from rather than a
/// `WidgetRef`, for the same reason [markBookFinished] takes handles: the
/// surfaces that finish a book are mostly surfaces that *disappear* when they
/// do — the mini-bar unmounts the instant a sitting stops, and the timer face
/// leaves for the book page. A container and a root-navigator context outlive
/// all of them (the 19 Jul and 31 Jul 2026 lessons).
///
/// Silent when there is nothing to gain by asking: no work to attach a review
/// to, or a *review* already written. Never irritate a reader who has already
/// said their piece — but a star rating alone is not their piece. It used to
/// count as one, and that made the nudge vanish for exactly the readers most
/// likely to write: anyone who rates a book while still reading it (owner
/// report, 6 Sep 2026 — "Marked as Read" from the timer's wax-seal face, and
/// no question followed). A rated, unreviewed book now gets the sheet with its
/// stars already lit, and the ask is the words.
///
/// The existence check fails *open*: it exists to avoid nagging, so a lookup
/// that throws (a duplicated rating row from a two-device sync, say) must not
/// take the whole moment with it. Better one extra ask than a finish in silence.
/// [workId] and the three display fields are what the *caller* already knows.
/// The book page holds all four (the work id is in its own route), and the
/// catalog mirror is the fallback for the surfaces that hold only an entry id
/// — the timer, the quick-stop sheet, Home's pencil. Ratings and reviews
/// attach to the Work (CLAUDE.md rule 17), so with no work id from either
/// source there is nowhere to put a review and nothing to ask for.
Future<void> maybePromptForReview(
  BuildContext context,
  ProviderContainer container, {
  required String libraryEntryId,
  String? workId,
  String? title,
  String? author,
  String? coverUrl,
}) async {
  final db = container.read(appDatabaseProvider);
  // Straight from Drift, never a stream provider: this runs at the end of a
  // flow on screens that may never have listened to one, and an autoDispose
  // read with no listener hands back nothing (19 Jul 2026).
  final entry = await db.libraryEntriesDao.getById(libraryEntryId);
  if (entry == null) return;
  final book = await db.cachedBooksDao.getByEditionId(entry.editionId);
  final work = workId ?? book?.workId;
  if (work == null) return;

  // Repositories directly, not the autoDispose providers' `.future` — a read
  // without a listener can be disposed before it resolves.
  Rating? rating;
  try {
    final reviewsRepo = await container.read(reviewsRepositoryProvider.future);
    final ratingsRepo = await container.read(ratingsRepositoryProvider.future);
    final review = await reviewsRepo.watchForWork(work).first;
    if (review != null) return;
    rating = await ratingsRepo.watchForWork(work).first;
  } catch (_) {
    // Fail open — see the doc comment. Nothing to do with the error itself:
    // the sheet's own rating row reads the repositories again and will show
    // the same trouble to the reader if it is real.
  }
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => FinishedReviewSheet(
      workId: work,
      initialStars: rating?.value,
      // The `extra` the review editor route needs to show which book it is
      // about — it renders a cover, so a missing one is a blank editor, not a
      // crash.
      reviewExtra: {
        'title': title ?? book?.title,
        'author': author ?? book?.authorNames,
        'coverUrl': coverUrl ?? book?.coverUrl,
      },
    ),
  );
}

/// The finished-reading popup — one tap on a star saves the rating right
/// there (and syncs before refreshing the hero's aggregate, same as the
/// review card's own rating row); "Write a review" goes deeper into the full
/// editor; "Not now" dismisses without friction. Never re-shown once a
/// review exists for this work (see [maybePromptForReview]); a rating given
/// earlier arrives as [initialStars].
///
/// A bottom sheet, not a snackbar — a snackbar times out mid-decision and its
/// one line can't carry a star row, so tapping a star straight away was never
/// possible.
class FinishedReviewSheet extends ConsumerStatefulWidget {
  const FinishedReviewSheet({
    super.key,
    required this.workId,
    required this.reviewExtra,
    this.initialStars,
  });

  final String workId;
  final Map<String, dynamic> reviewExtra;

  /// A rating the reader gave before finishing — lit from the start, so the
  /// sheet asks for words rather than pretending the stars are still open.
  final int? initialStars;

  @override
  ConsumerState<FinishedReviewSheet> createState() => _FinishedReviewSheetState();
}

class _FinishedReviewSheetState extends ConsumerState<FinishedReviewSheet> {
  late int _stars = widget.initialStars ?? 0;
  bool _saving = false;

  Future<void> _rate(int value) async {
    Haptics.selection();
    setState(() {
      _stars = value;
      _saving = true;
    });
    final repo = await ref.read(ratingsRepositoryProvider.future);
    await repo.setRating(widget.workId, value);
    ref.invalidate(ratingProvider(widget.workId));
    await ref.read(syncNowProvider)();
    ref.invalidate(publicReviewsProvider(widget.workId));
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final rated = widget.initialStars;
    return SafeArea(
      // Scrolls rather than overflows: a modal sheet is capped at nine
      // sixteenths of the screen, and on a short screen (or with a keyboard
      // up underneath) the fixed column ran 29px past it.
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 12, 24, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetGrabber(),
            SizedBox(height: 10),
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.goldSoft),
              child: Icon(Icons.auto_stories, color: AppColors.goldInk, size: 22),
            ),
            SizedBox(height: 14),
            Text(
              l10n.reviewFinishedTitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: 6),
            Text(
              rated == null
                  ? l10n.reviewFinishedSubtitle
                  : l10n.reviewFinishedSubtitleRated('★' * rated),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5, height: 1.4),
            ),
            SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 1; i <= 5; i++)
                  GestureDetector(
                    onTap: _saving ? null : () => _rate(i),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 5),
                      child: Icon(
                        i <= _stars ? Icons.star : Icons.star_border,
                        size: 32,
                        color: AppColors.gold,
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push(Routes.reviewEditorPath(widget.workId), extra: widget.reviewExtra);
                },
                child: Text(l10n.reviewFinishedAction),
              ),
            ),
            SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.reviewFinishedSkip, style: TextStyle(color: AppColors.inkSoft)),
            ),
          ],
        ),
      ),
    );
  }
}
