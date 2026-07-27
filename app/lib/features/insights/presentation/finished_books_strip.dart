import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/section_label.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../l10n/app_localizations.dart';
import '../period_summary.dart';

/// The books finished in the selected window, as covers rather than another
/// row of numbers — the answer to "which books, and how'd I rate them" reads
/// as richer without reading as busier (owner request, 27 Jul 2026). A star
/// badge only appears on a cover that was actually rated; an unrated finish
/// is just a plain cover, never a zero-star one. Horizontally scrolling, so
/// there's no separate "+N more" affordance to build or maintain.
class FinishedBooksStrip extends StatelessWidget {
  const FinishedBooksStrip({super.key, required this.books});

  final List<FinishedBookInfo> books;

  static const _coverWidth = 52.0;
  static const _coverHeight = 76.0;

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A plain "Finished" (no period wording): "Finished this 3 months"
        // conjugates badly across the windows, and the card's own eyebrow
        // already names the window right above.
        SectionLabel(l10n.insightsFinishedSection, padding: const EdgeInsets.only(bottom: 6)),
        _strip(),
      ],
    );
  }

  Widget _strip() {
    return SizedBox(
      height: _coverHeight + 6,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: books.length,
        separatorBuilder: (context, i) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final book = books[i];
          return GestureDetector(
            onTap: () => context.push(Routes.bookDetailPath(book.workId, book.editionId)),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                TypesetCover(
                  title: book.title,
                  author: book.author,
                  coverUrl: book.coverUrl,
                  width: _coverWidth,
                  height: _coverHeight,
                ),
                if (book.rating != null)
                  Positioned(
                    bottom: -4,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: AppColors.ink,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star, size: 8, color: AppColors.gold),
                            const SizedBox(width: 2),
                            Text(
                              '${book.rating}',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.paper,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
