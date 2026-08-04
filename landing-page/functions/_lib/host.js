// One site, one hostname.
//
// www.kitabi.in was serving the ENTIRE site byte-identical to the apex, at
// HTTP 200, with `index, follow` — a complete duplicate host, its own
// robots.txt and all (measured 4 Aug 2026, while preparing the Search Console
// submission). The canonical tag on every page already pointed at the apex, so
// Google would most likely have consolidated the two; but "most likely" is not
// how you want the question settled. A duplicate host splits crawl budget,
// lets stray inbound links accumulate on the wrong hostname, and turns Search
// Console into two properties reporting on one site.

const CANONICAL_HOST = 'kitabi.in';

// Exact hosts only. Preview deployments (*.pages.dev) and localhost must keep
// working untouched, so this is a set membership test rather than a
// `startsWith('www.')` heuristic.
const REDIRECT_HOSTS = new Set(['www.kitabi.in']);

// Apple does NOT follow redirects when fetching apple-app-site-association — a
// redirected association file reads as no association at all, and iOS only
// re-checks at install, so the breakage is invisible for weeks and unfixable
// for anyone who already installed. Nothing declares www today (the live AASA
// binds the apex, and the string "www.kitabi.in" appears nowhere in this repo),
// so this exclusion is belt-and-braces. It stays because the cost of being
// wrong is asymmetric — the same reasoning as the asset allowlist in
// [[path]].js, and this project has already been bitten once by a redirect
// interacting with app associations.
const NEVER_REDIRECT = '/.well-known/';

/**
 * The canonical URL for a request, or null if it is already on the right host.
 *
 * Pure and string-in/string-out so it can be tested without a runtime; the
 * middleware turns a non-null answer into a 301.
 */
export function canonicalHostUrl(href) {
  const url = new URL(href);
  if (!REDIRECT_HOSTS.has(url.hostname)) return null;
  if (url.pathname.startsWith(NEVER_REDIRECT)) return null;
  // Assembled from parts rather than by mutating `url` — mutation depends on
  // the URL implementation keeping href in sync with hostname, which is an
  // implementation detail to lean on for something that must never break.
  // Hard-coding https also collapses a hop: http://www.… would otherwise go
  // http→https on www, then www→apex. One 301 instead of two.
  return `https://${CANONICAL_HOST}${url.pathname}${url.search}${url.hash}`;
}
