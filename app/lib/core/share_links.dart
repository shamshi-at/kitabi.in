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
