// The app's own pages: /compare, /compare/:slug, /lending-tracker and /ml/app.
//
// Everything on them is content from ../guides.js; nothing here calls the API,
// so they cost no origin queries and cannot 503. The rules for what may be
// written on them are at the top of guides.js — read those before editing a
// row of a comparison.

import { appBand, breadcrumb, storeButtons } from '../components.js';
import {
  CHECKED,
  COMPARISONS,
  KITABI_FACTS,
  KITABI_IN_BRIEF,
  LENDING,
  MALAYALAM,
} from '../guides.js';
import { html, raw, seg } from '../html.js';
import * as ld from '../jsonld.js';
import { ORIGIN, page } from '../layout.js';

const GD_MONTHS = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/** "2026-10-16" → "16 October 2026", without Intl. */
function gdDate(iso) {
  const [y, m, d] = String(iso).split('-').map(Number);
  return `${d} ${GD_MONTHS[m - 1]} ${y}`;
}

const comparePath = (slug) => `/compare/${seg(slug)}`;

/** The box beside every English hero: what Kitabi is, in seven lines. */
function gdGlance() {
  return html`<aside class="hubstats gdg" aria-label="Kitabi at a glance">
    <p class="eyebrow">Kitabi at a glance</p>
    <ul>
      ${KITABI_FACTS.map((fact) => html`<li>${fact}</li>`)}
    </ul>
    <a class="btn-app" href="/app">See the app</a>
  </aside>`;
}

function gdHero({ crumbs, eyebrow, h1, lede }) {
  return html`<div class="hubhead">
    <div class="wrap">
      ${breadcrumb(crumbs)}
      <div class="hubhead-in" style="margin-top:14px">
        <div>
          <p class="eyebrow">${eyebrow}</p>
          <h1 style="margin-top:8px">${h1}</h1>
          ${lede.map((p) => html`<p class="intro">${p}</p>`)}
        </div>
        ${gdGlance()}
      </div>
    </div>
  </div>`;
}

function gdProse(title, paragraphs) {
  return html`<section class="sec gdp">
    <div class="sec-h"><h2>${title}</h2></div>
    ${paragraphs.map((p) => html`<p>${p}</p>`)}
  </section>`;
}

/** Questions as visible headings and answers. The FAQPage JSON-LD is built
 *  from the same array, so the markup can never claim what the page doesn't
 *  show. */
function gdFaq(items, title = 'Questions') {
  return html`<section class="sec gdq">
    <div class="sec-h"><h2>${title}</h2></div>
    ${items.map((item) => html`<h3>${item.q}</h3><p>${item.a}</p>`)}
  </section>`;
}

function gdAbout() {
  return gdProse('What is Kitabi?', [KITABI_IN_BRIEF]);
}

/** Links between the app pages, so each one is two clicks from every other. */
function gdMore(currentPath) {
  const links = [
    ...COMPARISONS.map((c) => ({ href: comparePath(c.slug), label: `Kitabi vs ${c.name}` })),
    { href: '/lending-tracker', label: 'Book lending tracker' },
    { href: '/compare', label: 'All comparisons' },
  ].filter((link) => link.href !== currentPath);
  return html`<section class="sec">
    <div class="sec-h"><h2>More about Kitabi</h2></div>
    <p class="chips">
      ${links.map((link) => html`<a class="chip" href="${link.href}">${link.label}</a>`)}
    </p>
  </section>`;
}

// --------------------------------------------------------------------------
// /compare/:slug
// --------------------------------------------------------------------------

export function renderCompare(c) {
  const canonical = comparePath(c.slug);
  const crumbs = [
    { label: 'Home', href: '/' },
    { label: 'Compare', href: '/compare' },
    { label: `Kitabi vs ${c.name}` },
  ];
  const checked = gdDate(CHECKED);

  const body = html`
    ${gdHero({ crumbs, eyebrow: `Kitabi vs ${c.name}`, h1: c.h1, lede: c.lede })}
    <div class="wrap">
      <section class="sec">
        <div class="sec-h"><h2>Side by side</h2></div>
        <table class="gdt">
          <caption class="sr">Kitabi and ${c.name} compared</caption>
          <thead>
            <tr><td></td><th scope="col">Kitabi</th><th scope="col">${c.name}</th></tr>
          </thead>
          <tbody>
            ${c.rows.map(
              (row) => html`<tr>
                <th scope="row">${row.k}</th>
                <td data-l="Kitabi">${row.us}</td>
                <td data-l="${c.name}">${row.them}</td>
              </tr>`,
            )}
          </tbody>
        </table>
        <p class="gdnote">
          ${c.name}'s column is taken from ${c.name}'s own pages, read on ${checked} — they are
          listed under Sources below.
        </p>
      </section>

      ${c.sections.map((s) => gdProse(s.h, s.p))}
      ${gdProse(`When ${c.name} is the better choice`, [c.betterFor])}
      ${gdFaq(c.faq)}
      ${gdAbout()}

      <section class="sec gdsrc">
        <div class="sec-h"><h2>Sources</h2></div>
        <ul>
          ${c.sources.map(
            (s) => html`<li><a href="${s.url}" rel="nofollow noopener">${s.label}</a></li>`,
          )}
        </ul>
        <p>
          Read on ${checked}. Prices and features change — check ${c.name}'s own site before you
          decide.
        </p>
      </section>

      ${gdMore(canonical)} ${appBand()}
    </div>
  `;

  return page({
    title: c.title,
    description: c.description,
    canonical,
    body,
    jsonLd: [ld.breadcrumbList(crumbs), ld.faqPage(c.faq, canonical)],
  });
}

// --------------------------------------------------------------------------
// /compare
// --------------------------------------------------------------------------

export function renderCompareIndex() {
  const crumbs = [{ label: 'Home', href: '/' }, { label: 'Compare' }];
  const description =
    "How Kitabi, a free personal library app, compares with Goodreads, Libib and LibraryThing — checked against each app's own pages, including where they do more.";

  const body = html`
    ${gdHero({
      crumbs,
      eyebrow: 'Personal library apps',
      h1: 'Kitabi compared with other personal library apps',
      lede: [
        "There are good apps for keeping track of books, and they don't all do the same job. These pages set Kitabi beside the three readers ask about most, using each app's own pages as the source, and say plainly where the other app is the better choice.",
      ],
    })}
    <div class="wrap">
      <section class="sec">
        <div class="gdl gd4">
          ${COMPARISONS.map(
            (c) => html`<a class="gdcard" href="${comparePath(c.slug)}">
              <span class="eyebrow">Kitabi vs ${c.name}</span>
              <span class="gdct">${c.h1}</span>
              <span class="gdcp">${c.description}</span>
            </a>`,
          )}
          <a class="gdcard" href="/lending-tracker">
            <span class="eyebrow">Lending</span>
            <span class="gdct">${LENDING.h1}</span>
            <span class="gdcp">${LENDING.description}</span>
          </a>
        </div>
      </section>
      ${gdAbout()} ${appBand()}
    </div>
  `;

  return page({
    title: 'Personal library apps: Kitabi vs Goodreads, Libib, LibraryThing',
    description,
    canonical: '/compare',
    body,
    jsonLd: [
      ld.collectionPage('Personal library apps compared', description, '/compare'),
      ld.breadcrumbList(crumbs),
    ],
  });
}

// --------------------------------------------------------------------------
// /lending-tracker
// --------------------------------------------------------------------------

export function renderLendingTracker() {
  const canonical = '/lending-tracker';
  const crumbs = [{ label: 'Home', href: '/' }, { label: 'Book lending tracker' }];

  const body = html`
    ${gdHero({ crumbs, eyebrow: 'Book lending tracker', h1: LENDING.h1, lede: LENDING.lede })}
    <div class="wrap">
      <section class="sec">
        <div class="sec-h"><h2>How it works</h2></div>
        <ol class="gdl gd4 gdsteps">
          ${LENDING.steps.map((step) => html`<li><h3>${step.h}</h3><p>${step.p}</p></li>`)}
        </ol>
      </section>
      ${LENDING.sections.map((s) => gdProse(s.h, s.p))} ${gdFaq(LENDING.faq)} ${gdAbout()}
      ${gdMore(canonical)} ${appBand()}
    </div>
  `;

  return page({
    title: LENDING.title,
    description: LENDING.description,
    canonical,
    body,
    jsonLd: [ld.breadcrumbList(crumbs), ld.faqPage(LENDING.faq, canonical)],
  });
}

// --------------------------------------------------------------------------
// /ml/app
// --------------------------------------------------------------------------

/** The English and Malayalam pitches name each other, so a search engine
 *  serves each reader the one in their language. /app carries the same three
 *  lines by hand (landing-page/app.html) — keep the pair reciprocal, or the
 *  annotation is ignored. */
export const APP_HREFLANG = raw(
  `<link rel="alternate" hreflang="en" href="${ORIGIN}/app">` +
    `<link rel="alternate" hreflang="ml" href="${ORIGIN}/ml/app">` +
    `<link rel="alternate" hreflang="x-default" href="${ORIGIN}/app">`,
);

export function renderMalayalamApp() {
  const canonical = '/ml/app';
  const m = MALAYALAM;
  const stores = storeButtons({ play: m.cta.play, apple: m.cta.apple });

  const body = html`
    <div class="gdml">
      <div class="hubhead">
        <div class="wrap">
          <p class="eyebrow">${m.eyebrow}</p>
          <h1 style="margin-top:8px">${m.h1}</h1>
          ${m.lede.map((p) => html`<p class="intro">${p}</p>`)}
          <div class="appband" style="margin-top:18px;padding:16px 18px">
            <div class="stores">${stores}</div>
          </div>
          <p class="gdnote" lang="en">
            Reading in English? <a href="/app" hreflang="en">See the app page in English</a>.
          </p>
        </div>
      </div>
      <div class="wrap">
        <section class="sec">
          <div class="gdl">
            ${m.features.map((f) => html`<div class="gdbox"><h2>${f.h}</h2><p>${f.p}</p></div>`)}
          </div>
        </section>
        ${gdFaq(m.faq, 'ചോദ്യങ്ങൾ')}
        <section class="sec">
          <div class="appband">
            <div>
              <h2>${m.cta.h}</h2>
              <p>${m.cta.p}</p>
            </div>
            <div class="stores">${stores}</div>
          </div>
        </section>
      </div>
    </div>
  `;

  return page({
    title: m.title,
    description: m.description,
    canonical,
    body,
    lang: 'ml',
    extraHead: APP_HREFLANG,
    jsonLd: [ld.faqPage(m.faq, canonical, 'ml')],
  });
}
