// The renderers loaded as REAL ES modules — the way Cloudflare loads them.
//
// run.py's main harness strips every `import` and concatenates the files into
// one program, so a name one module uses but forgot to import is simply in
// scope there, and every assertion passes. In production the same file is its
// own module and the name is undefined: a ReferenceError on every request. The
// buy-click hooks were written exactly that way on 5 Oct 2026 — `h` used in
// pages/book.js, never imported — and 434 assertions were green.
//
// So: import every module (a missing export fails at link time), then render
// one page of each kind through its real entry point (a missing import fails
// when the line runs). No assertions about the HTML beyond "it rendered and
// has its landmark" — cases.js owns the content. Run by run.py when node is
// present; nothing is installed.
import { readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { pathToFileURL } from 'node:url';

const ROOT = new URL('../functions/', import.meta.url).pathname;
const failures = [];
let checks = 0;

function walk(dir) {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    return statSync(path).isDirectory() ? walk(path) : path.endsWith('.js') ? [path] : [];
  });
}

const loaded = {};
for (const file of walk(ROOT)) {
  const name = relative(ROOT, file);
  try {
    loaded[name] = await import(pathToFileURL(file).href);
    checks++;
  } catch (err) {
    failures.push(`${name} does not load as a module: ${err.message}`);
  }
}

const CARD = { id: 'w', slug: 'chemmeen', title: 'Chemmeen', authors: [{ name: 'Thakazhi' }] };
const EDITION = {
  id: '11111111-2222-3333-4444-555555555555',
  isbn: '9788126412808',
  buy_links: [{ retailer: 'Amazon', url: 'https://www.amazon.in/dp/8126412801', affiliate: true }],
};

async function renders(label, landmark, make) {
  try {
    const response = await make();
    const body = await response.text();
    if (response.status !== 200) failures.push(`${label}: status ${response.status}`);
    else if (!body.includes(landmark)) failures.push(`${label}: rendered without "${landmark}"`);
    else checks++;
  } catch (err) {
    failures.push(`${label} threw: ${err.message}`);
  }
}

const book = loaded['_lib/pages/book.js'];
const discover = loaded['_lib/pages/discover.js'];
const more = loaded['_lib/pages/more.js'];
const people = loaded['_lib/pages/people.js'];
const home = loaded['_lib/pages/home.js'];

if (book && discover && more && people && home) {
  await renders('book page with a buy link', 'data-buy="Amazon"', () =>
    // BookPage as api/app/schemas/public.py sends it: the work's fields at the
    // top level, its editions beside them.
    book.renderBook({
      id: 'w', slug: 'chemmeen', title: 'Chemmeen', description: 'A novel of the Kerala coast.',
      language: 'Malayalam', form: 'Novel', first_publish_year: 1956,
      authors: [{ id: 'a', slug: 'thakazhi', name: 'Thakazhi' }], translators: [], genres: [],
      editions: [EDITION], translations: [], original: null,
      rating: { average: 4.5, count: 2, distribution: { 5: 1, 4: 1 } },
      reviews: [], more_by_author: [], related: [], indexable: true,
    }),
  );
  await renders('language hub', 'data-pager', () =>
    discover.renderHub({
      kind: 'language', name: 'Malayalam', slug: 'malayalam', form: null, works: [CARD],
      start_here: [], total: 183, page: 1, per_page: 24, sort: 'title',
      languages: [], forms: [], genres: [],
    }),
  );
  await renders('browse', 'data-list', () =>
    discover.renderBrowse(
      { works: [CARD], total: 1600, page: 2, per_page: 24, languages: [], forms: [], genres: [] },
      { query: {} },
    ),
  );
  await renders('authors directory', 'class="people"', () =>
    discover.renderPeople({
      kind: 'authors', sort: 'books', language: null, page: 1, per_page: 48, total: 1,
      people: [{ id: 'a', slug: 'basheer', name: 'Basheer', work_count: 12 }], languages: [],
    }),
  );
  await renders('reviews', 'Chemmeen', () =>
    more.renderReviews({
      work: CARD, rating: { average: 4, count: 1, distribution: { 4: 1 } },
      reviews: [{ id: 'r', body: 'Good.', rating: 4, reviewer: { display_name: 'A' } }],
      total: 1, page: 1, per_page: 20,
    }),
  );
}

console.log(JSON.stringify({ checks, failures }));
