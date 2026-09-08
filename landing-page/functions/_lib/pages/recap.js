// The page behind a shared reading card — /reader/:username/recap/:key
//
// A card is a picture; this is where "what did they actually read?" is
// answered (owner request, 8 Sep 2026). The card carries the link, the link
// carries the reader's handle and the window, and the API decides whether the
// page exists at all — a reader who hasn't published recaps 404s exactly like
// a handle that was never registered.
//
// `noindex` and robots-disallowed, deliberately: `<key>` is an infinite family
// of URLs, and a crawler walking a combinatorial space is what turned a 3 MB
// catalogue into 5.75 GB of metered egress in a billing cycle (7 Sep 2026).
// noindex stops indexing, not fetching — the Disallow is the half that matters.

import { appBand, bookStrip, breadcrumb, section } from '../components.js';
import { clamp, html, num, plural, raw, seg } from '../html.js';
import { page } from '../layout.js';

const MONTHS = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const DOW = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

/** A `YYYY-MM-DD` string as a UTC date — never `new Date(str)` with a time,
 * which a runtime is free to read in the local zone and shift by a day. */
function day(iso) {
  const [y, m, d] = String(iso).split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d));
}

const iso = (dt) =>
  `${dt.getUTCFullYear()}-${String(dt.getUTCMonth() + 1).padStart(2, '0')}-${String(
    dt.getUTCDate(),
  ).padStart(2, '0')}`;

/** "1–30 September 2026", "8 September 2026", "Everything so far". */
function windowTitle(data) {
  const a = day(data.start);
  const b = day(data.end);
  if (data.kind === 'all') return 'Everything so far';
  if (data.kind === 'year') return String(a.getUTCFullYear());
  if (data.kind === 'month') return `${MONTHS[a.getUTCMonth()]} ${a.getUTCFullYear()}`;
  if (data.kind === 'day') {
    return `${a.getUTCDate()} ${MONTHS[a.getUTCMonth()]} ${a.getUTCFullYear()}`;
  }
  const sameMonth = a.getUTCMonth() === b.getUTCMonth() && a.getUTCFullYear() === b.getUTCFullYear();
  const left = sameMonth
    ? `${a.getUTCDate()}`
    : `${a.getUTCDate()} ${MONTHS[a.getUTCMonth()]}`;
  return `${left}–${b.getUTCDate()} ${MONTHS[b.getUTCMonth()]} ${b.getUTCFullYear()}`;
}

/** "4h 12m", "38m" — the app's own `formatDuration` shape, so a page and the
 * card that linked to it never quote the same reading two different ways. */
function duration(seconds) {
  const total = Math.max(0, Math.round(seconds / 60));
  const hours = Math.floor(total / 60);
  const mins = total % 60;
  if (hours && mins) return `${hours}h ${mins}m`;
  if (hours) return `${hours}h`;
  return `${mins}m`;
}

function stat(value, label) {
  return html`<div class="rcs">
    <b class="serif">${value}</b>
    <span class="eyebrow">${label}</span>
  </div>`;
}

/** The window's shape. A month gets its calendar, anything shorter or longer
 * gets a strip of the same cells — one list of days read three ways rather
 * than three payloads. Days with no reading are drawn, not skipped: the shape
 * is the point, and a grid with holes in it says more than a row of blocks. */
function shape(data) {
  const days = [];
  const start = day(data.start);
  const end = day(data.end);
  for (let d = new Date(start); d <= end; d.setUTCDate(d.getUTCDate() + 1)) {
    days.push(iso(d));
  }
  // A year or "everything" is too many cells to read as a grid — the numbers
  // and the books carry those windows on their own.
  if (days.length > 62 || days.length < 2) return '';

  const seconds = data.seconds_by_day || {};
  const peak = Math.max(1, ...Object.values(seconds));
  const cell = (key) => {
    const s = seconds[key] || 0;
    const cls = s === 0 ? 'rcd' : s >= peak * 0.75 ? 'rcd on hv' : 'rcd on';
    const title = s === 0 ? key : `${key} · ${duration(s)}`;
    return html`<span class="${cls}" title="${title}"></span>`;
  };

  if (data.kind === 'month') {
    // Sunday-first, the same grid the app's card draws, padded so every row is
    // a real week.
    const lead = start.getUTCDay();
    return html`<div class="rcal" aria-hidden="true">
      ${DOW.map((d) => html`<span class="rcw">${d}</span>`)}
      ${Array.from({ length: lead }, () => html`<span class="rcd pad"></span>`)}
      ${days.map((key) => cell(key))}
    </div>`;
  }
  return html`<div class="rcrow" aria-hidden="true">${days.map((key) => cell(key))}</div>`;
}

export function renderRecap(data) {
  const canonical = `/reader/${seg(data.username)}/recap/${seg(data.key)}`;
  const title = windowTitle(data);
  const books = data.books || [];
  const crumbs = [
    { label: 'Home', href: '/' },
    { label: data.display_name, href: `/reader/${seg(data.username)}` },
    { label: title },
  ];

  const body = html`
    <div class="wrap">
      ${breadcrumb(crumbs)}
      <div class="rchd">
        <a class="rcwho" href="/reader/${seg(data.username)}">
          <span class="portrait" style="width:46px;height:46px;max-width:46px;border-radius:50%;font-size:19px">
            ${data.avatar_url
              ? html`<img src="${data.avatar_url}" alt="" width="46" height="46" />`
              : html`${(data.display_name || '?').trim().charAt(0)}`}
          </span>
          <span>
            <b>${data.display_name}</b>
            ${data.username ? html`<span class="rcat">@${data.username}</span>` : ''}
          </span>
        </a>
        <h1 class="serif">${title}</h1>
      </div>

      <div class="rcstats">
        ${books.length ? stat(num(books.length), books.length === 1 ? 'book finished' : 'books finished') : ''}
        ${data.pages_read ? stat(num(data.pages_read), data.pages_read === 1 ? 'page' : 'pages') : ''}
        ${data.total_seconds ? stat(duration(data.total_seconds), 'read') : ''}
        ${data.days_read ? stat(num(data.days_read), data.days_read === 1 ? 'day with a book' : 'days with a book') : ''}
      </div>

      ${shape(data)}

      ${books.length
        ? section('Finished in this window', bookStrip(books, { priorityFirst: true }))
        : html`<section class="sec">
            <div class="thin">
              <p>No books were finished in this window.</p>
            </div>
          </section>`}
      ${appBand()}
    </div>
  `;

  const summary = [
    books.length ? `${plural(books.length, 'book')} finished` : null,
    data.pages_read ? `${num(data.pages_read)} pages` : null,
    data.total_seconds ? duration(data.total_seconds) : null,
  ].filter(Boolean);

  return page({
    title: `${data.display_name} — ${title} — Kitabi`,
    description: clamp(
      summary.length
        ? `${data.display_name}'s reading, ${title.toLowerCase()}: ${summary.join(', ')}.`
        : `${data.display_name}'s reading, ${title.toLowerCase()}.`,
      160,
    ),
    canonical,
    body,
    // Never indexable, whatever it holds. This is a page one person shared with
    // the people they chose, and the key space behind it is infinite — see the
    // note at the top of this file.
    indexable: false,
    // Page-scoped rather than appended to the site stylesheet: that sheet is
    // inlined into *every* page, and this is the rarest page on the site. The
    // budget allows zero render-blocking requests, not zero thought about what
    // rides in each document.
    extraHead: raw(`<style>${RECAP_CSS}</style>`),
  });
}

/** The recap page's own styles, inlined into this page alone.
 *
 * Every class here is prefixed `rc`. The stylesheet is inlined into every page,
 * so every selector on this site is global, and a short name is a land grab —
 * `.lb` for a lightbox once collided with the ratings histogram's row label and
 * would have hidden "5 ★" on every book page (1 Sep 2026).
 */
export const RECAP_CSS = `
.rchd{margin-top:22px}
.rcwho{display:inline-flex;align-items:center;gap:10px;color:inherit}
.rcwho b{font-size:14px;display:block}
.rcat{font-size:12px;color:var(--ink-soft)}
.rchd h1{font-size:31px;font-weight:600;margin-top:13px}
.rcstats{display:flex;flex-wrap:wrap;gap:26px;margin-top:16px}
.rcs b{font-size:23px;font-weight:600;display:block;color:var(--oxblood)}
.rcal{display:grid;grid-template-columns:repeat(7,minmax(0,1fr));gap:5px;
  max-width:322px;margin-top:24px}
.rcw{font-size:9px;font-weight:700;letter-spacing:.1em;color:var(--ink-soft);text-align:center}
.rcrow{display:flex;flex-wrap:wrap;gap:5px;margin-top:24px;max-width:640px}
.rcrow .rcd{width:34px}
.rcd{aspect-ratio:1;border-radius:4px;background:var(--line)}
.rcd.pad{background:none}
.rcd.on{background:var(--gold)}
.rcd.on.hv{background:var(--oxblood)}
@media (max-width:520px){
  .rchd h1{font-size:25px}
  .rcstats{gap:18px}
  .rcrow .rcd{width:26px}
}
`;
