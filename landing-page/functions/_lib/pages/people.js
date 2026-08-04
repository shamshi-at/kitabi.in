// Author and publisher pages (mockups W4, W5).
//
// Both are low-competition, high-intent: "Thakazhi Sivasankara Pillai books"
// currently returns a Wikipedia stub and Amazon listings, and nobody writes good
// pages about regional publishers at all. The two sections no competitor has are
// "Translated into" and translator credits — translators are Author rows here,
// so they get real pages, and they are a small well-connected community who link
// to things that credit them.

import * as ld from '../jsonld.js';
import { appBand, avatar, bookStrip, breadcrumb, section } from '../components.js';
import { authorPath, clamp, html, joinDot, num, publisherPath, seg } from '../html.js';
import { page } from '../layout.js';

function decadeChart(decades) {
  const entries = Object.entries(decades || {});
  if (entries.length < 2) return '';
  const max = Math.max(...entries.map(([, n]) => n));
  return html`<div class="timeline">
    ${entries.map(
      ([label, n]) => html`<div class="tl">
        <div class="b" style="height:${Math.max(6, Math.round((n / max) * 62))}px"></div>
        <div class="y">${label}<br />${n}</div>
      </div>`,
    )}
  </div>`;
}

function statsPanel(rows) {
  const shown = rows.filter(([, v]) => v != null && v !== '' && v !== 0);
  if (!shown.length) return '';
  return html`<div class="hubstats">
    ${shown.map(
      ([k, v]) => html`<div class="st"><span class="k">${k}</span><b>${v}</b></div>`,
    )}
  </div>`;
}

export function renderAuthor(data) {
  const canonical = authorPath(data);
  const displayName = data.pen_name || data.name;
  const crumbs = [
    { label: 'Home', href: '/' },
    { label: 'Authors', href: '/authors' },
    { label: displayName },
  ];

  const description =
    clamp(data.bio, 155) ||
    joinDot([
      displayName,
      data.primary_language ? `${data.primary_language} author` : null,
      data.work_count ? `${data.work_count} books in the Kitabi catalogue` : null,
    ]);

  const body = html`
    <div class="wrap">
      ${breadcrumb(crumbs)}
      <div class="ahero">
        <div class="portrait">
          ${data.image_url
            ? html`<img src="${data.image_url}" alt="${displayName}" width="168" height="168" fetchpriority="high" />`
            : html`${displayName.trim().charAt(0)}`}
        </div>

        <div>
          <h1>${displayName}</h1>
          ${data.pen_name && data.pen_name !== data.name
            ? html`<p class="native">${data.name}</p>`
            : ''}
          <p class="chips" style="margin-top:11px">
            ${data.primary_language
              ? html`<a class="chip" href="/language/${seg(String(data.primary_language).toLowerCase())}"
                  >${data.primary_language}</a
                >`
              : ''}
            ${data.work_count ? html`<span class="chip">${data.work_count} works</span>` : ''}
            ${data.on_kitabi ? html`<span class="badge-kit">🔗 on Kitabi</span>` : ''}
          </p>
          ${data.bio ? html`<p class="intro">${data.bio}</p>` : ''}
          ${decadeChart(data.decades)}
        </div>

        <div>
          ${statsPanel([
            ['Works', data.work_count],
            ['Editions', data.edition_count],
            ['Languages', data.languages?.length],
            ['Translated', data.translated_works?.length],
            ['Average rating', data.rating ? `★ ${data.rating.toFixed(1)}` : null],
          ])}
          ${data.publishers?.length
            ? html`<div class="rail" style="margin-top:13px">
                <h2 class="rh">Published by</h2>
                <div class="rb chips">
                  ${data.publishers.map(
                    (p) => html`<a class="chip" href="${publisherPath(p)}">${p.name}</a>`,
                  )}
                </div>
              </div>`
            : ''}
        </div>
      </div>

      ${data.works?.length ? section('Works', bookStrip(data.works, { priorityFirst: !data.image_url })) : ''}
      ${data.translated_works?.length
        ? section('Translated works', bookStrip(data.translated_works))
        : ''}
      ${appBand()}
    </div>
  `;

  return page({
    title: `${displayName} — books and translations — Kitabi`,
    description,
    canonical,
    image: data.image_url || null,
    ogType: 'profile',
    body,
    indexable: data.indexable !== false,
    nav: 'authors',
    jsonLd: [
      ld.person(data),
      ld.breadcrumbList(crumbs),
      ...(data.works?.length ? [ld.itemList(data.works, `Books by ${displayName}`)] : []),
    ],
  });
}

export function renderPublisher(data) {
  const canonical = publisherPath(data);
  const crumbs = [
    { label: 'Home', href: '/' },
    { label: 'Publishers', href: '/publishers' },
    { label: data.name },
  ];

  const description = joinDot([
    data.name,
    data.primary_language ? `${data.primary_language} publisher` : null,
    data.edition_count ? `${num(data.edition_count)} editions in the Kitabi catalogue` : null,
  ]);

  const body = html`
    <div class="wrap">
      ${breadcrumb(crumbs)}
      <div class="ahero">
        <div class="portrait">
          ${data.logo_url
            ? html`<img src="${data.logo_url}" alt="${data.name}" width="168" height="168" fetchpriority="high" />`
            : html`${data.name.trim().charAt(0)}`}
        </div>
        <div>
          <h1>${data.name}</h1>
          <p class="chips" style="margin-top:11px">
            ${data.primary_language
              ? html`<a class="chip" href="/language/${seg(String(data.primary_language).toLowerCase())}"
                  >${data.primary_language}</a
                >`
              : ''}
            ${data.earliest_year ? html`<span class="chip">since ${data.earliest_year}</span>` : ''}
          </p>
          <p class="intro">
            ${joinDot([
              `${num(data.edition_count)} editions`,
              `${num(data.total)} works`,
              data.authors?.length ? `${num(data.authors.length)} authors` : null,
            ])}
            in this catalogue.
          </p>
          ${decadeChart(data.decades)}
        </div>
        <div>
          ${statsPanel([
            ['Editions', data.edition_count],
            ['Works', data.total],
            ['Authors', data.authors?.length],
            ['Languages', data.languages?.length],
            ['Earliest', data.earliest_year],
          ])}
        </div>
      </div>

      ${data.works?.length ? section('From this house', bookStrip(data.works)) : ''}
      ${data.authors?.length
        ? section(
            'Authors published',
            html`<p class="chips">
              ${data.authors.map((a) => html`<a class="chip" href="${authorPath(a)}">${a.name}</a>`)}
            </p>`,
          )
        : ''}
      ${appBand()}
    </div>
  `;

  return page({
    title: `${data.name} — catalogue — Kitabi`,
    description,
    canonical,
    image: data.logo_url || null,
    body,
    indexable: data.indexable !== false,
    nav: 'publishers',
    jsonLd: [
      ld.publisherOrg(data),
      ld.breadcrumbList(crumbs),
      ...(data.works?.length ? [ld.itemList(data.works, `Books published by ${data.name}`)] : []),
    ],
  });
}
