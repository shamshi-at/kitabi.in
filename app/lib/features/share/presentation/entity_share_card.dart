import 'package:flutter/material.dart';

import '../../../core/widgets/net_image.dart';
import 'share_logo.dart';
import 'share_palette.dart';

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
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Container(
      width: 320,
      padding: EdgeInsets.fromLTRB(16, 16, 16, 13),
      decoration: BoxDecoration(
        color: ShareCardPalette.paper,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ShareCardPalette.gold),
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
              color: ShareCardPalette.oxblood,
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
                          ?.copyWith(color: ShareCardPalette.ink, height: 1.2),
                    ),
                    SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: ShareCardPalette.inkSoft),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 11),
          ShareCardFooter(),
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
        color: ShareCardPalette.goldSoft,
        borderRadius: radius,
        image: imageUrl != null
            ? DecorationImage(image: netImageProvider(imageUrl!), fit: BoxFit.cover)
            : null,
      ),
      child: imageUrl == null
          ? Text(
              initial,
              style: TextStyle(
                color: ShareCardPalette.goldInk,
                fontWeight: FontWeight.w700,
                fontSize: 22,
              ),
            )
          : null,
    );
  }
}
