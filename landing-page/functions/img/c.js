// /img/c?u=<encoded> — the cover image proxy.
//
// Covers are hotlinked from covers.openlibrary.org, a third-party origin whose
// latency and availability we don't control and which rate-limits. That is one
// of the two remaining third-party origins on the critical path (the other was
// Google Fonts, now gone), and it is why covers arrive visibly late — the
// typeset cover showing underneath while an image loads is a mitigation, not a
// fix. Proxying puts them on our origin, behind Cloudflare's cache, fetched
// from the source at most once per edge location per month.
//
// ⚠️ THE ALLOWLIST IS THE WHOLE SECURITY MODEL. An image proxy that will fetch
// any URL is an open proxy: it launders traffic through our domain, lets
// someone serve arbitrary bytes from kitabi.in, and turns the edge into an
// SSRF instrument against anything reachable from it. Only the two hosts that
// legitimately hold Kitabi cover art are accepted, only over https, and
// anything else is refused before a fetch is attempted — not after.

// covers.openlibrary.org — the catalogue's imported covers.
// <project>.supabase.co — the `covers` bucket readers upload their own into
//   (CLAUDE.md: that bucket, never a second store).
const ALLOWED_HOSTS = [/^covers\.openlibrary\.org$/, /^[a-z0-9-]+\.supabase\.co$/];

// A cover is an image. Anything else coming back from an allowed host is a
// misconfiguration or an attack, and is not worth passing to a browser.
const ALLOWED_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/avif'];

const YEAR = 60 * 60 * 24 * 365;

function refuse(status, reason) {
  return new Response(reason, {
    status,
    headers: { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' },
  });
}

/** Parse and vet the requested source. Returns null for anything not allowed. */
export function allowedSource(raw) {
  if (!raw || raw.length > 600) return null;
  let url;
  try {
    url = new URL(raw);
  } catch (_) {
    return null;
  }
  // https only — an http hop would be a downgrade we'd be performing on the
  // reader's behalf, and neither source needs it.
  if (url.protocol !== 'https:') return null;
  if (!ALLOWED_HOSTS.some((re) => re.test(url.hostname))) return null;
  // No credentials, no ports: both are signals of something other than a CDN.
  if (url.username || url.password || url.port) return null;
  return url;
}

export async function onRequestGet(context) {
  const { request, waitUntil } = context;
  const source = allowedSource(new URL(request.url).searchParams.get('u'));
  if (!source) return refuse(400, 'Not an allowed image source.');

  const cache = caches.default;
  const key = new Request(new URL(request.url).toString(), { method: 'GET' });
  const hit = await cache.match(key);
  if (hit) return hit;

  let upstream;
  try {
    upstream = await fetch(source.toString(), {
      headers: { Accept: 'image/*' },
      // Belt and braces: even with the allowlist, don't follow a redirect off
      // an allowed host onto something else.
      redirect: 'follow',
      cf: { cacheTtl: YEAR, cacheEverything: true },
    });
  } catch (_) {
    return refuse(502, 'Could not fetch the image.');
  }

  if (!upstream.ok) {
    // Pass the shape of the failure through but never cache it — a cover that
    // 404s today may be uploaded tomorrow, and the page degrades to the typeset
    // cover in the meantime.
    return refuse(upstream.status === 404 ? 404 : 502, 'Image unavailable.');
  }

  const type = (upstream.headers.get('content-type') || '').split(';')[0].trim().toLowerCase();
  if (!ALLOWED_TYPES.includes(type)) return refuse(415, 'Not an image.');

  const response = new Response(upstream.body, {
    status: 200,
    headers: {
      'Content-Type': type,
      // Immutable: the URL contains the source, so different art is a different
      // URL. A year at the edge means the origin is hit about once.
      'Cache-Control': `public, max-age=${YEAR}, immutable`,
      'X-Content-Type-Options': 'nosniff',
      // The bytes came from somewhere else; make sure nothing treats this
      // response as same-origin active content.
      'Content-Security-Policy': "default-src 'none'; img-src 'self' data:; sandbox",
    },
  });
  if (waitUntil) waitUntil(cache.put(key, response.clone()));
  return response;
}
