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
// ISBN shape checking — the gate in front of /isbn/:isbn
//
// This URL is walkable by anyone with any string, so what it accepts decides
// what reaches the origin. The checksum is deliberately NOT checked here (the
// catalogue holds misprinted ISBNs that are still the only identifier those
// editions have) — that is a rule worth pinning down, not an oversight.
// --------------------------------------------------------------------------

assert(cleanIsbn('9788126403455') === '9788126403455', 'a bare ISBN-13 passes through');
assert(cleanIsbn('8126403454') === '8126403454', 'a bare ISBN-10 passes through');
assert(cleanIsbn('978-81-264-0345-5') === '9788126403455', 'hyphens are stripped');
assert(cleanIsbn('978 81 264 0345 5') === '9788126403455', 'spaces are stripped');
assert(cleanIsbn('043942089x') === '043942089X', 'a lowercase check character is normalised');
assert(cleanIsbn('8126403455') === '8126403455', 'a bad checksum is NOT rejected here');

assert(cleanIsbn('chemmeen') === null, 'a title is not an ISBN');
assert(cleanIsbn('123456789') === null, 'nine digits is not an ISBN');
assert(cleanIsbn('12345678901') === null, 'eleven digits is not an ISBN');
assert(cleanIsbn('978812640345X') === null, 'X is only ever an ISBN-10 check character');
assert(cleanIsbn('') === null && cleanIsbn(null) === null, 'empty input is not an ISBN');
assert(cleanIsbn(9788126403455) === null, 'a non-string is not an ISBN');
assert(
  cleanIsbn('../../etc/passwd') === null,
  'a traversal attempt is rejected before it can reach the origin',
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
var withCoverHtml = String(cover(withCover));
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

// A cover URL that 404s must not leave a blank box. The typeset cover is always
// rendered and the image layered over it, so a failed load reveals it — no JS.
assertIncludes(withCoverHtml, 'class="ct"', 'a typeset cover is rendered UNDER every image');
assertIncludes(withCoverHtml, 'Chemmeen', 'so a broken image still shows the title');
assertIncludes(withCoverHtml, '<img', '…and the real cover is still there on top');

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
  reviews: [{ rating: 5, body: 'Wonderful.', reviewer: { display_name: 'A reader' } }],
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
assert(bookLd.review[0].reviewBody === 'Wonderful.', 'and carry the review body, not just a star');

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
// The rating rides ON the cover (class="rt"), so a reader scanning a shelf of
// covers sees it without reading captions — and an unrated book wears nothing,
// because an absent rating is not a zero.
assertIncludes(strip, 'class="rt"', 'a rated card wears the rating chip on its cover');
assertIncludes(strip, '★ 4.4', 'the chip shows the rating value');
assertIncludes(strip, 'Rated 4.4 out of 5', 'the chip has a screen-reader label');
var unratedCard = String(bookCard({ title: 'No rating', slug: 'nr', authors: [] }));
assertExcludes(unratedCard, 'class="rt"', 'an unrated card wears no chip');
// A rated typeset cover is role="img", which silences child sr text — the
// rating must ride in the aria-label instead.
var ratedTypeset = String(bookCard({ title: 'Typeset', slug: 't', authors: [], rating: 4.1 }));
assertIncludes(ratedTypeset, 'rated 4.1 out of 5', 'a typeset cover carries the rating in its label');
// A typeset cover has no image to prioritise, and must not pretend otherwise.
var typesetStrip = String(bookStrip([{ title: 'No cover', slug: 'n' }], { priorityFirst: true }));
assertExcludes(typesetStrip, 'fetchpriority', 'a generated cover carries no image priority hint');

// A Malayalam title is a single unbreakable word. Without a break-inside-word
// rule the browser sets it on one line past its 129px column, so card titles
// ran into each other and typeset covers were clipped at their right edge
// (owner report, 1 Sep 2026) — a defect only the Indic half of the catalogue
// could ever show, because a space is a break opportunity.
assert(
  /body\{overflow-wrap:break-word\}/.test(CSS),
  'a spaceless title wraps inside the word instead of running into its neighbour',
);

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
               // Written from the API schema (BuyLinkOut via services/buy_links.py):
               // Amazon-only since 9 Aug 2026 — one entry, affiliate when tagged.
               buy_links: [{ retailer: 'Amazon', affiliate: true,
                             url: 'https://www.amazon.in/dp/8126403454?tag=kitabi0f-21' }] }],
  translations: [{ id: 'uuid-t', slug: 'chemmeen-english', title: 'Chemmeen', language: 'English',
                   year: 1962, rating: 4.2, rating_count: 88, authors: [] }],
  original: null,
  rating: { average: 4.4, count: 312, distribution: { '5': 193, '4': 81, '3': 25, '2': 9, '1': 4 } },
  reviews: [{ rating: 5, body: 'I read it first at fifteen.', created_at: '2026-07-14T00:00:00Z',
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
// From the editions table too, not only the hero rail: it names the publisher
// in every row and linked none of them (owner report, 1 Sep 2026).
assertIncludes(bookDoc, '<a class="et" href="/publisher/dc-books"',
  'every edition row names a publisher and links it');
// The three facts are ONE grid cell. As separate children they flowed into the
// phone layout's two columns on their own and overlapped each other.
assertIncludes(bookDoc, 'class="edf"', 'an edition row\'s facts are one cell');
var edf = bookDoc.slice(bookDoc.indexOf('class="edf"'));
edf = edf.slice(0, edf.indexOf('</div></div>') + 1);
assert((edf.match(/class="col"/g) || []).length === 3, '…holding all three of them');
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

// The Amazon button (owner decision, 9 Aug 2026): one branded button, not a
// retailer list — wordmark + smile are decorative, the CTA is the real text.
assertIncludes(bookDoc, 'class="amzn"', 'the branded Amazon button renders');
assertIncludes(bookDoc, 'Buy on Amazon.in', 'the button says what it does');
assertIncludes(bookDoc, 'https://www.amazon.in/dp/8126403454?tag=kitabi0f-21',
  'the button links to the served URL untouched');
// The affiliate layer (docs/revenue-plan.md §3.1): a link that pays must say
// so to crawlers (rel=sponsored is Google's requirement for paid links) and
// to readers (the disclosure line) — and only when something actually pays.
assertIncludes(bookDoc, 'rel="sponsored nofollow noopener"', 'affiliate links are rel=sponsored');
assertIncludes(bookDoc, 'may earn a commission', 'the affiliate disclosure renders');
var noAffiliate = String(
  renderBook(Object.assign({}, BOOK, {
    editions: [Object.assign({}, BOOK.editions[0],
      { buy_links: [{ retailer: 'Amazon', url: 'https://www.amazon.in/dp/8126403454' }] })],
  })).text(),
);
assertIncludes(noAffiliate, 'rel="nofollow noopener"', 'an unpaid link is still nofollow');
assertExcludes(noAffiliate, 'may earn a commission', 'no disclosure when no link pays');
assertExcludes(noAffiliate, 'rel="sponsored', 'no sponsored rel when no link pays');
// The covers viewer (owner report, 1 Sep 2026): the site had no way to show a
// back cover at all. Field name is `back_cover_url`, from PublicEdition in
// api/app/schemas/public.py — written from the schema, never from the
// renderer, which is how the review-body bug shipped green (9 Aug 2026).
var backDoc = String(
  renderBook(Object.assign({}, BOOK, {
    editions: [Object.assign({}, BOOK.editions[0],
      { back_cover_url: 'https://ref.supabase.co/covers/back.jpg' })],
  })).text(),
);
assertIncludes(backDoc, 'id="cover-back"', 'the back cover is a slide in the viewer');
assertIncludes(backDoc, 'id="cover-front"', '…alongside the front');
assertIncludes(backDoc, 'class="cvz" href="#cover-front"', 'the hero cover opens the viewer');
assertIncludes(backDoc, 'class="cvb" href="#cover-back"',
  'and the back cover is tucked at its corner, as it is in the app');
// …in front of it. The front cover's own <img> is z-index 2 inside a `.cv` that
// makes no stacking context, so a thumbnail with no z-index is painted under
// the cover it is tucked against (owner report, 1 Sep 2026).
assert(
  /\.cvb\{[^}]*z-index:4/.test(CSS),
  'the tucked thumbnail sits above the front cover, not behind it',
);
assertIncludes(backDoc, 'class="cvt"', 'the two sides sit in one scroll-snap track — swipe is native');
assertIncludes(backDoc, 'class="cvn n" href="#cover-back"', 'and the arrows are plain fragment links');
assertIncludes(backDoc, 'Back cover of Chemmeen', 'the full-size image has a real alt');
// Supabase-hosted covers go through our own proxy, same as the front.
assertIncludes(backDoc, '/img/c?u=', 'the back cover is served through the cover proxy');
// The corner thumbnail and the viewer's slide are the SAME url: one download
// serves both, so the viewer opens on an image the browser already holds. It is
// a full-size photograph either way — /img/c has no resizer — which is why it
// is lazy and de-prioritised behind the hero cover.
assert(
  backDoc.split('back.jpg').length - 1 === 2,
  'the thumbnail and the viewer share one image url',
);
assertIncludes(backDoc, 'fetchpriority="low"', 'the back cover never competes with the LCP');
assert(
  /<img src="[^"]*back\.jpg"[^>]*loading="lazy"/.test(backDoc.replace(/&[a-z]+;/g, '')) ||
    backDoc.indexOf('loading="lazy"') > -1,
  'the viewer\'s images are lazy',
);

// A book whose displayed edition has only a front cover still opens it, but has
// nothing to page through — no chips, no arrows, no empty second slide.
assertIncludes(bookDoc, 'class="cvz" href="#cover-front"', 'a lone front cover is still viewable');
assertExcludes(bookDoc, 'id="cover-back"', 'an edition with no back cover offers no second slide');
assertExcludes(bookDoc, 'class="cvn', '…and no arrows to nowhere');
assertExcludes(bookDoc, 'class="cvb"', '…and no corner thumbnail');

// A typeset cover is drawn from the title. There is nothing to enlarge, and a
// viewer over a generated image would be a promise the page cannot keep.
var typesetDoc = String(
  renderBook(Object.assign({}, BOOK, { editions: [{ id: 'e1', page_count: 218 }] })).text(),
);
assertExcludes(typesetDoc, 'class="cvz"', 'a generated cover is not clickable');
assertExcludes(typesetDoc, 'class="cvv"', '…and carries no viewer');
// The viewer must never claim a class the rest of the site already uses: `lb`
// is the ratings histogram's row label, and a bare `.lb{display:none}` hid
// every one of them.
assertIncludes(bookDoc, 'class="lb">5 ★', 'the histogram labels are untouched');

assertIncludes(bookDoc, 'What readers said', 'reviews are on the page');
// The big average is the score block's DIRECT child. stars() renders its own
// .n inside that block, and a descendant selector drew that at 48px serif as
// well — the average appeared twice, the second copy over the stars.
assert(/\.score>\.n\{/.test(CSS), 'only the score block\'s own number is display-sized');
assertIncludes(bookDoc, 'I read it first at fifteen', 'the review text is in the HTML');
assertIncludes(bookDoc, 'fetchpriority="high"', 'the hero cover is the LCP element');
assertIncludes(bookDoc, '"@type":"Book"', 'Book JSON-LD is emitted');
assertIncludes(bookDoc, '"aggregateRating"', 'a real rating is published as structured data');
assertIncludes(bookDoc, 'og:type" content="book"', 'og:type is book');
assertIncludes(bookDoc, 'content="index, follow"', 'a complete book page is indexable');

// The ISBN in the meta description — the one place an ISBN query has real
// weight. Body text alone is why an ISBN search never found us.
assertIncludes(
  bookDoc,
  'ISBN 9788126403455"',
  'the ISBN is appended to the meta description, not just buried in the body',
);
assert(
  /<meta name="description" content="([^"]*)"/.exec(bookDoc)[1].length <= 155,
  'the description stays within its budget — the blurb is clamped to make room for the ISBN',
);
assertIncludes(
  /<meta name="description" content="([^"]*)"/.exec(bookDoc)[1],
  'Karuthamma',
  '…and the blurb is still there, not crowded out',
);

// A book with no ISBN gets no dangling separator.
var noIsbnDoc = String(
  renderBook(Object.assign({}, BOOK, {
    editions: [{ id: 'e1', page_count: 218, cover_url: 'https://x/c.jpg' }],
  })).text(),
);
var noIsbnDesc = /<meta name="description" content="([^"]*)"/.exec(noIsbnDoc)[1];
assertExcludes(noIsbnDesc, 'ISBN', 'no ISBN on the edition means none in the description');
assertExcludes(noIsbnDesc, ' · ', 'and no orphaned separator left behind');
// The editions table still says so out loud — that is a different statement.
assertIncludes(noIsbnDoc, 'No ISBN', 'the editions table still reports the absence');

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

// Counts read as English. A new catalogue is full of ones — most publisher and
// author pages have exactly one of something today — and every count on the
// site was written `${num(n)} things`, so those pages said "1 editions · 1
// works · 1 authors in this catalogue" (owner report, 1 Sep 2026).
var onePub = String(
  renderPublisher({
    id: 'p2', slug: 'lone', name: 'Lone House',
    works: [{ id: 'w', slug: 'one', title: 'One', authors: [] }], total: 1,
    authors: [{ id: 'a1', name: 'Someone', slug: 'someone' }], languages: ['Malayalam'],
    edition_count: 1, earliest_year: 2013, decades: { '2010s': 1 }, indexable: true,
  }).text(),
);
assertIncludes(onePub, '1 edition ', 'one edition is an edition');
assertExcludes(onePub, '1 editions', '…never "1 editions"');
assertExcludes(onePub, '1 works', '…nor "1 works"');
assertExcludes(onePub, '1 authors', '…nor "1 authors"');
var oneAuthor = String(
  renderAuthor({
    id: 'a2', slug: 'one-book', name: 'One Book', works: [], translated_works: [],
    publishers: [], languages: ['Malayalam'], work_count: 1, edition_count: 1,
    decades: {}, indexable: true,
  }).text(),
);
assertIncludes(oneAuthor, '>1 work<', 'an author with one book has one work');
assertExcludes(oneAuthor, '1 works', '…not "1 works"');
// Portraits and logos are the LCP image on these pages and were the only
// images on the site fetched straight from a third-party origin — every other
// image goes through /img/c so the edge serves it.
var portraitDoc = String(
  renderAuthor({
    id: 'a3', slug: 'p', name: 'Portrait', works: [], translated_works: [], publishers: [],
    image_url: 'https://covers.openlibrary.org/a/id/5539485-L.jpg', decades: {}, indexable: true,
  }).text(),
);
assertIncludes(portraitDoc, 'src="/img/c?u=', 'an author portrait is served through the proxy');
var logoDoc = String(
  renderPublisher({
    id: 'p3', slug: 'l', name: 'Logo House', works: [], authors: [], total: 0, edition_count: 0,
    logo_url: 'https://ref.supabase.co/publishers/l.png', decades: {}, indexable: true,
  }).text(),
);
assertIncludes(logoDoc, 'src="/img/c?u=', '…and so is a publisher logo');

// --------------------------------------------------------------------------
// Home, search, browse, hubs
// --------------------------------------------------------------------------

var homeDoc = String(
  renderHome({
    featured: { id: 'f', slug: 'chemmeen', title: 'Chemmeen', authors: [{ name: 'Thakazhi' }],
                year: 1956, language: 'Malayalam', cover_url: 'https://x/c.jpg' },
    recent: [{ id: 'r', slug: 'kayar', title: 'Kayar', authors: [] }],
    top_rated: [{ id: 't', slug: 'randamoozham', title: 'Randamoozham', authors: [], rating: 4.7 }],
    languages: [{ name: 'Malayalam', slug: 'malayalam', count: 418 },
                { name: 'Tamil', slug: 'tamil', count: 204 }],
    genres: [{ name: 'Literary fiction', slug: 'literary-fiction', count: 212 }],
    translation_pairs: [{ original: { id: 'o', slug: 'aadujeevitham', title: 'ആടുജീവിതം',
                                      language: 'Malayalam', year: 2008, authors: [] },
                          translation: { id: 'g', slug: 'goat-days', title: 'Goat Days',
                                         language: 'English', year: 2012, authors: [] } }],
    work_count: 1403, author_count: 1190, publisher_count: 1067,
  }).text(),
);
assertIncludes(homeDoc, 'action="/search"', 'home leads with a working search form');
assertIncludes(homeDoc, 'href="/language/malayalam"', 'home links every language hub — the crawl root');
assertIncludes(homeDoc, 'href="/genre/literary-fiction"', 'home links the genre hubs');
assertIncludes(homeDoc, 'href="/book/chemmeen"', 'the featured book is a link');
assertIncludes(homeDoc, '1,403', 'the catalogue size is stated');
assertIncludes(homeDoc, 'Goat Days', 'the translation-pairs module renders');
assertIncludes(homeDoc, '"@type":"WebSite"', 'home emits WebSite');
assertIncludes(homeDoc, 'SearchAction', 'home declares a SearchAction for the sitelinks box');
assertIncludes(homeDoc, 'content="index, follow"', 'home is indexable');

var searchDoc = String(
  renderSearch({ q: 'chemmeen', works: [{ id: 'w', slug: 'chemmeen', title: 'ചെമ്മീൻ', authors: [] }],
                 authors: [], publishers: [], matched_scripts: ['ചെമ്മീൻ'] }).text(),
);
assertIncludes(searchDoc, 'content="noindex, follow"',
  'search is noindex — it generates infinite near-duplicate URLs');
assertIncludes(searchDoc, 'also matched', 'the cross-script hit is called out');
assertIncludes(searchDoc, 'href="/book/chemmeen"', 'results are crawlable links even though noindex');

var emptySearch = String(renderSearch({ q: 'qwertyuiop', works: [], authors: [], publishers: [] }).text());
assertIncludes(emptySearch, 'Nothing for', 'zero results is a real page, not a dead end');
assertIncludes(emptySearch, 'href="/browse"', 'and it offers somewhere to go');
assertIncludes(emptySearch, 'href="/genres"', 'zero results offers the genre door');
assertIncludes(emptySearch, 'href="/browse?sort=rating"', '…and the top-rated door');

var hubDoc = String(
  renderHub({ kind: 'language', name: 'Malayalam', slug: 'malayalam', form: null,
              works: [{ id: 'w', slug: 'chemmeen', title: 'Chemmeen', authors: [] }],
              start_here: [{ id: 's', slug: 'kayar', title: 'Kayar', authors: [] }],
              total: 418, page: 1, per_page: 24,
              languages: [], forms: [{ name: 'Novel', slug: 'novel', count: 214 }], genres: [] }).text(),
);
assertIncludes(hubDoc, 'Malayalam literature', 'the language hub is titled as literature');
assertIncludes(hubDoc, 'Malayalam has one of the shortest', 'the editorial intro renders');
assertIncludes(hubDoc, 'content="index, follow"', 'hubs ARE indexed — they win the queries nobody owns');
assertIncludes(hubDoc, 'href="/language/malayalam/novel"', 'the hub links its form sub-hubs');
assertIncludes(hubDoc, '"@type":"CollectionPage"', 'hubs emit CollectionPage');
assertIncludes(hubDoc, 'canonical" href="https://kitabi.in/language/malayalam"', 'page 1 self-canonicals');

// Page 2 must canonical to ITSELF. Canonicalising it back to page 1 de-indexes
// the deep catalogue, which is most of it.
var hub2 = String(
  renderHub({ kind: 'language', name: 'Malayalam', slug: 'malayalam', form: null, works: [],
              start_here: [], total: 418, page: 2, per_page: 24, languages: [], forms: [], genres: [] }).text(),
);
assertIncludes(hub2, 'canonical" href="https://kitabi.in/language/malayalam?page=2"',
  'page 2 canonicals to itself, never back to page 1');
assertIncludes(hub2, 'page 2', 'page 2 has its own title');

var browseDoc = String(
  renderBrowse({ works: [], total: 0, page: 1, per_page: 24, languages: [], forms: [], genres: [] }).text(),
);
assertIncludes(browseDoc, 'content="noindex, follow"', 'faceted browse is noindex, follow');

// The browse toolbar: every facet the API takes is a chip row, chips merge
// into the current query (Sort × Type × Genre × Language × Length compose),
// and the active chip is marked. The facets were in the payload all along —
// the old renderer just never drew them.
var facetedBrowse = String(
  renderBrowse(
    {
      works: [{ id: 'w', slug: 'chemmeen', title: 'Chemmeen', authors: [] }],
      total: 30, page: 1, per_page: 24,
      languages: [{ name: 'Malayalam', slug: 'malayalam', count: 300 },
                  { name: 'Tamil', slug: 'tamil', count: 120 }],
      forms: [{ name: 'Novel', slug: 'novel', count: 214 }],
      genres: [{ name: 'Fiction', slug: 'fiction', count: 190 },
               { name: 'Crime', slug: 'crime', count: 41 }],
    },
    { query: { genre: 'Crime', sort: 'rating' } },
  ).text(),
);
assertIncludes(facetedBrowse, 'href="/browse?genre=Crime&amp;sort=rating&amp;page=2"',
  'the pager keeps every active facet');
assertIncludes(facetedBrowse, 'href="/browse?genre=Crime&amp;length=short&amp;sort=rating"',
  'a length chip merges into the active query instead of replacing it');
assertIncludes(facetedBrowse, 'href="/browse?form=Novel&amp;genre=Crime&amp;sort=rating"',
  'a type chip composes with genre and sort');
assertIncludes(facetedBrowse, 'href="/browse?genre=Crime"',
  'the A–Z sort chip drops the sort param rather than pinning sort=title');
assert(
  /aria-current="true"\s+href="\/browse\?genre=Crime&amp;sort=rating">Top rated</.test(facetedBrowse),
  'the active sort chip is marked with aria-current',
);
assertIncludes(facetedBrowse, 'Top rated', 'the "best books" sort exists');
assertExcludes(facetedBrowse, 'aria-current=&quot;',
  'the attribute is emitted raw — entity-escaped quotes reached production for weeks');
assertIncludes(facetedBrowse, 'under 200 pp', 'the short-reads chip says the number readers search');
assertIncludes(facetedBrowse, 'Clear all', 'an active filter can always be cleared');

// Direction C + A's sort (docs/browse-filters-mockups.html, owner pick,
// 9 Aug 2026): a segmented sort control, then one <details> door per facet
// whose popover holds only that facet. name="facet" gives native
// one-open-at-a-time — zero JS, links in the DOM regardless.
assertIncludes(facetedBrowse, '<details class="fdoor live" name="facet">',
  'the active facet is a live door in the exclusive group');
assertIncludes(facetedBrowse, 'Genre · Crime <i>▾</i>',
  'an active door carries its value — the closed bar reads as a sentence');
assertIncludes(facetedBrowse, '<span class="seg">', 'sort is a segmented control, not chips');
assertIncludes(facetedBrowse, 'All genres', 'each popover offers its own All');
assertIncludes(facetedBrowse, 'Clear genre', 'an active facet clears from inside its door');
assertIncludes(facetedBrowse, 'href="/genres">All 2 genres →',
  'the genre popover doors out to the full directory');

var pristineBrowse = String(
  renderBrowse(
    { works: [{ id: 'w', slug: 'x', title: 'X', authors: [] }], total: 1, page: 1,
      per_page: 24, languages: [], forms: [], genres: [] },
    { query: {} },
  ).text(),
);
assertExcludes(pristineBrowse, 'fdoor live', 'no filters active → no live doors');
assertExcludes(pristineBrowse, 'Clear all', 'nothing to clear on a pristine browse');
assertExcludes(pristineBrowse, '✕', 'and no ✕ anywhere');

// A dead-end browse names each active filter and offers to drop exactly it.
var deadEnd = String(
  renderBrowse(
    { works: [], total: 0, page: 1, per_page: 24, languages: [], forms: [], genres: [] },
    { query: { language: 'Malayalam', length: 'short' } },
  ).text(),
);
assertIncludes(deadEnd, 'Nothing matches those filters', 'the empty state is honest');
assertIncludes(deadEnd, 'href="/browse?length=short"',
  'dropping the language keeps the length filter');
assertIncludes(deadEnd, 'href="/browse?language=Malayalam"',
  'dropping the length keeps the language filter');
assertIncludes(deadEnd, 'Language: Malayalam', 'each active filter is named');

// --------------------------------------------------------------------------
// Series, translation groups, lists, reviews, readers (W8–W12)
// --------------------------------------------------------------------------

// Fixtures follow schemas/public.py SeriesPage — `entries` (one per position,
// translations collapsed) plus the flat `works` the API still serves.
var swami = { id: '1', slug: 'swami', title: 'Swami and Friends', authors: [{ name: 'Narayan' }], year: 1935, language: 'English' };
var swamiMl = { id: '1b', slug: 'swami-ml', title: 'സ്വാമിയും കൂട്ടുകാരും', authors: [{ name: 'Narayan' }], year: 1985, language: 'Malayalam' };
var bachelor = { id: '2', slug: 'bachelor', title: 'The Bachelor of Arts', authors: [], year: 1937, language: 'English' };
var seriesDoc = String(
  renderSeries({ id: 's', slug: 'malgudi', name: 'Malgudi', indexable: true,
    description: 'R. K. Narayan’s fictional town.',
    languages: ['English', 'Malayalam'],
    entries: [{ number: 1, book: swami, also: [swamiMl] }, { number: 2, book: bachelor, also: [] }],
    works: [swami, swamiMl, bachelor] }).text(),
);
assertIncludes(seriesDoc, 'Swami and Friends', 'the series lists its books');
assertIncludes(seriesDoc, 'href="/book/swami"', 'each entry links to the book');
assertIncludes(seriesDoc, '"@type":"ItemList"', 'a series is an ItemList');
assertIncludes(seriesDoc, 'Also in Malayalam', 'a translated position names its other languages');
assertIncludes(seriesDoc, 'R. K. Narayan', 'the series description is rendered');
// Three works, two positions: the page counts books, not translations.
assertIncludes(seriesDoc, 'Series · 2 books', 'a position is counted once, not once per language');
if (seriesDoc.split('സ്വാമിയും').length - 1 > 1) {
  throw new Error('the Malayalam translation is listed twice — positions must collapse');
}

// The renderer deploys separately from the API, so it must still render the
// flat shape it was fed before `entries` existed.
var seriesLegacyDoc = String(
  renderSeries({ id: 's', slug: 'malgudi', name: 'Malgudi', indexable: true, works: [swami, bachelor] }).text(),
);
assertIncludes(seriesLegacyDoc, 'Swami and Friends', 'the pre-entries payload still renders');
assertIncludes(seriesLegacyDoc, 'Series · 2 books', 'and still counts its books');

// A series carries its OWN rating and reviews (schemas/public.py SeriesPage) —
// about the saga, separate from the ratings on the books inside it.
var seriesRatedDoc = String(
  renderSeries({ id: 's', slug: 'ps', name: 'Ponniyin Selvan', indexable: true,
    entries: [{ number: 1, book: swami, also: [] }, { number: 2, book: bachelor, also: [] }],
    works: [swami, bachelor],
    rating: { average: 4.6, count: 32, distribution: { '5': 24, '4': 6, '3': 2 } },
    reviews: [{ id: 'r1', body: 'A monumental saga.', rating: 5, created_at: '2026-08-13T00:00:00Z',
                reviewer: { id: 'u1', display_name: 'Shamshi', is_public: true } }] }).text(),
);
assertIncludes(seriesRatedDoc, 'A monumental saga.', 'the series review text is in the HTML');
assertIncludes(seriesRatedDoc, '4.6', 'the series average is shown');
assertIncludes(seriesRatedDoc, '32 ratings', 'and how many gave it');
assertIncludes(seriesRatedDoc, 'each book has its own rating', 'the page says the pools are separate');
// A series with no ratings of its own must not print an empty review block.
assertExcludes(seriesDoc, 'What readers say about the series', 'no series rating, no block');

// A reader's profile lists series reviews beside book reviews. Before this the
// row shape only knew about books, so a series review rendered as an empty card
// pointing at "/" — bookPath degrades that way by design.
var readerDoc = String(
  renderReader({ id: 'u1', username: 'shamshi', display_name: 'Shamshi', score: 10,
    reviews: [
      { id: 'r1', body: 'A monumental saga.', rating: 5, created_at: '2026-08-13T00:00:00Z',
        work: null, series: { id: 's', slug: 'ps', name: 'Ponniyin Selvan' } },
      { id: 'r2', body: 'This volume drags.', rating: 2, created_at: '2026-08-12T00:00:00Z',
        work: swami, series: null },
    ] }).text(),
);
assertIncludes(readerDoc, 'href="/series/ps"', 'a series review links to the series');
assertIncludes(readerDoc, 'Ponniyin Selvan', 'and names it');
assertIncludes(readerDoc, 'A monumental saga.', 'the series review body is rendered');
assertIncludes(readerDoc, 'href="/book/swami"', 'a book review still links to the book');

var transDoc = String(
  renderTranslations({ group_id: 'g', title: 'ആടുജീവിതം', group_rating: 4.5, group_rating_count: 1043,
    description: 'A Malayali migrant is enslaved on a Saudi goat farm.',
    original: { id: 'o', slug: 'aadujeevitham', title: 'ആടുജീവിതം', language: 'Malayalam', year: 2008,
                rating: 4.6, is_original: true, authors: [] },
    translations: [{ id: 't', slug: 'goat-days', title: 'Goat Days', language: 'English', year: 2012,
                     rating: 4.4, is_original: false, authors: [] }],
    translators: [{ id: 'x', name: 'Joseph Koyippally', slug: 'joseph-koyippally' }] }).text(),
);
assertIncludes(transDoc, 'Goat Days', 'the group lists every language');
assertIncludes(transDoc, 'the original', 'the original is labelled');
assertIncludes(transDoc, '4.5', 'the group rating is shown');
assertIncludes(transDoc, 'href="/author/joseph-koyippally"', 'translators get real links');
assertIncludes(transDoc, 'canonical" href="https://kitabi.in/translations/aadujeevitham"',
  'the group canonicals to the original, so it never competes with the book page');

var listDoc = String(
  renderList(
    { slug: 'start', title: 'Where to start', intro: 'A route through it.',
      entries: [{ slug: 'chemmeen', why: 'The one everyone names, and it earns it.' },
                { slug: 'gone-away', why: 'This book was merged away.' }] },
    [{ id: 'c', slug: 'chemmeen', title: 'Chemmeen', authors: [{ name: 'Thakazhi' }], year: 1956 }],
  ).text(),
);
assertIncludes(listDoc, 'The one everyone names', 'the editorial "why" is the point of a list');
assertIncludes(listDoc, 'href="/book/chemmeen"', 'entries link to the books');
assertExcludes(listDoc, 'This book was merged away',
  'an entry whose book no longer resolves is skipped, not rendered broken');
assertIncludes(listDoc, 'content="index, follow"', 'editorial lists are indexable');

// An index with no lists ready is a real page, not a broken one. The lists are
// written ahead of the catalogue deliberately and switch on as books arrive.
var emptyIndex = String(renderListIndex([]).text());
assertIncludes(emptyIndex, "Editors' lists", 'the list index renders even with nothing ready');

var reviewsDoc = String(
  renderReviews({ work: { id: 'w', slug: 'chemmeen', title: 'Chemmeen', authors: [] },
    rating: { average: 4.4, count: 312, distribution: { '5': 193, '4': 81 } },
    reviews: [{ rating: 5, body: 'Wonderful.', reviewer: { display_name: 'A reader' } }],
    total: 41, page: 1, per_page: 20 }).text(),
);
assertIncludes(reviewsDoc, 'Wonderful.', 'reviews render');
// The field is `body` — PublicReviewOut has never had a `text`. Reading the
// wrong name printed the reviewer's name, stars and date with no review under
// them, on both this page and the book page, for as long as public reviews
// have existed (found 9 Aug 2026 on /book/avalkkoppam). It survived because the
// fixtures said `text` too, so renderer and test agreed with each other rather
// than with the API.
assertExcludes(
  String(renderReviews({ work: { id: 'w', slug: 'c', title: 'C', authors: [] },
    rating: { average: 5, count: 1, distribution: { '5': 1 } },
    reviews: [{ rating: 5, text: 'Wrong field.', reviewer: { display_name: 'A reader' } }],
    total: 1, page: 1, per_page: 20 }).text()),
  'Wrong field.',
  'only `body` is the review text — a stray `text` field is not rendered',
);
assertIncludes(reviewsDoc, 'href="/book/chemmeen"', 'and link back to the book');
assertIncludes(reviewsDoc, 'content="index, follow"', 'a page with 41 reviews is worth indexing');

var thinReviews = String(
  renderReviews({ work: { id: 'w', slug: 'x', title: 'X', authors: [] },
    rating: { average: null, count: 0, distribution: {} }, reviews: [], total: 0, page: 1, per_page: 20 }).text(),
);
assertIncludes(thinReviews, 'content="noindex, follow"', 'an empty reviews page is not indexed');
assertIncludes(thinReviews, 'No reviews yet', 'but it is still a real page');

var readerDoc = String(
  renderReader({ id: 'u', username: 'arundhati', display_name: 'Arundhati M.', score: 214,
    library_visible: true, recent: [{ id: 'b', slug: 'chemmeen', title: 'Chemmeen', authors: [] }] }).text(),
);
assertIncludes(readerDoc, 'Arundhati M.', 'the reader page renders');
assertIncludes(readerDoc, '@arundhati', 'the handle is shown');
assertIncludes(readerDoc, 'href="/book/chemmeen"', 'their public shelf links to books');

var privateShelf = String(
  renderReader({ id: 'u', username: 'quiet', display_name: 'Quiet Reader', score: 3,
    library_visible: false, recent: [] }).text(),
);
assertIncludes(privateShelf, 'keeps their shelf private', 'a private shelf says so rather than looking empty');
assertIncludes(privateShelf, 'content="noindex, follow"',
  'a profile with nothing public is not indexed');

// A reader's own public reviews. The field is `body` — the name the API
// actually serialises (PublicReviewOut.body). Fixtures here used to say
// `text`, which is why every review on the live site rendered as a byline
// with no review under it.
var readerReviews = String(
  renderReader({ id: 'u', username: 'arundhati', display_name: 'Arundhati M.', score: 214,
    library_visible: true, recent: [{ id: 'b', slug: 'chemmeen', title: 'Chemmeen', authors: [] }],
    reviews: [{ id: 'r1', rating: 5, body: 'I read it first at fifteen.',
                created_at: '2026-07-14T00:00:00Z',
                work: { id: 'b', slug: 'chemmeen', title: 'Chemmeen',
                        authors: [{ name: 'Thakazhi', slug: 'thakazhi' }] } }] }).text(),
);
assertIncludes(readerReviews, 'What they wrote', 'a reader profile shows the reviews they made public');
assertIncludes(readerReviews, 'I read it first at fifteen', 'the review body is in the HTML');
assertIncludes(readerReviews, 'href="/book/chemmeen"', 'each review links to the book it is about');
assertIncludes(readerReviews, 'Thakazhi', "the book's author is named on the row");
assertIncludes(readerReviews, 'Rated 5 out of 5', 'their star rating rides along, labelled for screen readers');
// The reviewer is the page. The card's header slot belongs to the BOOK — the
// mirror of the book page, where it belongs to the reviewer. (Scoped to the
// card: the name legitimately appears in the title, h1, breadcrumb and meta.)
var reviewCard = readerReviews.slice(
  readerReviews.indexOf('<article class="rev">'),
  readerReviews.indexOf('</article>'),
);
assertIncludes(reviewCard, 'Chemmeen', 'the book heads the review card');
assertExcludes(reviewCard, 'Arundhati M.', 'the reader is not re-announced on their own review');

// A review is original prose that exists nowhere else on the site — it is
// exactly what makes a profile worth crawling, so it lifts the page past the
// floor on its own, with no public shelf.
var reviewerOnly = String(
  renderReader({ id: 'u', username: 'quiet', display_name: 'Quiet Reader', score: 3,
    library_visible: false, recent: [],
    reviews: [{ id: 'r1', rating: 4, body: 'Worth the slow first fifty pages.',
                work: { id: 'b', slug: 'kayar', title: 'Kayar', authors: [] } }] }).text(),
);
assertIncludes(reviewerOnly, 'keeps their shelf private', 'the private shelf note still stands');
assertIncludes(reviewerOnly, 'Worth the slow first fifty pages', 'and the reviews show anyway');
assertIncludes(reviewerOnly, 'content="index, follow"',
  'a private shelf does not suppress reviews the reader chose to publish');

// The old behaviour must not regress: nothing public at all is still noindex.
assertExcludes(privateShelf, 'What they wrote', 'no reviews section when there are none');

// --------------------------------------------------------------------------
// Self-hosted fonts
// --------------------------------------------------------------------------

var fontDoc = String(page({ title: 't', body: html`x` }).text());
assertIncludes(fontDoc, "@font-face", 'font faces are declared inline with the rest of the CSS');
assertIncludes(fontDoc, "/fonts/fraunces-latin.woff2", 'Fraunces is served from our own origin');
assertIncludes(fontDoc, "/fonts/inter-latin.woff2", 'Inter is served from our own origin');
assertExcludes(fontDoc, 'fonts.googleapis.com', 'never the Google Fonts CSS endpoint');
assertExcludes(fontDoc, 'fonts.gstatic.com', 'never the Google Fonts file origin');
assertIncludes(fontDoc, 'font-display:swap', 'swap — a slow font must never delay the paint');
assertIncludes(fontDoc, 'unicode-range', 'latin-ext only downloads on pages that need it');
assertIncludes(fontDoc, 'rel="preload" href="/fonts/fraunces-latin.woff2"', 'the primary faces are preloaded');
assertIncludes(fontDoc, 'as="font" type="font/woff2" crossorigin', 'preload is correctly typed and CORS-flagged');
// Preloading a subset that usually is not used would waste the bytes it saves.
assertExcludes(fontDoc, 'preload" href="/fonts/fraunces-latin-ext', 'the extended subset is NOT preloaded');

// --------------------------------------------------------------------------
// The cover proxy — the allowlist is the security model
// --------------------------------------------------------------------------

assert(
  coverSrc('https://covers.openlibrary.org/b/id/123-L.jpg') ===
    '/img/c?u=https%3A%2F%2Fcovers.openlibrary.org%2Fb%2Fid%2F123-L.jpg',
  'OpenLibrary covers are routed through our own origin',
);
assert(
  coverSrc('https://proj.supabase.co/storage/v1/object/public/covers/x.jpg').indexOf('/img/c?u=') === 0,
  'reader-uploaded covers from our bucket are proxied too',
);
assert(
  coverSrc('https://somewhere.example/x.jpg') === 'https://somewhere.example/x.jpg',
  'an unexpected host passes through rather than rendering as a broken image',
);
assert(coverSrc(null) === null, 'no cover URL stays no cover URL');

// allowedSource is what stands between this and an open proxy.
assert(allowedSource('https://covers.openlibrary.org/b/id/1-L.jpg') !== null, 'OpenLibrary is allowed');
assert(allowedSource('https://proj.supabase.co/storage/x.jpg') !== null, 'the Supabase bucket is allowed');
assert(allowedSource('https://evil.test/payload.jpg') === null, 'an arbitrary host is refused');
assert(allowedSource('http://covers.openlibrary.org/b/id/1-L.jpg') === null, 'http is refused — no downgrade');
assert(allowedSource('https://covers.openlibrary.org.evil.test/x.jpg') === null,
  'a suffix attack on an allowed host is refused');
assert(allowedSource('https://evil.test/#covers.openlibrary.org') === null,
  'an allowed host in the fragment is not an allowed host');
assert(allowedSource('https://user:pw@covers.openlibrary.org/x.jpg') === null,
  'embedded credentials are refused');
assert(allowedSource('https://covers.openlibrary.org:8080/x.jpg') === null,
  'a non-standard port is refused — a CDN does not need one');
assert(allowedSource('file:///etc/passwd') === null, 'non-http schemes are refused');
assert(allowedSource('https://169.254.169.254/latest/meta-data/') === null,
  'the cloud metadata endpoint is refused — this must never be an SSRF instrument');
assert(allowedSource('') === null && allowedSource(null) === null, 'empty input is refused');
assert(allowedSource('https://covers.openlibrary.org/' + 'x'.repeat(700)) === null,
  'an absurdly long URL is refused before anything is fetched');

// --------------------------------------------------------------------------
// Typeahead — optional by construction
// --------------------------------------------------------------------------

var sdoc = String(page({ title: 't', body: html`x` }).text());
assertIncludes(sdoc, 'role="search"', 'the search form is still a plain labelled form');
assertIncludes(sdoc, 'action="/search" method="get"',
  '…and a plain GET, so it works with JavaScript disabled, blocked or failed');
assertIncludes(sdoc, '<script defer>', 'the typeahead is deferred — never blocking');
assertIncludes(sdoc, '/api/suggest', 'it calls our own origin, not a second one');
assertIncludes(sdoc, '.sugg{', 'its styles ship with the rest of the inlined CSS');
// The suggestion labels come from a database and are written into innerHTML.
assertIncludes(SUGGEST_JS, 'replace(/[&<>"\']/g', 'suggestion text is escaped before innerHTML');
assertIncludes(SUGGEST_JS, 'aria-autocomplete', 'the combobox is announced to assistive tech');
assertIncludes(SUGGEST_JS, "e.key === 'Escape'", 'Escape closes the list');
// Enter must only be intercepted when a suggestion is genuinely selected,
// otherwise someone ignoring the dropdown cannot submit their own query.
assertIncludes(SUGGEST_JS, "e.key === 'Enter' && active >= 0",
  'Enter submits the form unless a suggestion is selected');

// --------------------------------------------------------------------------
// The catch-all's asset allowlist
// --------------------------------------------------------------------------
//
// This runs BEFORE static assets, so getting it wrong takes the site down. The
// cost is asymmetric: a missing font is cosmetic, a missing app-association
// file silently breaks universal links for every installed app.

assert(isAsset('/.well-known/apple-app-site-association'),
  'the iOS app-association file MUST pass through — losing it orphans installed apps');
assert(isAsset('/.well-known/assetlinks.json'), 'the Android association file passes through');
assert(isAsset('/fonts/inter-latin.woff2'), 'self-hosted fonts pass through');
assert(isAsset('/fonts/fraunces-latin-ext.woff2'), 'every font subset passes through');
assert(isAsset('/robots.txt'), 'robots.txt passes through');
assert(isAsset('/sitemap.xml'), 'sitemap.xml passes through');
assert(isAsset('/logo.svg') && isAsset('/ico.png') && isAsset('/apple-touch-icon.png'),
  'icons pass through');
assert(isAsset('/privacy.html') && isAsset('/terms.html'), 'the legal pages pass through');
assert(isAsset('/404.html'), 'the 404 document itself passes through');

// …and everything else is a 404, which is the entire point.
assert(!isAsset('/total-nonsense-url'), 'an unmatched path is not an asset');
assert(!isAsset('/book/chemmeen'), 'a real route is not handled here (its own Function wins)');
assert(!isAsset('/'), 'home is not handled here either');
assert(!isAsset('/fonts'), 'the bare directory is not a file');
assert(!isAsset('/.well-known'), 'nor is the bare well-known directory');

// Cloudflare Pages 308s /x.html to /x automatically, so an allowlist that names
// only the .html form sends the redirect to a path it doesn't recognise. That
// took the privacy policy offline once; both spellings are required.
assert(isAsset('/privacy') && isAsset('/privacy.html'), 'privacy is reachable both ways');

// The app pitch. Every page's header and footer links to /app, and it 404'd
// from the day the reference site took "/" over until app.html existed — the
// page was still deployed, just unreachable, which is the version of this bug
// nobody notices because nothing errors.
assert(isAsset('/app') && isAsset('/app.html'), 'the app page is reachable both ways');
assert(isAsset('/terms') && isAsset('/terms.html'), 'terms is reachable both ways');
var footerDoc = String(page({ title: 't', body: html`x` }).text());
assertIncludes(footerDoc, 'href="/privacy"', 'the footer links the clean URL, avoiding the hop');
assertExcludes(footerDoc, 'href="/privacy.html"', 'not the .html form that 308s');

// "/" is served by the catch-all, because a [[path]] Function shadows
// index.js for the root — named routes keep winning, "/" does not, and the
// home page 404'd in production until this was explicit.
assert(!isAsset('/'), 'home is not an asset — it is rendered, and by the catch-all');

// ===== canonical host (functions/_lib/host.js) =====
//
// www.kitabi.in served the whole site byte-identical at 200 with `index,
// follow` — a full duplicate host. These lock in the redirect and, more
// importantly, everything it must NOT touch.

assert(canonicalHostUrl('https://kitabi.in/') === null, 'the apex is already canonical');
assert(canonicalHostUrl('https://kitabi.in/book/nrittam') === null, 'a deep apex URL is left alone');

assert(
  canonicalHostUrl('https://www.kitabi.in/') === 'https://kitabi.in/',
  'www home redirects to the apex',
);
assert(
  canonicalHostUrl('https://www.kitabi.in/author/m-t-vasudevan-nair') ===
    'https://kitabi.in/author/m-t-vasudevan-nair',
  'a named route redirects too — this is why it is middleware and not the catch-all',
);
assert(
  canonicalHostUrl('https://www.kitabi.in/search?q=%E0%B4%9A%E0%B5%86') ===
    'https://kitabi.in/search?q=%E0%B4%9A%E0%B5%86',
  'the query string survives, encoding intact',
);
assert(
  canonicalHostUrl('https://www.kitabi.in/browse?language=malayalam&page=3') ===
    'https://kitabi.in/browse?language=malayalam&page=3',
  'multiple query params survive in order',
);

// Apple does not follow redirects for the association file, and iOS only
// re-checks at install — so a redirect here breaks universal links invisibly,
// for weeks, for everyone who already installed.
assert(
  canonicalHostUrl('https://www.kitabi.in/.well-known/apple-app-site-association') === null,
  'the app-association file is never redirected',
);
assert(
  canonicalHostUrl('https://www.kitabi.in/.well-known/assetlinks.json') === null,
  'nor is the Android one',
);

// Exact hosts only — a startsWith('www.') heuristic would break previews.
assert(
  canonicalHostUrl('https://kitabi-in.pages.dev/book/nrittam') === null,
  'preview deployments are untouched',
);
assert(canonicalHostUrl('http://localhost:8788/') === null, 'local dev is untouched');
assert(
  canonicalHostUrl('https://wwwkitabi.in/') === null,
  'a lookalike host without the dot is not ours to redirect',
);

// One 301, not two: http on www must land on https at the apex directly.
assert(
  canonicalHostUrl('http://www.kitabi.in/lists') === 'https://kitabi.in/lists',
  'http+www collapses to https+apex in a single hop',
);
assert(
  canonicalHostUrl('https://www.kitabi.in/browse?a=1#frag') === 'https://kitabi.in/browse?a=1#frag',
  'the fragment survives too',
);

// --------------------------------------------------------------------------
// The app band — the one call to action on every public page
//
// A store badge that goes nowhere is worse than one that admits it isn't there
// yet: a reader only learns the difference by tapping it. So the rule this
// pins is not "there are two badges", it is "a badge is a link if and only if
// that store is live". Android shipped 31 Aug 2026; iOS was still in review.
// --------------------------------------------------------------------------

var band = String(appBand());

assertIncludes(band, PLAY_STORE_URL, 'the app band carries the real Play Store URL');
assertIncludes(
  band,
  '<a class="store" href="' + PLAY_STORE_URL + '"',
  'Google Play is a real link, not a dead badge',
);
assertExcludes(band, 'href="#"', 'no badge links to nowhere');

// The App Store half, while APP_STORE_URL is null. An inert <span>, not an <a>:
// the reader must not learn which button works by tapping it.
assert(APP_STORE_URL === null, 'iOS is still in review — nothing to link to yet');
assertIncludes(band, '<span class="store ghost off"', 'the App Store button is inert while in review');
assertIncludes(band, '<small>In review</small>', 'and says so, rather than looking clickable');

// The band must never invent a second <a> for a store that has no URL: exactly
// one anchor while exactly one store is live.
assert((band.match(/<a class="store"/g) || []).length === 1, 'one live store, one link');

// Both halves are the same object — same icon, same two-line label — so the row
// reads as one row of buttons. Only the kicker line differs.
assert((band.match(/class="store[" ]/g) || []).length === 2, 'two buttons, always');
assert((band.match(/class="ic"/g) || []).length === 2, 'each button carries its store mark');
assertIncludes(band, '<small>Get it on</small><span>Google Play</span>', 'the live half reads "Get it on"');

// A URL typo here is invisible in review and fatal in production — the badge
// still renders, it just lands on a Play Store error page.
assert(
  PLAY_STORE_URL === 'https://play.google.com/store/apps/details?id=in.kitabi.kitabi',
  'the Play listing id matches the app applicationId',
);

// html`` escapes interpolations, so the query string's "=" and "?" must survive
// intact — an entity-escaped href is the 9 Aug aria-current bug wearing a
// different hat, and it would look perfectly fine on screen.
assertExcludes(band, '&amp;', 'the store URL is not entity-mangled');
