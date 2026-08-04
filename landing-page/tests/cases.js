// Tests for the edge renderer. Run with ./landing-page/tests/run.py
//
// Weighted towards the things that fail silently in production: escaping (there
// is no framework doing it for us), the robots tag (a wrong one either hides the
// site or floods the index with thin pages), and AggregateRating (fabricated
// review markup earns a manual action).

// --------------------------------------------------------------------------
// Escaping
// --------------------------------------------------------------------------

var XSS = '<script>alert(1)</script>';

assert(h(XSS) === '&lt;script&gt;alert(1)&lt;/script&gt;', 'h() escapes tags');
assert(h(null) === '' && h(undefined) === '', 'h() renders null/undefined as empty, not "null"');
assert(h('a & b') === 'a &amp; b', 'h() escapes ampersands');
assert(h('"quoted"') === '&quot;quoted&quot;', 'h() escapes double quotes');
assert(h("it's") === 'it&#39;s', 'h() escapes single quotes');

var interpolated = String(html`<p>${XSS}</p>`);
assertExcludes(interpolated, '<script>', 'html`` escapes interpolations');
assertIncludes(interpolated, '&lt;script&gt;', 'html`` keeps the escaped text');

assert(String(html`<p>${raw('<b>ok</b>')}</p>`) === '<p><b>ok</b></p>', 'raw() opts out of escaping');
assert(String(html`${['a', 'b']}`) === 'ab', 'html`` flattens arrays with no separator');
assert(
  String(html`${[html`<i>x</i>`]}`) === '<i>x</i>',
  'html`` keeps nested raw fragments unescaped',
);

// --------------------------------------------------------------------------
// Paths — a slug when there is one, the id when there is not
// --------------------------------------------------------------------------

assert(bookPath({ slug: 'chemmeen', id: 'uuid-1' }) === '/book/chemmeen', 'slug wins');
assert(bookPath({ slug: null, id: 'uuid-1' }) === '/book/uuid-1', 'id is the fallback');
assert(bookPath(null) === '/', 'a missing entity degrades to home, never "/book/undefined"');
assert(
  authorPath({ slug: 'a b/c' }) === '/author/a%20b%2Fc',
  'path segments are encoded — a stray slash must not invent a route',
);

// --------------------------------------------------------------------------
// clamp / num
// --------------------------------------------------------------------------

assert(clamp('  lots   of\n space ', 50) === 'lots of space', 'clamp collapses whitespace');
assert(clamp('abcdefghij', 5).length === 5, 'clamp respects the limit');
assert(clamp('abcdefghij', 5).slice(-1) === '…', 'clamp ends with an ellipsis');
assert(num(1402) === '1,402', 'num groups thousands');
assert(num(999) === '999', 'num leaves small numbers alone');

// --------------------------------------------------------------------------
// Covers — the LCP rule and CLS prevention
// --------------------------------------------------------------------------

var withCover = { title: 'Chemmeen', cover_url: 'https://x/c.jpg', authors: [{ name: 'Thakazhi' }] };
var priority = String(cover(withCover, { priority: true }));
assertIncludes(priority, 'fetchpriority="high"', 'the LCP cover is high priority');
assertExcludes(priority, 'loading="lazy"', 'the LCP cover is never lazy — that delays the paint');

var lazy = String(cover(withCover));
assertIncludes(lazy, 'loading="lazy"', 'every other cover is lazy');
assertIncludes(lazy, 'width=', 'covers carry explicit width');
assertIncludes(lazy, 'height=', 'covers carry explicit height — this is what keeps CLS at ~0');

var typeset = String(cover({ title: 'ചെമ്മീൻ', authors: [{ name: 'Thakazhi' }] }));
assertIncludes(typeset, 'ചെമ്മീൻ', 'no cover image → a typeset cover, not a broken image');
assertExcludes(typeset, '<img', 'the typeset cover has no img element to fail');
assertIncludes(typeset, 'role="img"', 'the typeset cover is still announced as an image');

// The palette pick must be stable, or a book flickers between pages.
assert(
  String(cover({ title: 'Kayar' })) === String(cover({ title: 'Kayar' })),
  'generated covers are deterministic for a title',
);

// --------------------------------------------------------------------------
// Stars — absent is not zero
// --------------------------------------------------------------------------

assert(String(stars(null, 0)) === '', 'no rating renders nothing at all');
assert(String(stars(0, 0)) === '', 'a zero rating renders nothing — it is not a rating');
var rated = String(stars(4.4, 312));
assertIncludes(rated, '4.4', 'the rating value is shown');
assertIncludes(rated, '312 ratings', 'the count is shown');
assertIncludes(rated, 'Rated 4.4 out of 5', 'there is a screen-reader label');

// --------------------------------------------------------------------------
// Pager — crawlable, and never canonicalising page 2 to page 1
// --------------------------------------------------------------------------

var href = function (n) {
  return '/browse?page=' + n;
};
assert(String(pager(1, 10, 24, href)) === '', 'one page needs no pager');
var mid = String(pager(5, 240, 24, href));
assertIncludes(mid, 'rel="prev"', 'a middle page links back');
assertIncludes(mid, 'rel="next"', 'a middle page links forward');
assertIncludes(mid, '/browse?page=1', 'the first page is always reachable');
assertIncludes(mid, '/browse?page=10', 'the last page is always reachable');
assertIncludes(mid, 'aria-current="page"', 'the current page is marked');
assertExcludes(String(pager(1, 240, 24, href)), 'rel="prev"', 'page 1 has no previous');

// --------------------------------------------------------------------------
// The document shell
// --------------------------------------------------------------------------

var doc = String(
  page({
    title: 'Chemmeen — Kitabi',
    description: 'A novel by Thakazhi.',
    canonical: '/book/chemmeen',
    body: html`<p>Body copy</p>`,
  }).text(),
);

assertIncludes(doc, '<!doctype html>', 'it is a real document');
assertIncludes(doc, '<title>Chemmeen — Kitabi</title>', 'the title is set');
assertIncludes(doc, 'rel="canonical" href="https://kitabi.in/book/chemmeen"', 'canonical is absolute');
assertIncludes(doc, 'content="index, follow"', 'a good page is indexable by default');
assertIncludes(doc, '<p>Body copy</p>', 'the body is present in the HTML');
assertIncludes(doc, '<main id="main">', 'there is a main landmark');
assertIncludes(doc, 'Skip to content', 'there is a skip link');
assertIncludes(doc, '<style>', 'CSS is inlined — zero render-blocking requests');
assertExcludes(doc, '<link rel="stylesheet"', 'no external stylesheet');
assertExcludes(doc, 'fonts.googleapis.com', 'no third-party font origin');
assertExcludes(doc, '<script src', 'no blocking script — content never depends on JS');

// The whole point of the rewrite: content is in the HTML, not fetched later.
assertExcludes(doc, 'Opening the book', 'the spinner shell is gone');

var noindexed = String(page({ title: 'Thin', body: html`x`, indexable: false }).text());
assertIncludes(noindexed, 'content="noindex, follow"', 'a thin page is noindex but still followed');

// A title with markup in it must not escape into the head.
var evil = String(page({ title: XSS, description: XSS, body: html`x` }).text());
assertExcludes(evil, '<script>alert(1)</script>', 'the title is escaped in <title> and og:title');

// --------------------------------------------------------------------------
// 404 and 503 — a blip must never read as "gone"
// --------------------------------------------------------------------------

var missing = notFound({ what: 'book' });
assert(missing.status === 404, 'a missing page is a real 404, not a soft 200');
assertIncludes(String(missing.text()), 'noindex', 'a 404 is noindex so it leaves the index');

var down = unavailable();
assert(down.status === 503, 'an API outage is a 503, never a 404');
assert(down.headers.get('Retry-After') === '30', 'the 503 tells crawlers when to come back');

// --------------------------------------------------------------------------
// JSON-LD
// --------------------------------------------------------------------------

var bookLd = book({
  title: 'Chemmeen',
  slug: 'chemmeen',
  language: 'Malayalam',
  first_publish_year: 1956,
  description: 'On the Kerala coast…',
  authors: [{ name: 'Thakazhi', slug: 'thakazhi' }],
  genres: [{ name: 'Literary fiction' }],
  editions: [
    { isbn: '9788126403455', page_count: 218, format: 'paperback', year: 2019,
      publisher: { name: 'DC Books' }, cover_url: 'https://x/c.jpg' },
  ],
  rating: { average: 4.4, count: 312 },
  reviews: [{ rating: 5, text: 'Wonderful.', reviewer: { display_name: 'A reader' } }],
});

assert(bookLd['@type'] === 'Book', 'the book emits Book');
assert(bookLd.author[0].url === 'https://kitabi.in/author/thakazhi', 'authors link absolutely');
assert(bookLd.aggregateRating.ratingValue === 4.4, 'a real rating is published');
assert(bookLd.workExample[0].isbn === '9788126403455', 'each edition becomes a workExample');
assert(
  bookLd.workExample[0].bookFormat === 'https://schema.org/Paperback',
  'the format maps to a schema.org URL',
);
assert(bookLd.review.length === 1, 'public reviews are published as Review');

// THE ONE THAT MATTERS: no rating means the property is absent, not zero.
var unrated = book({
  title: 'Untitled',
  authors: [],
  editions: [],
  rating: { average: null, count: 0 },
});
assert(
  unrated.aggregateRating === undefined,
  'NO aggregateRating when there is no rating — fabricated review markup earns a manual action',
);
assertExcludes(JSON.stringify(unrated), 'aggregateRating', 'the key is absent entirely');

var site = website();
assert(site.potentialAction['@type'] === 'SearchAction', 'home declares a SearchAction');

var crumbs = breadcrumbList([
  { label: 'Home', href: '/' },
  { label: 'Malayalam', href: '/language/malayalam' },
  { label: 'Chemmeen' },
]);
assert(crumbs.itemListElement.length === 3, 'the breadcrumb has every level');
assert(crumbs.itemListElement[2].item === undefined, 'the current page has no item URL');

// JSON-LD must not be able to close its own script tag.
var withTag = String(page({ title: 't', body: html`x`, jsonLd: { name: '</script><script>x' } }).text());
assertExcludes(withTag, '</script><script>x', 'a "</script>" inside JSON-LD is escaped');
assertIncludes(withTag, '\\u003c/script', 'it is escaped as a unicode escape');

// --------------------------------------------------------------------------
// Components compose without leaking
// --------------------------------------------------------------------------

var strip = String(
  bookStrip([
    { title: 'A', slug: 'a', authors: [{ name: 'X' }], rating: 4.4, rating_count: 10,
      cover_url: 'https://x/a.jpg' },
    { title: XSS, slug: 'b', authors: [] },
  ], { priorityFirst: true }),
);
assertIncludes(strip, 'href="/book/a"', 'cards link to the book page');
assertExcludes(strip, '<script>alert', 'a hostile title in a card is escaped');
assertIncludes(strip, 'fetchpriority="high"', 'the first card in a hero strip is the LCP image');
// A typeset cover has no image to prioritise, and must not pretend otherwise.
var typesetStrip = String(bookStrip([{ title: 'No cover', slug: 'n' }], { priorityFirst: true }));
assertExcludes(typesetStrip, 'fetchpriority', 'a generated cover carries no image priority hint');

var bc = String(breadcrumb([{ label: 'Home', href: '/' }, { label: 'Chemmeen' }]));
assertIncludes(bc, 'aria-label="Breadcrumb"', 'the breadcrumb is a labelled nav');
assertIncludes(bc, '<span>Chemmeen</span>', 'the last crumb is not a link');

// --------------------------------------------------------------------------
// The book page — the flagship (mockup W3)
// --------------------------------------------------------------------------

var BOOK = {
  id: 'uuid-b', slug: 'chemmeen', title: 'Chemmeen', subtitle: 'ചെമ്മീൻ',
  description: 'On the Kerala coast, Karuthamma loves Pareekutti across a line her community will not let her cross.',
  language: 'Malayalam', form: 'Novel', first_publish_year: 1956,
  authors: [{ id: 'a1', name: 'Thakazhi Sivasankara Pillai', slug: 'thakazhi-sivasankara-pillai' }],
  translators: [{ id: 'a2', name: 'Narayana Menon', slug: 'narayana-menon' }],
  genres: [{ id: 'g1', name: 'Literary fiction', slug: 'literary-fiction' }],
  editions: [{ id: 'e1', isbn: '9788126403455', page_count: 218, format: 'paperback', year: 2019,
               cover_url: 'https://x/c.jpg', publisher: { id: 'p1', name: 'DC Books', slug: 'dc-books' },
               buy_links: [{ retailer: 'Amazon.in', url: 'https://amazon.in/x' }] }],
  translations: [{ id: 'uuid-t', slug: 'chemmeen-english', title: 'Chemmeen', language: 'English',
                   year: 1962, rating: 4.2, rating_count: 88, authors: [] }],
  original: null,
  rating: { average: 4.4, count: 312, distribution: { '5': 193, '4': 81, '3': 25, '2': 9, '1': 4 } },
  reviews: [{ rating: 5, text: 'I read it first at fifteen.', created_at: '2026-07-14T00:00:00Z',
              reviewer: { display_name: 'Arundhati M.' } }],
  more_by_author: [{ id: 'uuid-k', slug: 'kayar', title: 'Kayar', authors: [], rating: 4.3 }],
  related: [{ id: 'uuid-r', slug: 'naalukettu', title: 'Naalukettu', authors: [] }],
  indexable: true,
};

var bookDoc = String(renderBook(BOOK).text());

// The whole reason for the rewrite: real content in the HTML, no JS required.
assertIncludes(bookDoc, 'Chemmeen', 'the title is in the served HTML');
assertIncludes(bookDoc, 'Karuthamma loves Pareekutti', 'the blurb is in the served HTML');
assertIncludes(bookDoc, 'Thakazhi Sivasankara Pillai', 'the author is in the served HTML');
assertIncludes(bookDoc, '4.4', 'the rating is in the served HTML');
assertIncludes(bookDoc, '218', 'the page count is in the served HTML');
assertIncludes(bookDoc, '9788126403455', 'the ISBN is in the served HTML');

// Onward links — a book page is the densest crawl node on the site.
assertIncludes(bookDoc, 'href="/author/thakazhi-sivasankara-pillai"', 'links to the author');
assertIncludes(bookDoc, 'href="/publisher/dc-books"', 'links to the publisher');
assertIncludes(bookDoc, 'href="/language/malayalam"', 'links to the language hub');
assertIncludes(bookDoc, 'href="/genre/literary-fiction"', 'links to the genre hub');
assertIncludes(bookDoc, 'href="/book/kayar"', 'links to more by the author');
assertIncludes(bookDoc, 'href="/book/chemmeen-english"', 'links to the translation');

// The signature module, and its position: above editions and above reviews.
assertIncludes(bookDoc, 'Read it in another language', 'the translation module is rendered');
// Compare against the editions TABLE, not the word "editions" — that also
// appears in the hero's facts line, well above both.
assert(
  bookDoc.indexOf('Read it in another language') < bookDoc.indexOf('class="eds"'),
  'the translation module sits above the editions table — it is the differentiator',
);
assert(
  bookDoc.indexOf('Read it in another language') < bookDoc.indexOf('What readers said'),
  '…and above the reviews',
);

assertIncludes(bookDoc, 'Amazon.in', 'buy links render when present');
assertIncludes(bookDoc, 'rel="nofollow noopener"', 'outbound retailer links are nofollow');
assertIncludes(bookDoc, 'What readers said', 'reviews are on the page');
assertIncludes(bookDoc, 'I read it first at fifteen', 'the review text is in the HTML');
assertIncludes(bookDoc, 'fetchpriority="high"', 'the hero cover is the LCP element');
assertIncludes(bookDoc, '"@type":"Book"', 'Book JSON-LD is emitted');
assertIncludes(bookDoc, '"aggregateRating"', 'a real rating is published as structured data');
assertIncludes(bookDoc, 'og:type" content="book"', 'og:type is book');
assertIncludes(bookDoc, 'content="index, follow"', 'a complete book page is indexable');

// A thin book: same renderer, different robots tag, and no invented rating.
var thinDoc = String(
  renderBook({ id: 'u', slug: 'stub', title: 'Stub', authors: [], genres: [], editions: [],
               translations: [], rating: { average: null, count: 0 }, reviews: [],
               more_by_author: [], related: [], indexable: false }).text(),
);
assertIncludes(thinDoc, 'content="noindex, follow"', 'a thin book page is noindex, still followed');
assertExcludes(thinDoc, 'aggregateRating', 'no rating means no rating markup');
assertExcludes(thinDoc, 'What readers said', 'no reviews section when there are none');

// --------------------------------------------------------------------------
// Author and publisher pages
// --------------------------------------------------------------------------

var authorDoc = String(
  renderAuthor({
    id: 'a1', slug: 'thakazhi', name: 'Thakazhi Sivasankara Pillai',
    bio: 'Thakazhi wrote the Kerala coast into Malayalam literature.',
    primary_language: 'Malayalam', on_kitabi: true,
    works: [{ id: 'w', slug: 'chemmeen', title: 'Chemmeen', authors: [], rating: 4.4 }],
    translated_works: [], publishers: [{ id: 'p1', name: 'DC Books', slug: 'dc-books' }],
    languages: ['Malayalam'], work_count: 34, edition_count: 96, rating: 4.3,
    decades: { '1950s': 4, '1960s': 6 }, indexable: true,
  }).text(),
);
assertIncludes(authorDoc, 'Thakazhi wrote the Kerala coast', 'the bio is in the HTML');
assertIncludes(authorDoc, 'href="/book/chemmeen"', 'the author page links to their books');
assertIncludes(authorDoc, 'on Kitabi', 'a verified author is badged');
assertIncludes(authorDoc, '"@type":"Person"', 'Person JSON-LD is emitted');
assertIncludes(authorDoc, '"@type":"ItemList"', 'the bibliography is an ItemList');

var pubDoc = String(
  renderPublisher({
    id: 'p1', slug: 'dc-books', name: 'DC Books', primary_language: 'Malayalam',
    works: [{ id: 'w', slug: 'chemmeen', title: 'Chemmeen', authors: [] }], total: 168,
    authors: [{ id: 'a1', name: 'Thakazhi', slug: 'thakazhi' }], languages: ['Malayalam'],
    edition_count: 214, earliest_year: 1974, decades: { '1990s': 41 }, indexable: true,
  }).text(),
);
assertIncludes(pubDoc, 'DC Books', 'the publisher name is in the HTML');
assertIncludes(pubDoc, '214', 'the edition count is shown');
assertIncludes(pubDoc, 'href="/author/thakazhi"', 'the publisher page links to its authors');
assertIncludes(pubDoc, '"@type":"Organization"', 'Organization JSON-LD is emitted');
