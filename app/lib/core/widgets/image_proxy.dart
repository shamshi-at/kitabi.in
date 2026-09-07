import 'package:kitabi/core/share_links.dart';

/// The hosts kitabi.in's cover proxy (`landing-page/functions/img/c.js`) will
/// serve. Kept in step with that file's allowlist and with the web renderer's
/// `coverSrc` — a URL rewritten here that the proxy refuses renders as a
/// broken image, so the three lists must agree.
final RegExp _proxyable =
    RegExp(r'^https://(covers\.openlibrary\.org|[a-z0-9-]+\.supabase\.co)/');

/// Route a remote image through kitabi.in's edge cache instead of fetching
/// it from the bucket on every install.
///
/// Every catalogue cover, portrait and logo lives in the Supabase `covers`
/// bucket, and Supabase meters every byte that leaves it. The app's disk cache
/// makes a cover free the *second* time one device shows it, but the first
/// time on each install, each emulator and each reinstall still comes out of
/// that quota — which is how a 99 MB bucket produced 5.7 GB of egress in a
/// month (Supabase grace period, 7 Sep 2026). The web platform already serves
/// covers via `/img/c`, which fetches from the bucket about once per edge
/// location per year and hands the bytes on from Cloudflare, where they cost
/// nothing. This puts the app behind the same door.
///
/// Display-only: callers must never store the rewritten URL. The bucket URL is
/// the identity the API knows (`/catalog/cover-extract` accepts only bucket
/// URLs, the share card posts the original), and a proxied URL saved back to
/// the catalog would proxy a proxy.
///
/// Anything not on the allowlist is passed through untouched rather than
/// dropped — a cover from an unexpected host is still a cover.
String proxiedImageUrl(String url, {String base = kShareBaseUrl}) {
  if (!_proxyable.hasMatch(url)) return url;
  return '$base/img/c?u=${Uri.encodeComponent(url)}';
}
