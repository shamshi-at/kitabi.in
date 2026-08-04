// Search, browse, and the genre/language hubs (mockups W2, W6, W7).
//
// Search and browse are `noindex, follow`: they generate infinite near-duplicate
// URLs, and indexing them is the single most common way a catalog site gets
// itself demoted. Every result on them is still a crawlable link, so the equity
// flows through.
//
// The hubs ARE indexed, because they are the pages that win queries nobody owns
// — "Malayalam novels", "Tamil short stories". They are one template with a
// different filter, which is how the mockups draw them.

import * as ld from '../jsonld.js';
import { appBand, avatar, bookStrip, breadcrumb, cover, pager, section } from '../components.js';
import { authorPath, bookPath, clamp, html, joinDot, num, publisherPath, seg } from '../html.js';
import { page } from '../layout.js';

// Editorial intros live here, not in the API: they are content, not data, and
// keeping them in the renderer means writing one doesn't need a backend deploy.
// A hub without one is a thin auto-generated list, which is exactly what the
// content-floor rule exists to avoid — so a hub with no intro still renders,
// but writing these is the difference between a page and a directory listing.
const HUB_INTROS = {
  malayalam: `Malayalam has one of the shortest and densest literary histories in India: a written novel tradition barely 140 years old, six Jnanpith laureates, and a readership that made a state of 35 million people the most book-buying in the country. It is also the Indian language whose fiction travels best — Chemmeen reached English in 1962, Goat Days in 2012, and in between an entire canon was carried across by translators who are only now being credited on the cover.`,
  tamil: `Tamil has the longest continuous literary record of any Indian language — Sangam poetry predates most of what survives elsewhere by centuries — and a modern prose tradition that arrived late and then moved very fast. What collects here runs from the historical epics that everyone's grandmother read in weekly instalments to the spare, difficult fiction of the Tamil New Wave.`,
  bengali: `Bengali fiction invented the modern Indian novel and then spent a century arguing with itself about it. The tradition runs from Bankim and Tagore through the village realism of Bibhutibhushan to the political fiction of the 1970s, and it is unusually well served by translation into English.`,
  hindi: `Hindi's literary tradition carries the weight of being both a regional literature and, awkwardly, a national one. The fiction here runs from Premchand's village realism through the Nayi Kahani writers to contemporary novelists working in a language that is spoken by far more people than read it.`,
};

function facetList(title, items, hrefFor, current) {
  if (!items?.length) return '';
  return html`<div style="margin-bottom:14px">
    <h2 style="font-size:9.5px;letter-spacing:.18em;text-transform:uppercase;color:#7A6A55;margin-bottom:10px">
      ${title}
    </h2>
    <p class="chips">
      ${items
        .slice(0, 14)
        .map(
          (i) => html`<a class="chip"${i.slug === current ? ' aria-current="true"' : ''}
            href="${hrefFor(i)}">${i.name} <span style="opacity:.6">${num(i.count)}</span></a>`,
        )}
    </p>
  </div>`;
}

// --------------------------------------------------------------------------
// Search
// --------------------------------------------------------------------------

export function renderSearch(data) {
  const q = data.q || '';
  const total = (data.works?.length || 0) + (data.authors?.length || 0) + (data.publishers?.length || 0);

  const results = total
    ? html`
        ${data.works?.length
          ? html`<div class="sgroup">
              <div class="sgh"><h2>Books</h2><span class="ct">${data.works.length}</span></div>
              ${data.works.map(
                (w) => html`<a class="srow" href="${bookPath(w)}">
                  <span class="cvw">${cover(w, { width: 52 })}</span>
                  <span class="si">
                    <span class="st">${w.title}</span>
                    <span class="sa"
                      >${joinDot([
                        (w.authors || []).map((a) => a.name).join(', '),
                        w.language,
                        w.form,
                        w.year,
                      ])}</span
                    >
                    ${w.rating
                      ? html`<span class="sm"><span>★ ${w.rating.toFixed(1)}</span></span>`
                      : ''}
                  </span>
                </a>`,
              )}
            </div>`
          : ''}
        ${data.authors?.length
          ? html`<div class="sgroup">
              <div class="sgh"><h2>Authors</h2><span class="ct">${data.authors.length}</span></div>
              ${data.authors.map(
                (a) => html`<a class="srow" href="${authorPath(a)}">
                  ${avatar(a)}
                  <span class="si"><span class="st">${a.name}</span></span>
                </a>`,
              )}
            </div>`
          : ''}
        ${data.publishers?.length
          ? html`<div class="sgroup">
              <div class="sgh"><h2>Publishers</h2><span class="ct">${data.publishers.length}</span></div>
              ${data.publishers.map(
                (p) => html`<a class="srow" href="${publisherPath(p)}">
                  ${avatar(p)}
                  <span class="si"><span class="st">${p.name}</span></span>
                </a>`,
              )}
            </div>`
          : ''}
      `
    : html`<div class="thin">
        <div class="fl">❦</div>
        <h2>Nothing for “${q}”</h2>
        <p>
          We searched titles in every script in the catalogue and their romanizations. If the book
          exists and isn't here yet, you can add it from the app — scan the ISBN and it's catalogued
          in seconds.
        </p>
        <a class="btn-ghost" style="margin-top:15px" href="/browse">Browse everything instead</a>
      </div>`;

  const body = html`
    <div class="wrap" style="padding-top:22px">
      <h1 class="serif" style="font-size:26px;font-weight:600">
        ${total ? `${total} results for` : 'Nothing for'} <span style="color:#7E2A33">“${q}”</span>
      </h1>
      ${data.matched_scripts?.length
        ? html`<p style="margin-top:8px">
            <span class="matchline"
              >✓ also matched ${data.matched_scripts.join(', ')} — spelling-insensitive across
              scripts</span
            >
          </p>`
        : ''}
      <div class="sres">
        <div>${results}</div>
        <aside>
          <div class="facets">
            <h2>Not here?</h2>
            <p style="font-size:12.5px;color:#7A6A55;line-height:1.65">
              Any reader can add a book to the catalogue from the Kitabi app — scan the ISBN and
              it's here in seconds.
            </p>
            <a class="btn-ghost" style="margin-top:11px" href="/app">Add a book →</a>
          </div>
        </aside>
      </div>
    </div>
  `;

  return page({
    title: `“${q}” — search — Kitabi`,
    description: `Search results for “${q}” on Kitabi.`,
    canonical: `/search?q=${encodeURIComponent(q)}`,
    body,
    q,
    // Search pages generate infinite near-duplicate URLs. Never indexed;
    // always followed, so every result still passes equity through.
    indexable: false,
  });
}

// --------------------------------------------------------------------------
// Browse
// --------------------------------------------------------------------------

export function renderBrowse(data, { query = {} } = {}) {
  const hrefFor = (p) => {
    const params = new URLSearchParams(query);
    params.set('page', String(p));
    return `/browse?${params.toString()}`;
  };
  const first = (data.page - 1) * data.per_page + 1;
  const last = Math.min(data.page * data.per_page, data.total);

  const body = html`
    <div class="wrap">
      ${breadcrumb([{ label: 'Home', href: '/' }, { label: 'Browse' }])}
      <h1 class="serif" style="font-size:30px;font-weight:600;margin-top:14px">Browse the catalogue</h1>
      <div class="toolbar">
        <a class="chip"${!query.language ? ' aria-current="true"' : ''} href="/browse">All</a>
        ${(data.languages || []).slice(0, 8).map(
          (l) => html`<a class="chip" href="/language/${seg(l.slug)}">${l.name}</a>`,
        )}
        <span class="cnt"
          >${data.total ? `Showing ${num(first)}–${num(last)} of ${num(data.total)}` : 'Nothing here'}</span
        >
      </div>
      ${data.works?.length
        ? html`${bookStrip(data.works, { priorityFirst: true })}${pager(
            data.page,
            data.total,
            data.per_page,
            hrefFor,
          )}`
        : html`<div class="thin">
            <div class="fl">❦</div>
            <h2>Nothing matches those filters</h2>
            <p>Try widening them, or browse a language hub instead.</p>
          </div>`}
      ${appBand()}
    </div>
  `;

  return page({
    title: `Browse — page ${data.page} — Kitabi`,
    description: 'Browse every book in the Kitabi catalogue by language, type and genre.',
    canonical: null,
    body,
    nav: 'books',
    // Faceted browse explodes combinatorially; only the canonical hubs are
    // indexed. Still followed, so the catalogue stays fully crawlable.
    indexable: false,
  });
}

// --------------------------------------------------------------------------
// Hubs — genre, language, language+form
// --------------------------------------------------------------------------

export function renderHub(data) {
  const isLanguage = data.kind === 'language';
  const base = `/${data.kind}/${seg(data.slug)}`;
  const path = data.form ? `${base}/${seg(data.form.toLowerCase())}` : base;
  const hrefFor = (p) => (p === 1 ? path : `${path}?page=${p}`);

  const heading = data.form ? `${data.name} ${data.form.toLowerCase()}` : data.name;
  const intro = HUB_INTROS[data.slug];
  const first = (data.page - 1) * data.per_page + 1;
  const last = Math.min(data.page * data.per_page, data.total);

  const crumbs = [
    { label: 'Home', href: '/' },
    { label: isLanguage ? 'Languages' : 'Genres', href: isLanguage ? '/languages' : '/genres' },
    ...(data.form ? [{ label: data.name, href: base }, { label: data.form }] : [{ label: data.name }]),
  ];

  const body = html`
    <div class="hubhead">
      <div class="wrap hubhead-in">
        <div>
          <p class="eyebrow">${isLanguage ? 'Language' : 'Genre'} · ${num(data.total)} books</p>
          <h1>${heading}${isLanguage && !data.form ? ' literature' : ''}</h1>
          ${intro ? html`<p class="intro">${intro}</p>` : ''}
          ${isLanguage && data.forms?.length
            ? html`<p class="chips" style="margin-top:16px">
                ${data.forms
                  .slice(0, 8)
                  .map(
                    (f) => html`<a class="chip"${data.form === f.name ? ' aria-current="true"' : ''}
                      href="${base}/${seg(f.slug)}">${f.name}</a>`,
                  )}
              </p>`
            : ''}
        </div>
        <div class="hubstats">
          <div class="st"><span class="k">Works</span><b>${num(data.total)}</b></div>
          ${isLanguage
            ? html`<div class="st"><span class="k">Forms</span><b>${data.forms?.length || 0}</b></div>`
            : html`<div class="st"><span class="k">Languages</span><b>${data.languages?.length || 0}</b></div>`}
        </div>
      </div>
    </div>

    <div class="wrap">
      ${data.start_here?.length && data.page === 1
        ? section('Start here', bookStrip(data.start_here, { priorityFirst: true }))
        : ''}
      <section class="sec">
        <div class="toolbar">
          ${!isLanguage
            ? (data.languages || [])
                .slice(0, 6)
                .map((l) => html`<a class="chip" href="/language/${seg(l.slug)}">${l.name}</a>`)
            : ''}
          <span class="cnt">Showing ${num(first)}–${num(last)} of ${num(data.total)}</span>
        </div>
        ${bookStrip(data.works, { priorityFirst: !data.start_here?.length })}
        ${pager(data.page, data.total, data.per_page, hrefFor)}
      </section>
      ${appBand()}
    </div>
  `;

  const pageSuffix = data.page > 1 ? ` — page ${data.page}` : '';
  return page({
    title: `${heading}${isLanguage && !data.form ? ' literature' : ''} — ${num(data.total)} books${pageSuffix} — Kitabi`,
    description: clamp(
      intro || `Every ${heading} book in the Kitabi catalogue — ${num(data.total)} works.`,
      160,
    ),
    // Each page self-canonicals. NEVER canonicalise page 2 back to page 1 —
    // that de-indexes the deep catalogue, which is most of it.
    canonical: hrefFor(data.page),
    body,
    nav: isLanguage ? 'languages' : 'books',
    jsonLd: [
      ld.collectionPage(heading, intro, hrefFor(data.page)),
      ld.breadcrumbList(crumbs),
      ...(data.works?.length ? [ld.itemList(data.works, heading)] : []),
    ],
  });
}

// --------------------------------------------------------------------------
// Index pages — the hub directories the header links to
// --------------------------------------------------------------------------

export function renderIndex({ title, description, kind, items, hrefFor, canonical }) {
  const body = html`
    <div class="wrap">
      ${breadcrumb([{ label: 'Home', href: '/' }, { label: title }])}
      <h1 class="serif" style="font-size:30px;font-weight:600;margin-top:14px">${title}</h1>
      <p class="intro">${description}</p>
      <section class="sec">
        ${items?.length
          ? html`<div class="langs">
              ${items.map(
                (i) => html`<a class="lang" href="${hrefFor(i)}">
                  <span class="n">${i.name}</span>
                  <span class="c">${num(i.count)} books</span>
                </a>`,
              )}
            </div>`
          : html`<div class="thin"><p>Nothing here yet.</p></div>`}
      </section>
      ${appBand()}
    </div>
  `;
  return page({
    title: `${title} — Kitabi`,
    description,
    canonical,
    body,
    nav: kind,
    jsonLd: [ld.collectionPage(title, description, canonical)],
  });
}

// --------------------------------------------------------------------------
// /authors and /publishers — the directories the header links to
// --------------------------------------------------------------------------

export function renderPeople(data) {
  const isAuthors = data.kind === 'authors';
  const title = isAuthors ? 'Authors' : 'Publishers';
  const path = `/${data.kind}`;
  const hrefFor = (p) => (p === 1 ? path : `${path}?page=${p}`);
  const first = (data.page - 1) * data.per_page + 1;
  const last = Math.min(data.page * data.per_page, data.total);

  const body = html`
    <div class="wrap">
      ${breadcrumb([{ label: 'Home', href: '/' }, { label: title }])}
      <h1 class="serif" style="font-size:30px;font-weight:600;margin-top:14px">${title}</h1>
      <p class="intro">
        ${isAuthors
          ? 'Everyone in the catalogue who has written, translated or been credited on a book — most-published first.'
          : 'Every house with a book in the catalogue, from the national imprints to the regional presses that publish most of what is here.'}
      </p>
      <div class="toolbar">
        <span class="cnt">Showing ${num(first)}–${num(last)} of ${num(data.total)}</span>
      </div>
      ${data.people?.length
        ? html`<div class="strip" style="grid-template-columns:repeat(auto-fill,minmax(150px,1fr))">
              ${data.people.map(
                (p) => html`<a class="bk" style="text-align:center"
                  href="/${isAuthors ? 'author' : 'publisher'}/${seg(p.slug || p.id)}">
                  ${avatar(p, { className: 'ppl' })}
                  <span class="bt">${p.name}</span>
                  ${p.work_count
                    ? html`<span class="ba">${num(p.work_count)} ${p.work_count === 1 ? 'book' : 'books'}</span>`
                    : ''}
                </a>`,
              )}
            </div>
            ${pager(data.page, data.total, data.per_page, hrefFor)}`
        : html`<div class="thin"><p>Nothing here yet.</p></div>`}
      ${appBand()}
    </div>
  `;

  const suffix = data.page > 1 ? ` — page ${data.page}` : '';
  return page({
    title: `${title} — ${num(data.total)} in the catalogue${suffix} — Kitabi`,
    description: isAuthors
      ? `Every author in the Kitabi catalogue — ${num(data.total)} writers and translators across Indian languages.`
      : `Every publisher in the Kitabi catalogue — ${num(data.total)} houses.`,
    canonical: hrefFor(data.page),
    body,
    nav: data.kind,
    jsonLd: [ld.collectionPage(title, null, hrefFor(data.page))],
  });
}
