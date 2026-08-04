// The shared request→page pipeline every route uses.
//
// Keeps the routes to three lines each, and — more importantly — makes the
// failure behaviour uniform. Getting this wrong per-route is how a site ends up
// telling crawlers that real pages are gone during a five-minute outage.

import { cached, fetchPage } from './api.js';
import { notFound, unavailable } from './layout.js';
import { renderIndex } from './pages/discover.js';

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
/** Read a bounded page number from the query string. */
function pageParam(url) {
  const n = parseInt(url.searchParams.get('page') || '1', 10);
  return Number.isFinite(n) && n >= 1 && n <= 500 ? n : 1;
}

/** /search?q= — a plain GET form, so it works with JavaScript disabled. */
export function serveSearch(context, render) {
  const url = new URL(context.request.url);
  const q = (url.searchParams.get('q') || '').trim().slice(0, 200);
  if (!q) return Promise.resolve(permanentRedirect('/browse'));
  return cached(context, async () => {
    const { data } = await fetchPage(`/public/search?q=${encodeURIComponent(q)}`);
    // An unreachable API on search degrades to an empty result set rather than
    // a 503 — the reader still gets a usable page with somewhere to go.
    return render(data || { q, works: [], authors: [], publishers: [] });
  });
}

/** /browse?language=&form=&genre=&sort=&page= */
export function serveBrowse(context, render) {
  const url = new URL(context.request.url);
  const query = {};
  for (const key of ['language', 'form', 'genre', 'sort']) {
    const value = url.searchParams.get(key);
    if (value) query[key] = value;
  }
  const page = pageParam(url);
  const qs = new URLSearchParams({ ...query, page: String(page) }).toString();
  return cached(context, async () => {
    const { data } = await fetchPage(`/public/browse?${qs}`);
    if (!data) return unavailable();
    return render(data, { query });
  });
}

/** /genre/:slug, /language/:slug, /language/:slug/:form */
export function serveHub(context, kind, slug, render, { form = null } = {}) {
  const url = new URL(context.request.url);
  const params = new URLSearchParams({ page: String(pageParam(url)) });
  if (form) params.set('form', form);
  const path = `/public/hub/${kind}/${encodeURIComponent(slug)}?${params.toString()}`;
  return servePage(context, path, render, { what: kind });
}

/**
 * A directory page (/languages, /genres) built from the home payload's facet
 * counts — no extra endpoint needed, and it stays consistent with the grid on
 * the home page by construction.
 */
export function serveIndex(context, { title, description, kind, field, prefix, canonical }) {
  return cached(context, async () => {
    const { data } = await fetchPage('/public/home');
    if (!data) return unavailable();
    return renderIndex({
      title,
      description,
      kind,
      canonical,
      items: data[field] || [],
      hrefFor: (i) => `${prefix}${encodeURIComponent(i.slug)}`,
    });
  });
}

export async function legacyRedirect(context, kind, key) {
  const encoded = encodeURIComponent(key);
  const { data, missing } = await fetchPage(`/public/${kind}/${encoded}`);
  if (missing) return notFound({ what: kind });
  const slug = data?.slug || key;
  return permanentRedirect(`/${kind}/${encodeURIComponent(slug)}`);
}
