/// Public share links (S6c). These resolve to the landing page's shareable
/// detail pages (kitabi.in/b/:id, /a/:id, /p/:id) — each renders the book /
/// author / publisher and carries a "get the app" banner. The same short
/// paths are registered as in-app routes, so with universal/app links
/// configured a shared link opens the app when it's installed and the web
/// page otherwise.
library;

/// The landing-page origin. Overridable at build time so a staging web host
/// can be pointed at without a code change.
const String kShareBaseUrl = String.fromEnvironment(
  'SHARE_BASE_URL',
  defaultValue: 'https://kitabi.in',
);

String bookShareUrl(String workId) => '$kShareBaseUrl/b/$workId';

String authorShareUrl(String authorId) => '$kShareBaseUrl/a/$authorId';

String publisherShareUrl(String publisherId) => '$kShareBaseUrl/p/$publisherId';

/// A shared reading recap: `kitabi.in/reader/<handle>/recap/<key>`.
///
/// Named rather than tokenised (owner decision, 8 Sep 2026), which is what
/// makes it derivable — see `recapKeyFor` for the key grammar. Two consequences
/// worth holding on to. A reader with no handle has no recap link, so the share
/// sheet has to offer them one rather than a dead URL. And this path is
/// deliberately **not** claimed in `apple-app-site-association` or the Android
/// manifest: the recipient of a recap is a stranger, and the whole point is
/// that they land on a web page they can read, not a store listing.
String recapShareUrl(String username, String key) =>
    '$kShareBaseUrl/reader/${Uri.encodeComponent(username)}/recap/$key';
