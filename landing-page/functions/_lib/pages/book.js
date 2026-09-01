// The book page — the flagship. Everything else on the site exists to send
// people here (docs/web-platform-plan.md §5, mockup W3).
//
// Order of the page is the order the questions actually arrive: what is it →
// what do people think → what's it about → what do I do about it. Then, below
// the fold: read it in another language → which printing → what readers said →
// what else by this author → what's like it → the facts.
//
// The translation module sits directly under the fold, ABOVE editions and
// reviews, on purpose: it is the one thing Goodreads, StoryGraph and Amazon
// structurally cannot show, so it gets the best position that isn't the title.

import * as ld from '../jsonld.js';
import {
  appBand,
  avatar,
  bookStrip,
  breadcrumb,
  byline,
  cover,
  coverSrc,
  section,
  stars,
} from '../components.js';
import { authorPath, bookPath, clamp, html, joinDot, num, publisherPath, raw, seg } from '../html.js';
import { page } from '../layout.js';

const LANG_PATH = (l) => `/language/${seg(String(l).toLowerCase())}`;

function translationModule(data) {
  const others = data.translations || [];
  if (!others.length && !data.original) return '';

  const cards = [];
  if (data.original) {
    cards.push(
      html`<a class="tcard orig" href="${bookPath(data.original)}">
        <span class="cvw">${cover(data.original, { width: 48 })}</span>
        <span class="ti">
          <span class="lg">${data.original.language || 'Original'} · the original</span>
          <span class="t">${data.original.title}</span>
          <span class="m">${joinDot([data.original.year, ratingLine(data.original)])}</span>
        </span>
      </a>`,
    );
  }
  for (const t of others) {
    cards.push(
      html`<a class="tcard${t.is_original ? ' orig' : ''}" href="${bookPath(t)}">
        <span class="cvw">${cover(t, { width: 48 })}</span>
        <span class="ti">
          <span class="lg">${t.language || 'Another language'}${t.is_original ? ' · the original' : ''}</span>
          <span class="t">${t.title}</span>
          <span class="m">${joinDot([t.year, ratingLine(t)])}</span>
        </span>
      </a>`,
    );
  }

  return html`<section class="sec">
    <div class="trans">
      <div class="rule"></div>
      <div class="tin">
        <div class="th">
          <h2 class="eyebrow" style="color:#8F681E">Read it in another language</h2>
          ${data.translation_group_rating
            ? html`<span class="grp"
                >Across all translations: <b>★ ${data.translation_group_rating.toFixed(1)}</b></span
              >`
            : ''}
        </div>
        <div class="tg">${cards}</div>
      </div>
    </div>
  </section>`;
}

function ratingLine(work) {
  if (!work?.rating) return '';
  return `★ ${work.rating.toFixed(1)}${work.rating_count ? ` · ${num(work.rating_count)}` : ''}`;
}

function editionsTable(editions) {
  if (!editions?.length) return '';
  return html`<div class="eds">
    ${editions.map(
      (e) => html`<div class="ed">
        ${cover({ title: e.publisher?.name || 'Edition', cover_url: e.cover_url }, { width: 44 })}
        <div>
          <div class="et">${e.publisher?.name || 'Unknown publisher'}</div>
          <div class="em">${joinDot([e.language, e.format])}</div>
        </div>
        <div class="col"><b>${e.year || '—'}</b>${e.isbn ? `ISBN ${e.isbn}` : 'No ISBN'}</div>
        <div class="col"><b>${e.page_count || '—'}</b>pages</div>
        <div>${e.series?.name ? html`<span class="pill p-slate">${e.series.name}</span>` : ''}</div>
      </div>`,
    )}
  </div>`;
}

function ratingsBlock(rating) {
  if (!rating?.count) return '';
  const dist = rating.distribution || {};
  const max = Math.max(1, ...Object.values(dist));
  return html`<div class="ratings">
    <div class="score">
      <div class="n">${rating.average ? rating.average.toFixed(1) : '—'}</div>
      <div>${stars(rating.average, 0)}</div>
      <div class="of">${num(rating.count)} ratings</div>
    </div>
    <div class="hist">
      ${[5, 4, 3, 2, 1].map((n) => {
        const count = dist[String(n)] || 0;
        return html`<div class="hbar">
          <span class="lb">${n} ★</span>
          <span class="tr"
            ><span class="fl" style="width:${Math.round((count / max) * 100)}%"></span
          ></span>
          <span class="ct">${num(count)}</span>
        </div>`;
      })}
    </div>
  </div>`;
}

function reviewsBlock(reviews) {
  if (!reviews?.length) return '';
  return html`${reviews.slice(0, 5).map(
    (r) => html`<article class="rev">
      <div class="rhd">
        ${avatar({ name: r.reviewer?.display_name || 'A reader' }, { className: 'av' })}
        <div>
          <div class="who">${r.reviewer?.display_name || 'A reader on Kitabi'}</div>
          ${r.created_at ? html`<div class="when">${String(r.created_at).slice(0, 10)}</div>` : ''}
        </div>
        ${r.rating
          ? html`<div class="rs" aria-label="${`Rated ${r.rating} out of 5`}">
              ${'★'.repeat(Math.round(r.rating))}
            </div>`
          : ''}
      </div>
      ${r.body ? html`<p class="rt">“${r.body}”</p>` : ''}
    </article>`,
  )}`;
}

function factsTable(data) {
  const rows = [];
  const add = (k, v) => v && rows.push(html`<div class="r"><span class="k">${k}</span><span class="v">${v}</span></div>`);
  add('Title', data.title);
  if (data.authors?.length) add('Author', byline(data.authors));
  if (data.translators?.length) add('Translators', byline(data.translators));
  if (data.language) add('Language', html`<a href="${LANG_PATH(data.language)}">${data.language}</a>`);
  add('First published', data.first_publish_year);
  add('Type', data.form);
  if (data.genres?.length) {
    add(
      'Genres',
      html`${data.genres.map(
        (g, i) => html`${i ? ', ' : ''}<a href="/genre/${seg(g.slug || g.name)}">${g.name}</a>`,
      )}`,
    );
  }
  add('Editions', data.editions?.length ? String(data.editions.length) : null);
  const publishers = [...new Set((data.editions || []).map((e) => e.publisher?.name).filter(Boolean))];
  if (publishers.length) {
    const refs = (data.editions || []).map((e) => e.publisher).filter(Boolean);
    const seen = new Set();
    add(
      'Publishers',
      html`${refs
        .filter((p) => !seen.has(p.id) && seen.add(p.id))
        .map((p, i) => html`${i ? ', ' : ''}<a href="${publisherPath(p)}">${p.name}</a>`)}`,
    );
  }
  if (!rows.length) return '';
  return html`<div class="ftab">${rows}</div>`;
}

/** The link's mark: the back of a book — blurb lines and a barcode. Drawn
 *  rather than photographed on purpose. These are reader photographs of real
 *  printings and run to half a megabyte; the proxy passes them through at full
 *  size (it has no resizer), so a thumbnail here would make every book page
 *  carry a second full-resolution image to render a 34px speck. The photograph
 *  loads when the reader asks for it, and not before. */
const BACK_MARK = raw(
  '<svg class="m" viewBox="0 0 24 34" aria-hidden="true" width="24" height="34">' +
    '<rect x="1.6" y="1" width="20.8" height="32" rx="2.4" fill="none" stroke="currentColor" stroke-width="1.5"/>' +
    '<path d="M6 8h12M6 12h12M6 16h9" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" opacity=".55"/>' +
    '<path d="M13 23v6M15 23v6M17 23v6M19 23v6" stroke="#B8862B" stroke-width="1.3" stroke-linecap="round"/>' +
    '</svg>',
);

/**
 * The hero cover, plus the back cover when the edition has one.
 *
 * A back cover is the one photograph no other catalogue shows, and on an
 * Indian-language printing it is usually where the blurb, the translator's
 * note and the price actually live — so it is worth more than a thumbnail the
 * reader can't read. It is offered as a captioned link under the front cover
 * and opens full-size in a `:target` overlay: both images are in the served
 * HTML, and the overlay is pure CSS, because the public site runs no JavaScript
 * to reveal content (docs/web-platform-plan.md rule 3).
 */
function coverBlock(work, edition) {
  const front = cover(work, { priority: true, width: 212 });
  if (!edition.back_cover_url) return html`<div>${front}</div>`;
  const src = coverSrc(edition.back_cover_url);
  return html`<div>
    ${front}
    <a class="bkc" href="#back-cover">
      ${BACK_MARK}
      <span class="l">Back cover<span class="s">The blurb, as printed</span></span>
      <span class="go" aria-hidden="true">→</span>
    </a>
    <div class="lb" id="back-cover">
      <a class="lbx" href="#main" aria-label="Close">×</a>
      <figure>
        <img src="${src}" alt="${`Back cover of ${work.title}`}" loading="lazy" decoding="async" />
        <figcaption>Back cover · ${work.title}</figcaption>
      </figure>
    </div>
  </div>`;
}

export function renderBook(data) {
  const primaryEdition = (data.editions || []).find((e) => e.cover_url) || data.editions?.[0] || {};
  const heroWork = {
    title: data.title,
    cover_url: primaryEdition.cover_url,
    authors: data.authors,
  };
  const authorNames = (data.authors || []).map((a) => a.name).join(', ');
  const canonical = bookPath(data);

  const crumbs = [{ label: 'Home', href: '/' }];
  if (data.language) crumbs.push({ label: data.language, href: LANG_PATH(data.language) });
  crumbs.push({ label: data.title });

  // The ISBN goes in the meta description, and the blurb is clamped to leave
  // room for it rather than the other way round.
  //
  // Someone searching an ISBN is holding the book — the highest-intent query
  // this site can receive — and until this line the number lived only in the
  // page's body text, where it carries almost no weight. `<title>` is the
  // stronger signal still, but it belongs to the title and author: a number
  // there would cost every reader-facing query to win one machine-facing one.
  // The description is the slot where both fit.
  const isbnSuffix = primaryEdition.isbn ? ` · ISBN ${primaryEdition.isbn}` : '';
  const blurbBudget = 155 - isbnSuffix.length;
  const description =
    (clamp(data.description, blurbBudget) ||
      joinDot([
        authorNames ? `by ${authorNames}` : null,
        data.language,
        data.form,
        data.first_publish_year,
      ]) ||
      `${data.title} on Kitabi.`) + isbnSuffix;

  const body = html`
    <div class="wrap">
      ${breadcrumb(crumbs)}

      <div class="bhero">
        ${coverBlock(heroWork, primaryEdition)}

        <div>
          <h1>${data.title}</h1>
          ${data.subtitle ? html`<p class="native">${data.subtitle}</p>` : ''}
          ${data.authors?.length ? html`<p class="by">by ${byline(data.authors)}</p>` : ''}
          ${data.translators?.length
            ? html`<p class="by"><span class="tr">Translated by ${byline(data.translators)}</span></p>`
            : ''}
          ${data.rating?.average
            ? html`<div class="rating-row">
                <span class="big">${data.rating.average.toFixed(1)}<span> / 5</span></span>
                ${stars(data.rating.average, data.rating.count)}
              </div>`
            : ''}
          <p class="facts">
            ${data.first_publish_year ? html`<span><b>${data.first_publish_year}</b> first published</span>` : ''}
            ${data.language ? html`<span><b>${data.language}</b></span>` : ''}
            ${data.form ? html`<span><b>${data.form}</b></span>` : ''}
            ${primaryEdition.page_count ? html`<span><b>${primaryEdition.page_count}</b> pages</span>` : ''}
            ${data.editions?.length ? html`<span><b>${data.editions.length}</b> editions</span>` : ''}
          </p>
          ${data.genres?.length
            ? html`<p class="chips" style="margin-top:14px">
                ${data.genres.map(
                  (g) => html`<a class="chip" href="/genre/${seg(g.slug || g.name)}">${g.name}</a>`,
                )}
              </p>`
            : ''}
          ${data.description ? html`<p class="blurb">${data.description}</p>` : ''}
          <p class="act"><a class="prim" href="/app">Track this in Kitabi</a></p>
        </div>

        <div>
          ${primaryEdition.buy_links?.length
            ? html`<div class="rail">
                <h2 class="rh">Get this book</h2>
                <div class="rb" style="padding:12px 15px 6px">
                  ${primaryEdition.buy_links.map(
                    (b) => html`<a class="amzn" href="${b.url}"
                      rel="${b.affiliate ? 'sponsored nofollow noopener' : 'nofollow noopener'}"
                      ><span class="wm" aria-hidden="true"
                        >amazon${raw(
                          '<svg class="sm" viewBox="0 0 54 13" aria-hidden="true">' +
                            '<path d="M2 3c11 8 32 8 46 1.5" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"/>' +
                            '<path d="M44.5 1.5l5.3 2.6-3.6 4.4" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>' +
                            '</svg>',
                        )}</span
                      ><span class="go">Buy on Amazon.in <span aria-hidden="true">→</span></span></a
                    >`,
                  )}
                  ${primaryEdition.buy_links.some((b) => b.affiliate)
                    ? html`<p class="buydisc">Kitabi may earn a commission from bookseller links.</p>`
                    : ''}
                </div>
              </div>`
            : ''}
          ${primaryEdition.id
            ? html`<div class="rail">
                <h2 class="rh">This edition</h2>
                <div class="rb">
                  ${primaryEdition.publisher
                    ? html`<div class="kv">
                        <span class="k">Publisher</span>
                        <a class="v" href="${publisherPath(primaryEdition.publisher)}"
                          >${primaryEdition.publisher.name}</a
                        >
                      </div>`
                    : ''}
                  ${primaryEdition.year ? html`<div class="kv"><span class="k">Published</span><span class="v">${primaryEdition.year}</span></div>` : ''}
                  ${primaryEdition.isbn ? html`<div class="kv"><span class="k">ISBN</span><span class="v">${primaryEdition.isbn}</span></div>` : ''}
                  ${primaryEdition.page_count ? html`<div class="kv"><span class="k">Pages</span><span class="v">${primaryEdition.page_count}</span></div>` : ''}
                  ${primaryEdition.format ? html`<div class="kv"><span class="k">Format</span><span class="v">${primaryEdition.format}</span></div>` : ''}
                </div>
              </div>`
            : ''}
          <div class="rail dark">
            <h2 class="rh">On your shelf?</h2>
            <div class="rb">
              Track it, log your reading, and lend it to a friend — without losing it.
              <a class="btn-ghost" style="display:block;text-align:center;margin-top:12px;background:#B8862B;border-color:#B8862B;color:#241811" href="/app">Open in Kitabi</a>
            </div>
          </div>
        </div>
      </div>

      ${translationModule(data)}
      ${section(
        data.editions?.length === 1 ? '1 edition' : `All ${data.editions?.length || 0} editions`,
        editionsTable(data.editions),
      )}
      ${data.rating?.count
        ? section('What readers said', html`${ratingsBlock(data.rating)}${reviewsBlock(data.reviews)}`)
        : ''}
      ${data.more_by_author?.length
        ? section(
            `More by ${(data.authors || [])[0]?.name || 'this author'}`,
            bookStrip(data.more_by_author),
            { more: data.authors?.[0] ? authorPath(data.authors[0]) : null, moreLabel: 'All works' },
          )
        : ''}
      ${data.related?.length ? section('Readers also shelved', bookStrip(data.related)) : ''}
      ${section('The facts', factsTable(data))}
      ${appBand()}
    </div>
  `;

  return page({
    title: `${data.title}${authorNames ? ` by ${authorNames}` : ''} — Kitabi`,
    description,
    canonical,
    image: primaryEdition.cover_url || null,
    ogType: 'book',
    body,
    indexable: data.indexable !== false,
    nav: 'books',
    jsonLd: [ld.book(data), ld.breadcrumbList(crumbs)],
  });
}
