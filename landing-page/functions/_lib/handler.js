// The shared request→page pipeline every route uses.
//
// Keeps the routes to three lines each, and — more importantly — makes the
// failure behaviour uniform. Getting this wrong per-route is how a site ends up
// telling crawlers that real pages are gone during a five-minute outage.

import { cached, fetchPage } from './api.js';
import { notFound, unavailable } from './layout.js';

/**
 * Fetch a /public/* payload and render it.
 *
 * The three outcomes are deliberately distinct:
 *   * data          → render, cache
 *   * missing (404) → a real 404 + noindex, so a dead link leaves the index
 *   * anything else → 503 + Retry-After, NEVER a 404. A blip must not read as
 *     "this book no longer exists", or one bad minute deindexes the site.
 */
export function servePage(context, apiPath, render, { what = 'page' } = {}) {
  return cached(context, async () => {
    const { data, missing } = await fetchPage(apiPath);
    if (data) return render(data);
    return missing ? notFound({ what }) : unavailable();
  });
}

/** 301, cached for a day so the lookup behind it isn't repeated per visitor. */
export function permanentRedirect(location) {
  return new Response(null, {
    status: 301,
    headers: { Location: location, 'Cache-Control': 'public, max-age=86400' },
  });
}

/**
 * Send a legacy /b/, /a/, /p/ UUID link to its canonical slug URL.
 *
 * Resolves the slug so the reader lands on a readable address rather than a
 * UUID that then canonicalises elsewhere. If the API can't be reached we still
 * redirect — to the UUID form, which renders fine — because a share link that
 * has worked for months must not start failing because of a blip. The only case
 * that 404s is one the API positively confirms is gone.
 */
export async function legacyRedirect(context, kind, key) {
  const encoded = encodeURIComponent(key);
  const { data, missing } = await fetchPage(`/public/${kind}/${encoded}`);
  if (missing) return notFound({ what: kind });
  const slug = data?.slug || key;
  return permanentRedirect(`/${kind}/${encodeURIComponent(slug)}`);
}
