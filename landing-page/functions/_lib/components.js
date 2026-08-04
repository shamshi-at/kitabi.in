// The shared pieces every page is built from.
//
// One cover component, one card component, one pager — because the design's
// "covers first, one frame for all" rule is a promise that only holds if every
// grid on the site is fed through the same function (docs/screen-design.md).

import { authorPath, bookPath, html, joinDot, num, raw, seg } from './html.js';

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
export function cover(work, { priority = false, width = 190 } = {}) {
  const height = Math.round(width * 1.5);
  const title = work?.title || 'Untitled';
  const author = work?.authors?.[0]?.name || '';

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
      <img src="${work.cover_url}" alt="${`Cover of ${title}`}" width="${width}" height="${height}"
           ${raw(priority ? 'fetchpriority="high" decoding="async"' : 'loading="lazy" decoding="async"')} />
    </span>`;
  }
  return html`<span class="cv g${tone(title)}" role="img" aria-label="${`Cover of ${title}`}">
    ${typeset}
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
    <span class="n">${rating.toFixed(1)}${count ? ` · ${num(count)} ratings` : ''}</span>
    <span class="sr">Rated ${rating.toFixed(1)} out of 5</span>
  </span>`;
}

/** The atom of every grid and strip. */
export function bookCard(work, { priority = false } = {}) {
  const authors = (work.authors || []).map((a) => a.name).join(', ');
  return html`<a class="bk" href="${bookPath(work)}">
    ${cover(work, { priority, width: 140 })}
    <span class="bt">${work.title}</span>
    ${authors ? html`<span class="ba">${authors}</span>` : ''}
    ${work.rating
      ? html`<span class="brt"
          >★ ${work.rating.toFixed(1)}${work.rating_count
            ? html` <span>· ${num(work.rating_count)}</span>`
            : ''}</span
        >`
      : ''}
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
    ? html`<span class="${className}"><img src="${ref.image_url}" alt="" loading="lazy" /></span>`
    : html`<span class="${className}" aria-hidden="true">${initial}</span>`;
}

/** "by X, Y" with links — used on the book page and in search results. */
export function byline(authors) {
  if (!authors?.length) return '';
  return html`${authors.map(
    (a, i) => html`${i ? ', ' : ''}<a href="${authorPath(a)}">${a.name}</a>`,
  )}`;
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
      <div>
        <span class="b">App Store</span><span class="b">Google Play</span>
      </div>
    </div>
  </section>`;
}

export function factsLine(parts) {
  return joinDot(parts);
}

export const langPath = (slug) => `/language/${seg(slug)}`;
export const genrePath = (slug) => `/genre/${seg(slug)}`;
