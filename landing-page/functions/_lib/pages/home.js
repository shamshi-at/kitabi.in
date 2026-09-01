// The front door (mockup W1).
//
// A book site's home page IS a search box; everything under it is proof the
// site has answers. The language grid is not decoration — it is the crawl
// architecture: home links every hub, each hub links its books, so no indexable
// page is more than three clicks from the root. A new domain's crawl budget is
// small and a shallow graph is the cheapest way to spend it well.

import * as ld from '../jsonld.js';
import { appBand, bookStrip, cover, section } from '../components.js';
import { bookPath, clamp, html, joinDot, num, plural, seg } from '../html.js';
import { page } from '../layout.js';

function languageGrid(languages) {
  if (!languages?.length) return '';
  return html`<div class="langs">
    ${languages.slice(0, 14).map(
      (l) => html`<a class="lang" href="/language/${seg(l.slug)}">
        <span class="n">${l.name}</span>
        <span class="c">${plural(l.count, 'book')}</span>
      </a>`,
    )}
  </div>`;
}

function translationPairs(pairs) {
  if (!pairs?.length) return '';
  return html`<div class="pairs">
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
  </div>`;
}

export function renderHome(data) {
  const featured = data.featured;
  const langNames = (data.languages || []).slice(0, 3).map((l) => l.name);

  const body = html`
    <div class="hhero">
      <div class="wrap hhero-in">
        <div class="hh-l">
          <h1>Every book you've read,<br />and <em>every language</em> it lives in.</h1>
          <p>
            A reference library for Indian literature — ${plural(data.work_count, 'work')},
            ${plural(data.author_count, 'author')}, in ${data.languages?.length || 0} languages, with the
            translations traced both ways.
          </p>
          <form class="bigsearch" action="/search" method="get" role="search">
            <label class="sr" for="hq">Search books, authors and publishers</label>
            <input id="hq" name="q" type="search" placeholder="Try a title, an author, or an ISBN…" />
            <button type="submit">Search</button>
          </form>
          ${langNames.length
            ? html`<p class="hint">
                Type in English — we'll find it in ${langNames.map(
                  (n, i) => html`${i ? ', ' : ''}<b>${n}</b>`,
                )} and more.
              </p>`
            : ''}
        </div>
        ${featured
          ? html`<a class="feat" href="${bookPath(featured)}">
              <span class="cvw">${cover(featured, { priority: true, width: 96 })}</span>
              <span>
                <span class="eyebrow" style="color:#B8862B">From the reading room</span>
                <h2>${featured.title}</h2>
                <span class="fa"
                  >${joinDot([
                    (featured.authors || []).map((a) => a.name).join(', '),
                    featured.year,
                    featured.language,
                  ])}</span
                >
              </span>
            </a>`
          : ''}
      </div>
    </div>

    <div class="wrap">
      ${section('Browse by language', languageGrid(data.languages), {
        more: '/languages',
        moreLabel: 'All languages',
      })}
      ${data.translation_pairs?.length
        ? section('Read it in another language', translationPairs(data.translation_pairs), {
            more: '/translations',
            moreLabel: 'The translation index',
          })
        : ''}
      ${data.recent?.length
        ? section('Recently added', bookStrip(data.recent), {
            more: '/browse?sort=year_desc',
            moreLabel: 'Everything new',
          })
        : ''}
      ${data.top_rated?.length
        ? section('Highest rated', bookStrip(data.top_rated), {
            more: '/browse',
            moreLabel: 'Browse all',
          })
        : ''}
      ${data.genres?.length
        ? section(
            'By genre',
            html`<p class="chips">
              ${data.genres
                .slice(0, 24)
                .map(
                  (g) =>
                    html`<a class="chip" href="/genre/${seg(g.slug)}"
                      >${g.name} <span style="opacity:.6">${num(g.count)}</span></a
                    >`,
                )}
            </p>`,
            { more: '/genres', moreLabel: 'All genres' },
          )
        : ''}
      ${appBand()}
    </div>
  `;

  return page({
    title: 'Kitabi — a reference library for Indian literature',
    description: clamp(
      `${plural(data.work_count, 'work')} and ${plural(data.author_count, 'author')} across ${
        data.languages?.length || 0
      } Indian languages, with translations traced in both directions. Search a book, an author or a publisher.`,
      160,
    ),
    canonical: '/',
    body,
    nav: null,
    jsonLd: [ld.website(), ld.organization()],
  });
}
