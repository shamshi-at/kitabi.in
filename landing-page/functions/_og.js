// Shared Open Graph injection for the public share pages (/b/:id, /a/:id, /p/:id).
//
// The share pages render themselves client-side (see book.html etc.), but
// link-preview bots — iMessage, WhatsApp, Slack, Telegram — do NOT run JS. They
// read only the static <head>, which ships a generic fallback ("A book on
// Kitabi / Track, lend, and share your library"). These Pages Functions run at
// the edge, fetch the real entity from the catalog API, and rewrite the <head>
// so a shared link previews with the real cover, title and a short blurb.
//
// SCALE: one edge invocation + one API GET per share-link hit. Fine on the free
// tier; if invocations ever bite, cache the API response at the edge.

const API = 'https://api.kitabi.in';

// Escape a string for interpolation into an HTML attribute value (we build the
// appended <meta> tags as raw HTML, so we must escape ourselves).
function attr(v) {
  return String(v == null ? '' : v)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// Collapse whitespace and clamp to a link-preview-friendly length.
export function clamp(text, max) {
  const t = String(text || '').replace(/\s+/g, ' ').trim();
  if (t.length <= max) return t;
  return t.slice(0, max - 1).trimEnd() + '…';
}

// Fetch the entity JSON from the catalog API.
//
// Returns { data, missing }. `missing` is true ONLY when the API answered
// definitively that there is no such entity (404/410) — a 5xx, a timeout, or a
// network blip leaves it false. That distinction is the whole point: a missing
// entity should tell crawlers "gone" (see notFound), but an API outage must
// not, or one bad minute would deindex every real book page on the site.
export async function fetchEntity(path) {
  try {
    const r = await fetch(`${API}${path}`, { headers: { Accept: 'application/json' } });
    if (r.ok) return { data: await r.json(), missing: false };
    return { data: null, missing: r.status === 404 || r.status === 410 };
  } catch (_) {
    return { data: null, missing: false };
  }
}

// The shell served as a real 404 for an entity that doesn't exist, with a
// noindex so a crawler that already has the URL drops it instead of keeping a
// generic "A book on Kitabi" page in the index. Without this the shell went out
// as HTTP 200 — a soft 404, and one near-identical thin page per dead link.
export function notFound(shell) {
  const page = new HTMLRewriter()
    .on('head', {
      element(el) {
        el.append('<meta name="robots" content="noindex">', { html: true });
      },
    })
    .transform(shell);
  return new Response(page.body, { status: 404, headers: page.headers });
}

// Rewrite the static shell's <head> with real OG / Twitter tags. `meta` carries
// { pageTitle, title, description, url, image, card, canonical, jsonLd }.
// `image`, `canonical` (a <link rel="canonical">) and `jsonLd` (an object,
// emitted as an application/ld+json script for search engines) are optional.
export function injectOg(shell, meta) {
  const image = meta.image ? attr(meta.image) : '';
  const url = attr(meta.url);
  const title = attr(meta.title);
  const desc = attr(meta.description);
  const card = meta.card || 'summary';

  return new HTMLRewriter()
    .on('title', {
      element(el) {
        el.setInnerContent(meta.pageTitle || meta.title);
      },
    })
    .on('meta[name="description"]', {
      element(el) {
        el.setAttribute('content', meta.description);
      },
    })
    .on('meta[property="og:title"]', {
      element(el) {
        el.setAttribute('content', meta.title);
      },
    })
    .on('meta[property="og:description"]', {
      element(el) {
        el.setAttribute('content', meta.description);
      },
    })
    .on('head', {
      element(el) {
        const tags = [
          `<meta property="og:url" content="${url}">`,
          `<meta name="twitter:card" content="${image ? card : 'summary'}">`,
          `<meta name="twitter:title" content="${title}">`,
          `<meta name="twitter:description" content="${desc}">`,
        ];
        if (image) {
          tags.push(`<meta property="og:image" content="${image}">`);
          tags.push(`<meta property="og:image:secure_url" content="${image}">`);
          tags.push(`<meta property="og:image:alt" content="${title}">`);
          tags.push(`<meta name="twitter:image" content="${image}">`);
        }
        if (meta.canonical) {
          tags.push(`<link rel="canonical" href="${attr(meta.canonical)}">`);
        }
        if (meta.jsonLd) {
          // Escape < so the JSON can never close the script tag early.
          const json = JSON.stringify(meta.jsonLd).replace(/</g, '\\u003c');
          tags.push(`<script type="application/ld+json">${json}</script>`);
        }
        el.append(tags.join(''), { html: true });
      },
    })
    .transform(shell);
}
