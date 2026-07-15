import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/kitabi_linked_badge.dart';
import '../../../core/widgets/net_image.dart';

/// A catalog author row (portrait/monogram, name, primary language) — shared by
/// global search and the Discover/browse screen. The caller supplies [onTap]
/// so it can decide where to go (both send it to the author browse page).
class AuthorRowTile extends StatelessWidget {
  const AuthorRowTile({super.key, required this.author, required this.onTap});

  final Map<String, dynamic> author;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = author['name'] as String? ?? '';
    final imageUrl = author['image_url'] as String?;
    final language = author['primary_language'] as String?;
    final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final linked = author['linked_user_id'] != null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.goldSoft,
              foregroundImage: imageUrl != null ? netImageProvider(imageUrl) : null,
              child: imageUrl == null
                  ? Text(
                      initials,
                      style: const TextStyle(
                        color: Color(0xFF8F681E),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ),
                      if (linked) ...[
                        const SizedBox(width: 6),
                        const KitabiLinkedBadge(compact: true),
                      ],
                    ],
                  ),
                  if (language != null && language.isNotEmpty)
                    Text(language, style: TextStyle(color: AppColors.inkSoft, fontSize: 11)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: AppColors.inkSoft),
          ],
        ),
      ),
    );
  }
}

/// A catalog publisher row (logo/icon, name, primary language) — shared by
/// global search and the Discover/browse screen.
class PublisherRowTile extends StatelessWidget {
  const PublisherRowTile({super.key, required this.publisher, required this.onTap});

  final Map<String, dynamic> publisher;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = publisher['name'] as String? ?? '';
    final logoUrl = publisher['logo_url'] as String?;
    final language = publisher['primary_language'] as String?;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.line),
              ),
              child: logoUrl != null
                  ? netImage(
                      logoUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          Icon(Icons.business, color: AppColors.inkSoft, size: 16),
                    )
                  : Icon(Icons.business, color: AppColors.inkSoft, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  if (language != null && language.isNotEmpty)
                    Text(language, style: TextStyle(color: AppColors.inkSoft, fontSize: 11)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: AppColors.inkSoft),
          ],
        ),
      ),
    );
  }
}
