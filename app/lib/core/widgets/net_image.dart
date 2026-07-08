import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// One disk cache for every remote image in the app (covers, portraits,
/// logos). `Image.network` only has the in-memory cache, so covers scrolled
/// out of a long grid were re-downloaded seconds later; this backs them with
/// flutter_cache_manager's LRU disk store — sized for a real library, with
/// eviction (oldest-used out first, and anything untouched for 60 days).
final kitabiImageCache = CacheManager(
  Config(
    'kitabiImages',
    stalePeriod: const Duration(days: 60),
    maxNrOfCacheObjects: 1500,
  ),
);

/// Drop-in for `Image.network` that reads/writes [kitabiImageCache].
Widget netImage(
  String url, {
  double? width,
  double? height,
  BoxFit? fit,
  Widget Function(BuildContext, Widget, ImageChunkEvent?)? loadingBuilder,
  Widget Function(BuildContext, Object, StackTrace?)? errorBuilder,
}) {
  return CachedNetworkImage(
    imageUrl: url,
    cacheManager: kitabiImageCache,
    width: width,
    height: height,
    fit: fit,
    // Cached hits paint immediately; only genuine downloads fade in.
    fadeInDuration: const Duration(milliseconds: 150),
    fadeOutDuration: const Duration(milliseconds: 100),
    progressIndicatorBuilder: loadingBuilder == null
        ? null
        : (context, _, progress) => loadingBuilder(
              context,
              const SizedBox.shrink(),
              progress.totalSize == null
                  ? null
                  : ImageChunkEvent(
                      cumulativeBytesLoaded: progress.downloaded,
                      expectedTotalBytes: progress.totalSize,
                    ),
            ),
    errorWidget: errorBuilder == null
        ? null
        : (context, _, error) => errorBuilder(context, error, null),
  );
}

/// Drop-in for `NetworkImage` (avatars via `foregroundImage`,
/// `DecorationImage`, `precacheImage`) backed by the same disk cache.
ImageProvider netImageProvider(String url) =>
    CachedNetworkImageProvider(url, cacheManager: kitabiImageCache);
