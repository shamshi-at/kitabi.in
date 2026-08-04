// The page shell: <head> (SEO, structured data), header, footer, response.
//
// Everything a crawler needs is in the HTML this produces — no JavaScript runs
// to reveal content. That is the entire point of the rewrite: the measured
// baseline served "Opening the book…" and a spinner to anything that doesn't
// execute JS, which is most crawlers and, for ranking purposes, effectively
// Googlebot too.

import { CACHE_CONTROL } from './api.js';
import { CSS } from './css.js';
import { SUGGEST_CSS, SUGGEST_JS } from './suggest.js';
import { attr, h, html, raw } from './html.js';

export const SITE = 'Kitabi';
export const ORIGIN = 'https://kitabi.in';
export const TAGLINE = 'Beyond the Bookshelf';

function headerHtml(nav, q) {
  const item = (href, label, key) =>
    html`<a href="${href}"${raw(nav === key ? ' aria-current="page"' : '')}>${label}</a>`;
  return html`
    <a class="skip" href="#main">Skip to content</a>
    <header class="shead">
      <div class="shead-in">
        <a class="brand" href="/">
          <img src="/logo.svg?v=3" width="32" height="32" alt="" />
          <span class="bn">${SITE}<small>${TAGLINE}</small></span>
        </a>
        <nav class="snav" aria-label="Sections">
          ${item('/browse', 'Books', 'books')} ${item('/authors', 'Authors', 'authors')}
          ${item('/publishers', 'Publishers', 'publishers')}
          ${item('/languages', 'Languages', 'languages')} ${item('/lists', 'Lists', 'lists')}
        </nav>
        <form class="hsearch" action="/search" method="get" role="search">
          <label class="sr" for="q">Search books, authors and publishers</label>
          <input id="q" name="q" type="search" value="${attr(q || '')}"
                 placeholder="Search a book, author or publisher…" />
          <button type="submit" aria-label="Search">Go</button>
        </form>
        <a class="btn-app" href="/app">Get the app</a>
      </div>
    </header>
  `;
}

const FOOTER = html`
  <footer class="sfoot">
    <div class="wrap sfoot-in">
      <div>
        <div class="fb">${SITE}</div>
        <p>A reference library for Indian literature, and a personal one for your shelf.</p>
      </div>
      <div>
        <h2>Browse</h2>
        <a href="/languages">Languages</a><a href="/genres">Genres</a>
        <a href="/authors">Authors</a><a href="/publishers">Publishers</a>
      </div>
      <div>
        <h2>Discover</h2>
        <a href="/lists">Editors' lists</a><a href="/browse?sort=year_desc">Recently added</a>
        <a href="/translations">Translations</a>
      </div>
      <div>
        <h2>${SITE}</h2>
        <a href="/app">The app</a><a href="/privacy.html">Privacy</a><a href="/terms.html">Terms</a>
      </div>
    </div>
    <div class="wrap"><div class="legal">© 2026 ${SITE}. Book data contributed by readers.</div></div>
  </footer>
`;

/**
 * Render a complete document.
 *
 * `indexable: false` emits `noindex, follow` — still crawlable, still linked,
 * just not competing. That is the content-floor rule (plan §8.3) and it is why
 * this site will publish ~250-400 strong pages rather than 1,402 thin ones.
 */
export function page({
  title,
  description,
  body,
  canonical,
  image = null,
  ogType = 'website',
  jsonLd = null,
  indexable = true,
  nav = null,
  q = '',
  lang = 'en',
  status = 200,
  extraHead = '',
}) {
  const canonicalUrl = canonical ? `${ORIGIN}${canonical}` : ORIGIN;
  const desc = description || `${SITE} — a reference library for Indian literature.`;
  const blocks = (Array.isArray(jsonLd) ? jsonLd : [jsonLd]).filter(Boolean);

  const doc = `<!doctype html>
<html lang="${attr(lang)}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>${h(title)}</title>
<meta name="description" content="${attr(desc)}">
<meta name="robots" content="${indexable ? 'index, follow' : 'noindex, follow'}">
<link rel="canonical" href="${attr(canonicalUrl)}">
<meta name="theme-color" content="#F6F0E3">
<link rel="preload" href="/fonts/fraunces-latin.woff2" as="font" type="font/woff2" crossorigin>
<link rel="preload" href="/fonts/inter-latin.woff2" as="font" type="font/woff2" crossorigin>
<link rel="icon" href="/logo.svg?v=3" type="image/svg+xml">
<link rel="icon" href="/ico.png?v=3" type="image/png">
<link rel="apple-touch-icon" href="/apple-touch-icon.png?v=3">
<meta property="og:site_name" content="${attr(SITE)}">
<meta property="og:type" content="${attr(ogType)}">
<meta property="og:title" content="${attr(title)}">
<meta property="og:description" content="${attr(desc)}">
<meta property="og:url" content="${attr(canonicalUrl)}">
<meta name="twitter:card" content="${image ? 'summary_large_image' : 'summary'}">
<meta name="twitter:title" content="${attr(title)}">
<meta name="twitter:description" content="${attr(desc)}">
${image ? `<meta property="og:image" content="${attr(image)}"><meta property="og:image:secure_url" content="${attr(image)}"><meta name="twitter:image" content="${attr(image)}">` : ''}
<style>${CSS}${SUGGEST_CSS}</style>
${blocks
  .map(
    (b) =>
      // Escape < so the JSON can never close the script tag early.
      `<script type="application/ld+json">${JSON.stringify(b).replace(/</g, '\\u003c')}</script>`,
  )
  .join('')}
${extraHead}
</head>
<body>
${headerHtml(nav, q)}
<main id="main">${body}</main>
${FOOTER}
<script defer>${SUGGEST_JS}</script>
</body>
</html>`;

  return new Response(doc, {
    status,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': status === 200 ? CACHE_CONTROL : 'no-store',
      // Cheap, universally-applicable hardening for a static read-only site.
      'X-Content-Type-Options': 'nosniff',
      'Referrer-Policy': 'strict-origin-when-cross-origin',
    },
  });
}

/**
 * A real 404 — status AND noindex.
 *
 * Serving a shell as HTTP 200 for a dead link is a soft 404: it leaves one
 * near-identical thin page per broken URL in the index. The previous share
 * pages did exactly that until it was fixed, and the fix has to survive here.
 */
export function notFound({ what = 'page', suggestions = '' } = {}) {
  return page({
    title: `Not found — ${SITE}`,
    description: 'That page is not on Kitabi.',
    indexable: false,
    status: 404,
    canonical: null,
    body: html`
      <div class="wrap" style="padding-top:34px">
        <div class="thin">
          <div class="fl">❦</div>
          <h1>We couldn't find that ${what}</h1>
          <p>
            It may have been merged into another entry, or the link may be wrong. The catalogue is
            contributed by readers, so things do move.
          </p>
          <a class="btn-ghost" style="margin-top:15px" href="/">Back to Kitabi</a>
        </div>
        ${suggestions}
      </div>
    `,
  });
}

/**
 * The API is unreachable. Explicitly NOT a 404 — a blip must never tell a
 * crawler that a real page is gone, or one bad minute deindexes the site.
 * 503 + Retry-After is the honest answer and search engines respect it.
 */
export function unavailable() {
  const res = page({
    title: `Temporarily unavailable — ${SITE}`,
    description: 'Kitabi is having a moment. Please try again shortly.',
    indexable: false,
    status: 503,
    canonical: null,
    body: html`
      <div class="wrap" style="padding-top:34px">
        <div class="thin">
          <div class="fl">❦</div>
          <h1>Just a moment</h1>
          <p>We couldn't reach the library right now. Please try again in a few seconds.</p>
        </div>
      </div>
    `,
  });
  const headers = new Headers(res.headers);
  headers.set('Retry-After', '30');
  return new Response(res.body, { status: 503, headers });
}
