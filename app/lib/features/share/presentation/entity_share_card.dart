import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/widgets/net_image.dart';

/// The shareable card for an author or publisher — mirrors [BookShareCard] so a
/// shared author/publisher looks the part: their portrait/logo, name, a subtitle
/// (works/titles count), and the Kitabi mark. Fixed width so it rasterises
/// identically to its on-screen preview.
class EntityShareCard extends StatelessWidget {
  const EntityShareCard({
    super.key,
    required this.eyebrow,
    required this.name,
    required this.subtitle,
    required this.imageUrl,
    required this.circular,
  });

  final String eyebrow;
  final String name;
  final String subtitle;
  final String? imageUrl;

  /// Author portraits render as a circle; publisher logos as a rounded square.
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Container(
      width: 320,
      padding: EdgeInsets.fromLTRB(16, 16, 16, 13),
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
            eyebrow,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
              color: AppColors.oxblood,
            ),
          ),
          SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _Avatar(imageUrl: imageUrl, initial: initial, circular: circular),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: AppColors.ink, height: 1.2),
                    ),
                    SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 11),
          Container(height: 1, color: AppColors.line),
          SizedBox(height: 9),
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
                    child: Icon(Icons.menu_book, size: 10, color: AppColors.paper),
                  ),
                  SizedBox(width: 5),
                  Text(
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
                style: TextStyle(fontSize: 8, color: AppColors.inkSoft),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.imageUrl, required this.initial, required this.circular});

  final String? imageUrl;
  final String initial;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    const size = 56.0;
    final radius = BorderRadius.circular(circular ? size : 8);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.goldSoft,
        borderRadius: radius,
        image: imageUrl != null
            ? DecorationImage(image: netImageProvider(imageUrl!), fit: BoxFit.cover)
            : null,
      ),
      child: imageUrl == null
          ? Text(
              initial,
              style: TextStyle(
                color: Color(0xFF8F681E),
                fontWeight: FontWeight.w700,
                fontSize: 22,
              ),
            )
          : null,
    );
  }
}
