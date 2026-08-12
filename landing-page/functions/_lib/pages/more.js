// The remaining page types: series, translation group, editorial lists, the
// standalone reviews page, and public reader profiles.
// Mockups W8, W9, W10, W11, W12.

import * as ld from '../jsonld.js';
import { appBand, avatar, bookStrip, breadcrumb, cover, pager, section, stars } from '../components.js';
import { authorPath, bookPath, clamp, html, joinDot, num, seg } from '../html.js';
import { page } from '../layout.js';

// --------------------------------------------------------------------------
// W8 — Series
// --------------------------------------------------------------------------

export function renderSeries(data) {
  const canonical = `/series/${seg(data.slug || data.id)}`;
  const crumbs = [{ label: 'Home', href: '/' }, { label: data.name }];

  // One entry per position, translations collapsed into it. `entries` is what
  // the API serves now; the fallback keeps this page rendering against an API
  // that hasn't rolled yet — the two deploy separately, and a body that needs
  // the newest API to appear is a body crawlers lose in between.
  const entries =
    data.entries?.length
      ? data.entries
      : (data.works || []).map((w, i) => ({ number: i + 1, book: w, also: [] }));

  const body = html`
    <div class="wrap">
      ${breadcrumb(crumbs)}
      <div style="margin-top:18px">
        <p class="eyebrow">
          Series · ${entries.length} ${entries.length === 1 ? 'book' : 'books'}${data.languages
            ?.length > 1
            ? ` · in ${data.languages.join(', ')}`
            : ''}
        </p>
        <h1 class="serif" style="font-size:clamp(25px,5vw,32px);font-weight:600;margin-top:6px">
          ${data.name}
        </h1>
        ${data.description
          ? html`<p style="margin-top:10px;max-width:62ch;line-height:1.7">${data.description}</p>`
          : ''}
      </div>
      <section class="sec">
        <div class="eds">
          ${entries.map(
            (e) => html`<a class="ed" href="${bookPath(e.book)}" style="grid-template-columns:34px 44px 1fr">
              <span class="serif" style="font-size:19px;font-weight:700;color:#B8862B"
                >${e.number ?? '·'}</span
              >
              <span>${cover(e.book, { width: 44 })}</span>
              <span>
                <span class="et">${e.book.title}</span>
                <span class="em"
                  >${joinDot([
                    (e.book.authors || []).map((a) => a.name).join(', '),
                    e.book.year,
                    e.book.language,
                  ])}</span
                >
                ${e.also?.length
                  ? html`<span class="em"
                      >${'Also in ' + e.also.map((t) => t.language || t.title).join(', ')}</span
                    >`
                  : ''}
              </span>
            </a>`,
          )}
        </div>
        ${entries.some((e) => e.also?.length)
          ? html`<p class="cap" style="margin-top:10px">
              Each book is listed once, under the number it holds in the series — a translation
              sits at the same position as the book it was translated from.
            </p>`
          : ''}
      </section>
      ${appBand()}
    </div>
  `;

  return page({
    title: `${data.name} — the books in order — Kitabi`,
    description: `Every book in the ${data.name} series, in reading order.`,
    canonical,
    body,
    nav: 'books',
    // A one-book "series" is not a series — it's a thin page.
    indexable: data.indexable !== false,
    jsonLd: [
      ld.collectionPage(data.name, data.description || null, canonical),
      ld.breadcrumbList(crumbs),
      // The positions, not every translation of them: an ItemList that repeats
      // a book once per language describes a longer series than exists.
      ...(entries.length ? [ld.itemList(entries.map((e) => e.book), data.name)] : []),
    ],
  });
}

// --------------------------------------------------------------------------
// W9 — Translation group
// --------------------------------------------------------------------------

export function renderTranslations(data) {
  const anchor = data.original || data.translations?.[0];
  const canonical = `/translations/${seg(anchor?.slug || data.group_id)}`;
  const crumbs = [
    { label: 'Home', href: '/' },
    { label: 'Translations', href: '/translations' },
    { label: data.title },
  ];
  const all = [...(data.original ? [data.original] : []), ...(data.translations || [])];

  const body = html`
    <div class="wrap">
      ${breadcrumb(crumbs)}
      <div style="margin-top:18px">
        <p class="eyebrow" style="color:#B8862B">One book · ${all.length} languages</p>
        <h1 class="serif" style="font-size:clamp(25px,5vw,32px);font-weight:600;margin-top:6px">
          ${data.title}
        </h1>
        ${data.group_rating
          ? html`<div class="rating-row">
              <span class="big">${data.group_rating.toFixed(1)}<span> / 5</span></span>
              <span class="n" style="font-size:12.5px;color:#7A6A55;font-weight:600"
                >across all ${all.length} translations${data.group_rating_count
                  ? ` · ${num(data.group_rating_count)} ratings`
                  : ''}</span
              >
            </div>`
          : ''}
        ${data.description ? html`<p class="blurb">${data.description}</p>` : ''}
      </div>

      <section class="sec">
        <div class="trans">
          <div class="rule"></div>
          <div class="tin">
            <h2 class="eyebrow" style="color:#8F681E">Every language it exists in</h2>
            <div class="tg">
              ${all.map(
                (w) => html`<a class="tcard${w.is_original ? ' orig' : ''}" href="${bookPath(w)}">
                  <span class="cvw">${cover(w, { width: 48 })}</span>
                  <span class="ti">
                    <span class="lg">${w.language || 'Unknown'}${w.is_original ? ' · the original' : ''}</span>
                    <span class="t">${w.title}</span>
                    <span class="m"
                      >${joinDot([
                        w.year,
                        w.rating ? `★ ${w.rating.toFixed(1)}` : null,
                      ])}</span
                    >
                  </span>
                </a>`,
              )}
            </div>
          </div>
        </div>
      </section>

      ${data.translators?.length
        ? section(
            'The translators',
            html`<p class="chips">
              ${data.translators.map(
                (t) => html`<a class="chip" href="${authorPath(t)}">${t.name}</a>`,
              )}
            </p>`,
          )
        : ''}
      ${appBand()}
    </div>
  `;

  return page({
    title: `${data.title} — in ${all.length} languages — Kitabi`,
    description: clamp(
      `${data.title} across every language it has been translated into, each with its own rating.`,
      160,
    ),
    canonical,
    body,
    nav: 'books',
    jsonLd: [ld.collectionPage(data.title, data.description, canonical), ld.breadcrumbList(crumbs)],
  });
}

// --------------------------------------------------------------------------
// W10 — Editorial lists
// --------------------------------------------------------------------------

export function renderList(list, works) {
  const canonical = `/list/${seg(list.slug)}`;
  const crumbs = [
    { label: 'Home', href: '/' },
    { label: 'Lists', href: '/lists' },
    { label: list.title },
  ];
  const byId = new Map(works.map((w) => [w.slug || String(w.id), w]));

  const body = html`
    <div class="listhead" style="background:linear-gradient(135deg,#33241A,#241811);color:#E9DCC2;padding:34px 0">
      <div class="wrap">
        <p class="eyebrow" style="color:#B8862B">An editors' list</p>
        <h1 class="serif" style="font-size:clamp(27px,5.5vw,38px);font-weight:600;color:#F6F0E3;margin-top:8px;line-height:1.16">
          ${list.title}
        </h1>
        <p style="font-size:14.5px;color:#CBB897;line-height:1.75;margin-top:12px;max-width:700px">
          ${list.intro}
        </p>
        <p style="margin-top:14px;font-size:12px;color:#9d8b6e">${list.entries.length} books</p>
      </div>
    </div>

    <div class="wrap">
      ${list.entries.map((entry, i) => {
        const work = byId.get(entry.slug);
        if (!work) return '';
        return html`<article
          style="display:grid;grid-template-columns:38px 74px 1fr;gap:16px;padding:20px 0;border-bottom:1px solid #E2D6BD;align-items:start"
        >
          <span class="serif" style="font-size:28px;font-weight:700;color:#B8862B;line-height:1">${i + 1}</span>
          <a href="${bookPath(work)}" style="display:block">${cover(work, { width: 74 })}</a>
          <div>
            <h2 class="serif" style="font-size:19px;font-weight:600;line-height:1.24">
              <a href="${bookPath(work)}">${work.title}</a>
            </h2>
            <p style="font-size:13px;color:#7A6A55;margin-top:4px">
              ${joinDot([
                (work.authors || []).map((a) => a.name).join(', '),
                work.year,
                work.language,
              ])}
            </p>
            ${entry.why
              ? html`<p style="font-size:13.5px;line-height:1.75;color:#4a3d2e;margin-top:9px;max-width:660px">
                  ${entry.why}
                </p>`
              : ''}
          </div>
        </article>`;
      })}
      ${appBand()}
    </div>
  `;

  return page({
    title: `${list.title} — Kitabi`,
    description: clamp(list.intro, 160),
    canonical,
    body,
    nav: 'lists',
    jsonLd: [
      ld.collectionPage(list.title, list.intro, canonical),
      ld.breadcrumbList(crumbs),
      ...(works.length ? [ld.itemList(works, list.title)] : []),
    ],
  });
}

export function renderListIndex(lists) {
  const body = html`
    <div class="wrap">
      ${breadcrumb([{ label: 'Home', href: '/' }, { label: 'Lists' }])}
      <h1 class="serif" style="font-size:30px;font-weight:600;margin-top:14px">Editors' lists</h1>
      <p class="intro">
        Routes through the catalogue, written rather than generated. Each one is a way in to a
        literature that can be intimidating from outside.
      </p>
      <section class="sec">
        <div class="strip" style="grid-template-columns:repeat(auto-fill,minmax(240px,1fr))">
          ${lists.map(
            (l) => html`<a href="/list/${seg(l.slug)}"
              style="display:block;background:linear-gradient(135deg,#33241A,#241811);border-radius:11px;padding:19px;min-height:120px">
              <span class="eyebrow" style="color:#B8862B">Editors' list · ${l.entries.length} books</span>
              <span class="serif" style="display:block;color:#F6F0E3;font-size:17px;font-weight:600;line-height:1.28;margin-top:10px">${l.title}</span>
            </a>`,
          )}
        </div>
      </section>
      ${appBand()}
    </div>
  `;
  return page({
    title: "Editors' lists — Kitabi",
    description: 'Curated routes through Indian literature — where to start, and what to read next.',
    canonical: '/lists',
    body,
    nav: 'lists',
    jsonLd: [ld.collectionPage("Editors' lists", null, '/lists')],
  });
}

// --------------------------------------------------------------------------
// W11 — Reviews
// --------------------------------------------------------------------------

export function renderReviews(data) {
  const work = data.work;
  const base = `${bookPath(work)}/reviews`;
  const hrefFor = (p) => (p === 1 ? base : `${base}?page=${p}`);
  const crumbs = [
    { label: 'Home', href: '/' },
    { label: work.title, href: bookPath(work) },
    { label: 'Reviews' },
  ];
  const dist = data.rating?.distribution || {};
  const max = Math.max(1, ...Object.values(dist));

  const body = html`
    <div class="wrap">
      ${breadcrumb(crumbs)}
      <h1 class="serif" style="font-size:26px;font-weight:600;margin-top:14px">
        ${num(data.total)} ${data.total === 1 ? 'review' : 'reviews'} of
        <a href="${bookPath(work)}" style="color:#7E2A33">${work.title}</a>
      </h1>

      ${data.rating?.count
        ? html`<div class="ratings" style="margin:18px 0 20px">
            <div class="score">
              <div class="n">${data.rating.average ? data.rating.average.toFixed(1) : '—'}</div>
              <div>${stars(data.rating.average, 0)}</div>
              <div class="of">${num(data.rating.count)} ratings</div>
            </div>
            <div class="hist">
              ${[5, 4, 3, 2, 1].map((n) => {
                const c = dist[String(n)] || 0;
                return html`<div class="hbar">
                  <span class="lb">${n} ★</span>
                  <span class="tr"
                    ><span class="fl" style="width:${Math.round((c / max) * 100)}%"></span
                  ></span>
                  <span class="ct">${num(c)}</span>
                </div>`;
              })}
            </div>
          </div>`
        : ''}

      ${data.reviews?.length
        ? html`${data.reviews.map(
            (r) => html`<article class="rev">
              <div class="rhd">
                ${avatar({ name: r.reviewer?.display_name || 'A reader' }, { className: 'av' })}
                <div>
                  <div class="who">${r.reviewer?.display_name || 'A reader on Kitabi'}</div>
                  ${r.created_at
                    ? html`<div class="when">${String(r.created_at).slice(0, 10)}</div>`
                    : ''}
                </div>
                ${r.rating
                  ? html`<div class="rs" aria-label="${`Rated ${r.rating} out of 5`}">
                      ${'★'.repeat(Math.round(r.rating))}
                    </div>`
                  : ''}
              </div>
              ${r.body ? html`<p class="rt">“${r.body}”</p>` : ''}
            </article>`,
          )}
          ${pager(data.page, data.total, data.per_page, hrefFor)}`
        : html`<div class="thin">
            <div class="fl">❦</div>
            <h2>No reviews yet</h2>
            <p>Be the first — reviews are written in the Kitabi app.</p>
          </div>`}
      ${appBand()}
    </div>
  `;

  return page({
    title: `Reviews of ${work.title} — Kitabi`,
    description: `What readers said about ${work.title}${
      data.rating?.count ? ` — ${num(data.rating.count)} ratings` : ''
    }.`,
    canonical: hrefFor(data.page),
    body,
    nav: 'books',
    // Thin until there's something to read. Still followed, so the book page
    // and every reviewer link stay reachable.
    indexable: data.total >= 3,
    jsonLd: [ld.breadcrumbList(crumbs)],
  });
}

// --------------------------------------------------------------------------
// W12 — Reader profile
// --------------------------------------------------------------------------

// A review on the reader's own page. Same card as the book page's, turned
// around: there the reviewer heads each row and the book is assumed, here the
// reader IS the page, so the book takes the header and naming them again on
// every row would just be noise.
function writtenReviews(reviews) {
  if (!reviews?.length) return '';
  return html`${reviews.map((r) => {
    const work = r.work || {};
    const authors = (work.authors || []).map((a) => a.name).join(', ');
    return html`<article class="rev">
      <div class="rhd">
        <!-- 44px, the same as the editions table: the typeset fallback cover
             draws its title at a fixed 13px, so anything narrower clips it. -->
        <a href="${bookPath(work)}" style="flex:none;width:44px">${cover(work, { width: 44 })}</a>
        <div style="min-width:0">
          <div class="who"><a href="${bookPath(work)}">${work.title}</a></div>
          <div class="when">
            ${joinDot([authors, r.created_at ? String(r.created_at).slice(0, 10) : null])}
          </div>
        </div>
        ${r.rating
          ? html`<div class="rs" aria-label="${`Rated ${r.rating} out of 5`}">
              ${'★'.repeat(Math.round(r.rating))}
            </div>`
          : ''}
      </div>
      ${r.body ? html`<p class="rt">“${r.body}”</p>` : ''}
    </article>`;
  })}`;
}

export function renderReader(data) {
  const canonical = `/reader/${seg(data.username || data.id)}`;
  const crumbs = [{ label: 'Home', href: '/' }, { label: data.display_name }];
  const reviews = data.reviews || [];

  const body = html`
    <div class="wrap">
      ${breadcrumb(crumbs)}
      <div style="display:flex;gap:22px;align-items:center;margin-top:20px;flex-wrap:wrap">
        <span class="portrait" style="width:84px;height:84px;max-width:84px;border-radius:50%;font-size:32px">
          ${data.avatar_url
            ? html`<img src="${data.avatar_url}" alt="" width="84" height="84" />`
            : html`${data.display_name.trim().charAt(0)}`}
        </span>
        <div>
          <h1 class="serif" style="font-size:27px;font-weight:600">${data.display_name}</h1>
          ${data.username ? html`<p style="font-size:13px;color:#7A6A55;margin-top:3px">@${data.username}</p>` : ''}
          <div style="display:flex;gap:24px;margin-top:11px">
            <span><b class="serif" style="font-size:19px;display:block">${num(data.score)}</b>
              <span class="eyebrow">Score</span></span>
            ${data.library_visible
              ? html`<span><b class="serif" style="font-size:19px;display:block">${num(data.recent.length)}</b>
                  <span class="eyebrow">Books shown</span></span>`
              : ''}
            ${reviews.length
              ? html`<span><b class="serif" style="font-size:19px;display:block">${num(reviews.length)}</b>
                  <span class="eyebrow">${reviews.length === 1 ? 'Review' : 'Reviews'}</span></span>`
              : ''}
          </div>
        </div>
      </div>

      ${data.library_visible && data.recent?.length
        ? section('On their shelf', bookStrip(data.recent))
        : html`<section class="sec">
            <div class="thin">
              <p>This reader keeps their shelf private.</p>
            </div>
          </section>`}
      ${reviews.length ? section('What they wrote', writtenReviews(reviews)) : ''}
      ${appBand()}
    </div>
  `;

  return page({
    title: `${data.display_name} — Kitabi`,
    description: reviews.length
      ? clamp(
          `${data.display_name} on Kitabi — ${num(reviews.length)} ${
            reviews.length === 1 ? 'book review' : 'book reviews'
          }${reviews[0]?.work?.title ? `, including ${reviews[0].work.title}` : ''}.`,
          160,
        )
      : `${data.display_name} on Kitabi.`,
    canonical,
    body,
    // A profile page is thin by nature and is about a person, not a book — so
    // it earns indexing only by carrying something worth landing on. A public
    // shelf counts; so does a review, which is original prose that exists
    // nowhere else on the site (and the reason this page is worth crawling at
    // all). Same self-healing shape as the book page's content floor: nobody
    // decides, the reader's own activity flips it.
    indexable: Boolean((data.library_visible && data.recent?.length) || reviews.length),
    // Deliberately no Review markup, matching renderReviews above: these are
    // real reviews, but a profile is not a review-rich-result surface, and the
    // rule at the top of jsonld.js is worth over-honouring.
    jsonLd: [ld.breadcrumbList(crumbs)],
  });
}

// --------------------------------------------------------------------------
// /translations — the index
// --------------------------------------------------------------------------

export function renderTranslationIndex(pairs) {
  const body = html`
    <div class="wrap">
      ${breadcrumb([{ label: 'Home', href: '/' }, { label: 'Translations' }])}
      <h1 class="serif" style="font-size:30px;font-weight:600;margin-top:14px">Translations</h1>
      <p class="intro">
        Books that exist in more than one language, traced in both directions. Each translation
        keeps its own rating — they are different books to their readers — with the group average
        shown alongside.
      </p>
      <section class="sec">
        ${pairs.length
          ? html`<div class="pairs">
              ${pairs.map(
                (p) => html`<a class="pair" href="${bookPath(p.original)}">
                  <span class="rule"></span>
                  <span class="in">
                    <span class="cvw">${cover(p.original, { width: 44 })}</span>
                    <span class="side">
                      <span class="t">${p.original.title}</span>
                      <span class="m">${joinDot([p.original.language, p.original.year])}</span>
                    </span>
                    <span class="arrow" aria-hidden="true">⇄</span>
                    <span class="side" style="text-align:right">
                      <span class="t">${p.translation.title}</span>
                      <span class="m">${joinDot([p.translation.language, p.translation.year])}</span>
                    </span>
                  </span>
                </a>`,
              )}
            </div>`
          : html`<div class="thin">
              <div class="fl">❦</div>
              <h2>No linked translations yet</h2>
              <p>
                Translations are linked by readers in the Kitabi app — an original and its
                translation become one group, each keeping its own rating.
              </p>
            </div>`}
      </section>
      ${appBand()}
    </div>
  `;
  return page({
    title: 'Translations — Indian books across languages — Kitabi',
    description:
      'Indian books traced across every language they exist in — originals and translations, each with its own rating.',
    canonical: '/translations',
    body,
    nav: 'books',
    jsonLd: [ld.collectionPage('Translations', null, '/translations')],
  });
}
