// Talking to the catalog API from the edge, and caching what comes back.
//
// The whole performance story lives here. A page render is ONE upstream call
// (the /public/* endpoints are page-shaped for exactly this reason), and the
// rendered HTML is cached at the edge so a crawler burst hits Cloudflare rather
// than Railway in Singapore. Measured baseline before any of this: 620ms TTFB
// for a shell that contained no book content, plus a 310ms client-side fetch.

const API = 'https://api.kitabi.in';

// Short fresh window, long stale window. A page stays instant even when the
// entry has gone cold and refreshes behind the request; catalog edits reach
// readers within the minute via the purge hook rather than by making every
// visitor wait for revalidation.
export const CACHE_CONTROL = 'public, max-age=60, s-maxage=300, stale-while-revalidate=86400';

/**
 * Fetch a /public/* page payload.
 *
 * Returns { data, missing }. `missing` is true ONLY when the API answered
 * definitively that there is no such thing (404/410). A 5xx, a timeout or a
 * network blip leaves it false — that distinction is the whole point: a missing
 * book should tell a crawler "gone", but one bad minute at the origin must not,
 * or an outage would deindex the entire site.
 */
export async function fetchPage(path, { timeoutMs = 8000 } = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(`${API}${path}`, {
      headers: { Accept: 'application/json' },
      signal: controller.signal,
      // Let Cloudflare cache the upstream JSON too, so two page types that need
      // the same author's data share one origin fetch.
      cf: { cacheTtl: 60, cacheEverything: true },
    });
    if (res.ok) return { data: await res.json(), missing: false };
    return { data: null, missing: res.status === 404 || res.status === 410 };
  } catch (_) {
    return { data: null, missing: false };
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Serve `render()` through the edge cache.
 *
 * Cache-first with a background revalidate: on a hit we return immediately and,
 * if the entry is past its fresh window, refresh it after the response has been
 * sent (waitUntil) so the *next* visitor gets new content and this one waits for
 * nothing. That is what turns a 620ms origin round trip into a ~40ms edge hit
 * for everyone after the first.
 */
export async function cached(context, render) {
  const { request, waitUntil } = context;
  // Only GET is cacheable, and only same-origin page requests reach here.
  if (request.method !== 'GET') return render();

  const cache = caches.default;
  const key = new Request(new URL(request.url).toString(), { method: 'GET' });

  const hit = await cache.match(key);
  if (hit) {
    const age = Number(hit.headers.get('age') || 0);
    if (age > 300 && waitUntil) {
      waitUntil(
        (async () => {
          const fresh = await render();
          if (fresh.ok) await cache.put(key, fresh.clone());
        })().catch(() => {}),
      );
    }
    return hit;
  }

  const response = await render();
  // Never cache an error: a 500 pinned at the edge for a day is worse than the
  // 500 itself, and a 404 for a book that's about to be added would stick too.
  if (response.ok && waitUntil) waitUntil(cache.put(key, response.clone()));
  return response;
}
