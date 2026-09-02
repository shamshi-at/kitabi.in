// The shared pieces every page is built from.
//
// One cover component, one card component, one pager — because the design's
// "covers first, one frame for all" rule is a promise that only holds if every
// grid on the site is fed through the same function (docs/screen-design.md).

import { authorPath, bookPath, html, joinDot, num, plural, raw, seg } from './html.js';

// Hosts the cover proxy will serve. Kept in step with functions/img/c.js — a
// URL the renderer proxies but the proxy refuses renders as a broken image, and
// one it passes through unproxied is a third-party origin on the critical path.
const PROXYABLE = /^https:\/\/(covers\.openlibrary\.org|[a-z0-9-]+\.supabase\.co)\//;

/**
 * Route a cover through our own origin so it is served from the edge cache
 * rather than fetched from a third party on every page view.
 *
 * Anything not on the allowlist is passed through untouched rather than
 * dropped: a cover from an unexpected host is still a cover, and a blank frame
 * would be a worse outcome than one slow image.
 */
export function coverSrc(url) {
  if (!url) return null;
  return PROXYABLE.test(url) ? `/img/c?u=${encodeURIComponent(url)}` : url;
}

/** Stable 1-8 palette pick for a generated cover, derived from the title so a
 *  book looks the same everywhere it appears rather than flickering per page. */
function tone(text) {
  let n = 0;
  const s = String(text || '');
  for (let i = 0; i < s.length; i++) n = (n * 31 + s.charCodeAt(i)) >>> 0;
  return (n % 8) + 1;
}

/**
 * A cover. Real image when the edition has one, otherwise a typeset cover from
 * title + author — never a broken-image placeholder (screen-design.md).
 *
 * `priority` marks the one cover that is the page's LCP element: it gets
 * fetchpriority=high and NO lazy attribute. Everything else is lazy. Width and
 * height are always set so the layout never shifts — that alone takes CLS to
 * roughly zero, and it was unmeasured-but-likely-poor on the old pages.
 */
export function cover(work, { priority = false, width = 190, rating = null } = {}) {
  const height = Math.round(width * 1.5);
  const title = work?.title || 'Untitled';
  const author = work?.authors?.[0]?.name || '';

  // The community rating, worn on the cover itself — the shelf is where a
  // reader picks the next book, so the signal lives on the object they scan,
  // not in a caption under it. Opt-in per call site: cards pass it, the book
  // hero doesn't (its stars already sit beside the cover). A dark chip with
  // gold text is readable over any cover art and any typeset tone.
  const badge = rating
    ? html`<span class="rt"
        ><span aria-hidden="true">★ ${rating.toFixed(1)}</span
        ><span class="sr">Rated ${rating.toFixed(1)} out of 5</span></span
      >`
    : '';

  // The typeset cover is ALWAYS rendered, and the image sits on top of it.
  //
  // Not just a null-cover fallback. Covers are hotlinked from
  // covers.openlibrary.org — a third-party origin we don't control the latency
  // or availability of — so between first paint and the image arriving there is
  // a window where an <img> alone is an empty box, and a genuinely dead URL
  // leaves one permanently. Deciding the fallback server-side on
  // `cover_url != null` can't see either case. Layering covers both: the
  // typeset cover shows while the image loads and stays if it never does, with
  // no JavaScript and no onerror handler.
  //
  // The proper fix for the latency half is the cover proxy (plan §6) — fetch
  // once, cache at the edge, and drop the third-party origin entirely.
  const typeset = html`<span class="ct">
    <span class="t">${title}</span>
    ${author ? html`<span class="a">${author}</span>` : ''}
  </span>`;

  if (work?.cover_url) {
    return html`<span class="cv g${tone(title)}">
      ${typeset}
      <img src="${coverSrc(work.cover_url)}" alt="${`Cover of ${title}`}" width="${width}" height="${height}"
           ${raw(priority ? 'fetchpriority="high" decoding="async"' : 'loading="lazy" decoding="async"')} />
      ${badge}
    </span>`;
  }
  // role="img" makes children presentational, so the badge's sr text would be
  // silenced here — carry the rating in the label instead.
  return html`<span class="cv g${tone(title)}" role="img"
    aria-label="${rating ? `Cover of ${title} — rated ${rating.toFixed(1)} out of 5` : `Cover of ${title}`}">
    ${typeset}
    ${badge}
  </span>`;
}

/** ★★★★☆ with a count. Renders nothing when there is no rating — an empty
 *  star row reads as "rated zero", which is a different and untrue claim. */
export function stars(rating, count) {
  if (!rating) return '';
  const full = Math.round(rating);
  return html`<span class="stars">
    <span class="s" aria-hidden="true"
      >${raw('★'.repeat(full))}<span class="off">${raw('★'.repeat(5 - full))}</span></span
    >
    <span class="n">${rating.toFixed(1)}${count ? ` · ${plural(count, 'rating')}` : ''}</span>
    <span class="sr">Rated ${rating.toFixed(1)} out of 5</span>
  </span>`;
}

/** The atom of every grid and strip. */
export function bookCard(work, { priority = false } = {}) {
  const authors = (work.authors || []).map((a) => a.name).join(', ');
  return html`<a class="bk" href="${bookPath(work)}">
    ${cover(work, { priority, width: 140, rating: work.rating })}
    <span class="bt">${work.title}</span>
    ${authors ? html`<span class="ba">${authors}</span>` : ''}
  </a>`;
}

export function bookStrip(works, { priorityFirst = false } = {}) {
  if (!works?.length) return '';
  return html`<div class="strip">
    ${works.map((w, i) => bookCard(w, { priority: priorityFirst && i === 0 }))}
  </div>`;
}

export function section(title, body, { more = null, moreLabel = 'See all' } = {}) {
  if (!body) return '';
  return html`<section class="sec">
    <div class="sec-h">
      <h2>${title}</h2>
      ${more ? html`<a class="more" href="${more}">${moreLabel} →</a>` : ''}
    </div>
    ${body}
  </section>`;
}

/** Breadcrumb trail. `items` is [{label, href}] with the last one unlinked. */
export function breadcrumb(items) {
  return html`<nav class="crumb" aria-label="Breadcrumb">
    ${items.map((item, i) =>
      i === items.length - 1
        ? html`<span>${item.label}</span>`
        : html`<a href="${item.href}">${item.label}</a><span class="sep">›</span>`,
    )}
  </nav>`;
}

/**
 * Pagination.
 *
 * Every page is a real link, so a crawler can walk the whole catalogue. Each
 * page self-canonicals with its own title elsewhere — never canonicalise page 2
 * back to page 1, which de-indexes the deep catalogue, i.e. most of it.
 */
export function pager(page, total, perPage, hrefFor) {
  const pages = Math.ceil(total / perPage);
  if (pages <= 1) return '';
  const nums = new Set([1, pages, page, page - 1, page + 1]);
  const list = [...nums].filter((n) => n >= 1 && n <= pages).sort((a, b) => a - b);

  const out = [];
  if (page > 1) out.push(html`<a href="${hrefFor(page - 1)}" rel="prev">‹ Previous</a>`);
  let last = 0;
  for (const n of list) {
    if (n - last > 1) out.push(html`<span class="el">…</span>`);
    out.push(
      n === page
        ? html`<span aria-current="page">${n}</span>`
        : html`<a href="${hrefFor(n)}">${n}</a>`,
    );
    last = n;
  }
  if (page < pages) out.push(html`<a href="${hrefFor(page + 1)}" rel="next">Next ›</a>`);
  return html`<nav class="pager" aria-label="Pagination">${out}</nav>`;
}

/** A person/organisation avatar that degrades to an initial. */
export function avatar(ref, { className = 'ppl' } = {}) {
  const initial = (ref?.name || '?').trim().charAt(0);
  return ref?.image_url
    ? html`<span class="${className}"><img src="${coverSrc(ref.image_url)}" alt="" loading="lazy" /></span>`
    : html`<span class="${className}" aria-hidden="true">${initial}</span>`;
}

/** "by X, Y" with links — used on the book page and in search results. */
export function byline(authors) {
  if (!authors?.length) return '';
  return html`${authors.map(
    (a, i) => html`${i ? ', ' : ''}<a href="${authorPath(a)}">${a.name}</a>`,
  )}`;
}

/** Where the app can actually be got. Live stores are the ONLY thing that may
 *  render as a link — a store badge that goes nowhere is worse than one that
 *  says it isn't there yet, because a reader only learns the difference by
 *  tapping it. Both are live now: Android 31 Aug 2026, iOS 1 Sep 2026.
 *
 *  The App Store link carries no country segment on purpose. Apple resolves
 *  `/app/id…` to whichever storefront the visitor actually shops in; a `/us/`
 *  or `/in/` path sends everyone else through a redirect at best, and this
 *  site's readers are in India and its diaspora both. */
export const PLAY_STORE_URL = 'https://play.google.com/store/apps/details?id=in.kitabi.kitabi';
export const APP_STORE_URL = 'https://apps.apple.com/app/id6787361959';

// The two store marks, inline so the band costs no extra request. Same paths as
// the ones on /app (landing-page/app.html) — the two surfaces are the same
// button and must not drift apart.
const PLAY_ICON = raw(
  '<svg class="ic" viewBox="0 0 24 24" width="19" height="19" aria-hidden="true">' +
    '<path fill="currentColor" d="M4 2.3v19.4c0 .4.45.65.79.42l14.4-9.7a.5.5 0 0 0 0-.84L4.79 1.88A.5.5 0 0 0 4 2.3z"/>' +
    '</svg>',
);
const APPLE_ICON = raw(
  '<svg class="ic" viewBox="0 0 24 24" width="22" height="22" aria-hidden="true">' +
    '<path fill="currentColor" d="M17.05 12.54c-.03-2.89 2.36-4.27 2.47-4.34-1.35-1.97-3.44-2.24-4.18-2.27-1.78-.18-3.47 1.05-4.37 1.05-.9 0-2.29-1.02-3.77-1-1.94.03-3.72 1.13-4.72 2.86-2.01 3.49-.51 8.66 1.45 11.5.96 1.39 2.1 2.95 3.6 2.89 1.45-.06 2-.93 3.75-.93 1.75 0 2.24.93 3.77.9 1.56-.03 2.55-1.41 3.5-2.81 1.1-1.61 1.55-3.17 1.58-3.25-.03-.01-3.03-1.16-3.08-4.6zM14.16 4.06c.8-.97 1.34-2.32 1.19-3.66-1.15.05-2.55.77-3.38 1.74-.74.86-1.39 2.23-1.22 3.55 1.29.1 2.6-.65 3.41-1.63z"/>' +
    '</svg>',
);

/** One store button — an <a> when the store is live, an inert <span> when it
 *  isn't. The two render identically apart from the kicker line, which is the
 *  point: the reader sees one row of buttons and reads which one they can use. */
function storeButton(name, kicker, icon, url) {
  const label = html`${icon}<span><small>${kicker}</small><span>${name}</span></span>`;
  return url
    ? html`<a class="store" href="${url}" rel="noopener" aria-label="Get Kitabi on ${name}">
        ${label}
      </a>`
    : html`<span class="store ghost off" role="note">${label}</span>`;
}

/** The one honest call to action. A door into the app, never a wall — the
 *  public web is strictly read-only, so every write lives on the other side. */
export function appBand() {
  return html`<section class="sec">
    <div class="appband">
      <div>
        <h2>Keep the shelf in your pocket</h2>
        <p>
          Kitabi is a personal library app — track what you own, log what you read, and lend a book
          to a friend without losing it. Free, offline-first, no ads.
        </p>
      </div>
      <div class="stores">
        ${storeButton('Google Play', 'Get it on', PLAY_ICON, PLAY_STORE_URL)}
        ${storeButton('App Store', APP_STORE_URL ? 'Download on the' : 'In review', APPLE_ICON, APP_STORE_URL)}
      </div>
    </div>
  </section>`;
}

export function factsLine(parts) {
  return joinDot(parts);
}

export const langPath = (slug) => `/language/${seg(slug)}`;
export const genrePath = (slug) => `/genre/${seg(slug)}`;
