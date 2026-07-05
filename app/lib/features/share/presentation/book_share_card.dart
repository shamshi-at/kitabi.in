import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/typeset_cover.dart';
import '../../../l10n/app_localizations.dart';

/// The shareable book card (S6c / S13). Cover, title, author, a star rating
/// (the user's own when [personalRating] is set, otherwise the catalog
/// average), a blurb — or the user's review line in the personal-endorsement
/// variant — and the Kitabi mark. Fixed width so it renders identically whether
/// previewed on screen or captured to an image.
class BookShareCard extends StatelessWidget {
  const BookShareCard({
    super.key,
    required this.title,
    required this.author,
    required this.coverUrl,
    required this.blurb,
    this.personalRating,
    this.catalogRating,
    this.personalReview,
  });

  final String title;
  final String author;
  final String? coverUrl;
  final String? blurb;

  /// When set (personal-endorsement mode), the card shows the user's rating and
  /// their review line instead of the neutral blurb.
  final int? personalRating;
  final double? catalogRating;
  final String? personalReview;

  double? get _rating => personalRating?.toDouble() ?? catalogRating;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final rating = _rating;
    final showPersonalReview = personalRating != null && (personalReview?.trim().isNotEmpty ?? false);
    final body = showPersonalReview ? personalReview!.trim() : blurb?.trim();

    return Container(
      width: 320,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 13),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.shareEyebrow,
            style: const TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
              color: AppColors.oxblood,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TypesetCover(title: title, author: author, coverUrl: coverUrl, width: 54, height: 80),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: AppColors.ink, height: 1.2),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppColors.inkSoft),
                    ),
                    if (rating != null) ...[
                      const SizedBox(height: 6),
                      _Stars(
                        value: rating,
                        caption: personalRating != null
                            ? l10n.shareYourRating
                            : l10n.shareCatalogAvg,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (body != null && body.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              body,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: AppColors.inkSoft,
                fontStyle: showPersonalReview ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ],
          const SizedBox(height: 11),
          Container(height: 1, color: AppColors.line),
          const SizedBox(height: 9),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: AppColors.oxblood,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.menu_book, size: 10, color: AppColors.paper),
                  ),
                  const SizedBox(width: 5),
                  const Text(
                    'kitabi.in',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppColors.oxblood,
                    ),
                  ),
                ],
              ),
              Text(
                l10n.shareTagline,
                style: const TextStyle(fontSize: 8, color: AppColors.inkSoft),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.value, required this.caption});

  final double value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            value >= i
                ? Icons.star
                : (value >= i - 0.5 ? Icons.star_half : Icons.star_border),
            size: 14,
            color: AppColors.gold,
          ),
        const SizedBox(width: 5),
        Text(caption, style: const TextStyle(fontSize: 8, color: AppColors.inkSoft)),
      ],
    );
  }
}
