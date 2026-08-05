# Kitabi on the web — the public book destination

> **What this plans:** turning `kitabi.in` from a launching-soon page with three
> thin share pages into a public, crawlable, fast **book reference site** — the
> thing people mean when they say "IMDB for books" — without adding a service,
> a bill, or a framework.
>
> Companion mockups: [web-mockups.html](web-mockups.html) (open in a browser —
> every page type below is drawn there as a browser frame).
> Design tokens: [screen-design.md](screen-design.md). Product spec:
> [feature-map.md](../feature-map.md). Deployment reality: [../STATUS.md](../STATUS.md).

---

## 1. The thesis, in one paragraph

IMDB does not win on data modelling. It wins because when you type a film's name
into Google, IMDB is the first result, the page loads before you've finished
reading the snippet, and it answers *"is this worth my evening?"* in one screen —
rating, cast, plot, where to watch, what's like it. Kitabi already has the data
model for the book equivalent (Work/Edition, authors, publishers, series,
translations, ratings, reviews). What it does not have is **a page a search
engine can read** or **a reason to be the first result**. This plan is about
those two things, and nothing else.

The reason to be the first result is not "books" — that war is lost to Goodreads
and Amazon. It is **Indic-language literature in English-readable pages**. Search
*"Chemmeen novel"*, *"Thakazhi Sivasankara Pillai books"*, *"Malayalam novels
list"*, *"Aadujeevitham English translation"* today and the results are Wikipedia
stubs, blogspot posts, and Amazon listings. Nobody owns those queries. Kitabi's
catalog is already seeded language-first (14 Indic languages), already carries
romanized titles (`title_translit`) so an English keyboard finds a Malayalam
book, and already models **translation as a first-class graph**. That is a
defensible wedge that the incumbents structurally do not have.

So: the site is an IMDB-shaped reference site whose *content moat is
translations and Indic-language depth*, and whose *conversion goal* is the app.

---

## 2. Where we are today — measured, 4 Aug 2026

I measured production before planning. This is the honest baseline.

| Fact | Value | Verdict |
|---|---|---|
| `/b/:id` shell TTFB | **0.62 s** | Slow — the edge function blocks on an uncached API call |
| Text a non-JS crawler sees on a book page | *"Opening the book… Track, lend, and share your library."* | **Zero book content** |
| Extra round trip the browser must make | `api.kitabi.in/catalog/works/:id`, **+0.31 s** | Content starts arriving at ~1 s, best case |
| Render-blocking third parties | `fonts.googleapis.com` + `fonts.gstatic.com` | 2 extra DNS+TLS handshakes before first paint |
| Works / authors / publishers live | **1,402 / 1,189 / 1,066** | Enough to launch, not enough to rank |
| `GET /catalog/browse/genres` | `[]` | **No genre is attached to any seeded work** |
| `GET /catalog/browse/forms` | `["Novel"]` | Form facet is effectively empty too |
| Public page types | 3 (`/b/`, `/a/`, `/p/`) | No home, search, browse, genre, series, or list page |
| Reviews on the web | none — `/catalog/works/{id}/reviews` requires auth | The single most IMDB-ish thing is invisible |

Two of these are not "improvements needed", they are blockers:

**(a) The pages render client-side.** The edge function
(`landing-page/functions/_og.js`) does an excellent job injecting Open Graph and
JSON-LD into the `<head>` — that is why WhatsApp previews look right. But the
`<body>` is a spinner. Googlebot *can* render JS, in a deferred second wave, at
its own discretion, and it consistently under-ranks pages whose visible HTML
doesn't match their structured data. Every other crawler (Bing, DuckDuckGo,
Perplexity, ChatGPT's fetcher, LLM training crawlers) mostly does not render at
all. **1,400 pages of spinner is not an index.**

**(b) The catalog has no genres.** Genre hubs are half the internal-linking
surface of a reference site. Right now there is nothing to build them from.

Everything else in this document is downstream of fixing those two.

---

## 3. The architecture decision

### Edge-rendered HTML from Cloudflare Pages Functions. No framework. No build step.

```
Browser ──► kitabi.in (Cloudflare Pages Function)
                 │  1. cache.match()  ── HIT (95%) ─► full HTML, ~40 ms TTFB
                 │
                 └─ MISS ─► api.kitabi.in/public/…  (ONE call, whole page)
                              └─► render template ─► cache.put() ─► HTML
```

The Pages Functions already exist and already fetch from the catalog API. This
plan does not introduce a new runtime — it **moves the rendering from the
browser into the function that is already running there**, and puts a cache in
front of it.

**Why not Next.js / Astro / Remix?** All three would work and would be pleasant
to write. All three break the rules this repo has held to: `landing-page/` is
"dependency-free static HTML/CSS — no build step, no frameworks" (CLAUDE.md), and
rule 8 is "no new services, no new monthly bills". An Astro+Cloudflare setup adds
a `node_modules`, a build pipeline, a framework upgrade treadmill, and a second
way to deploy the same site — for a site with **eleven page templates**. Eleven
templates is comfortably inside what a `functions/_lib/` directory of tagged
template literals handles well, and it keeps the whole public surface readable in
one sitting.

**The escape hatch, stated now so it isn't a surprise later:** if the template
count passes ~20, or the site needs client-side routing, or a second language's
UI makes the templates branch badly — port to Astro. The page contracts in §5
(one function, one payload, one HTML document) are deliberately framework-shaped,
so that port is a rewrite of the rendering layer only, never of the API.

### The one-payload rule

A page must cost **exactly one upstream API call**. Today's book page would need
four (work, reviews, similar, breadcrumbs). Four sequential calls from an edge
function to Singapore is 1.2 s of TTFB, and Cloudflare's edge is not necessarily
near Railway.

So the API grows a small **public read layer** (§7) whose endpoints are shaped
like *pages*, not like *resources*: `GET /public/book/{slug}` returns everything
the book page renders, already joined, already trimmed. This is a deliberate
break from the REST-shaped catalog API the app uses — the app is offline-first
and wants resources; the web is render-once and wants pages. They can coexist;
the public layer is a thin projection over the same services.

### Caching, in three layers

| Layer | What | TTL | Why |
|---|---|---|---|
| Edge HTML | `cache.put()` in the Pages Function | `s-maxage=300`, `stale-while-revalidate=86400` | A crawler burst hits cache, not Railway. Stale-while-revalidate means a cold-ish page is still instant and refreshes behind the request |
| Edge API | The `/public/*` JSON response | 60 s + SWR 1 h | Two page types sharing an author's data share the fetch |
| Images | Cover proxy (§6) | 30 d, `immutable` | Covers never change; today they're hotlinked from a third party |

Purge on write: the API already knows when a Work changes (`updated_at`,
revisions). A `POST /internal/purge` webhook → Cloudflare cache purge by URL keeps
the 5-minute window honest for edits, and costs nothing.

**Everything is served from cache to a crawler.** Google's crawl budget for a new
site is small; spending it on 0.6 s responses is how 1,400 pages take three months
to index instead of three weeks.

---

## 4. Information architecture — the URL map

URLs are the site's skeleton and are expensive to change later, so they get
decided once, here.

### 4.1 The slug decision

Today: `/b/47e95a54-829f-5f0c-bdea-f4f3be8c6bbe`. A UUID in a URL is bad for
click-through (it looks like spam in a SERP), bad for keyword relevance, and
impossible to say out loud.

**Add a `slug` column** (unique, indexed) to `works`, `authors`, `publishers`,
`series`. Generate from `title` — or from **`title_translit`** when the title is
non-Latin, which is a capability this repo already has and most competitors
don't. Disambiguate by appending author, then year, then `-2`, `-3`.

```
കയർ                      → /book/kayar
Chemmeen (Thakazhi)      → /book/chemmeen
Chemmeen (a second work) → /book/chemmeen-thakazhi-sivasankara-pillai
```

Rejected alternative: `/book/<slug>-<first-8-hex-of-uuid>`, which needs no
migration. At 100k works the birthday collision probability over an 8-hex space
is ~0.1% — small, but it fails *silently* and the failure is "two books share a
URL". A unique column fails loudly at write time. For a site whose entire purpose
is SEO, spend the migration.

### 4.2 The map

| URL | Page | Indexed? | Mockup |
|---|---|---|---|
| `/` | Home — the discovery front door | ✅ | **W1** |
| `/book/<slug>` | **Work page** — the flagship | ✅ *(gated, §8.3)* | **W3** |
| `/book/<slug>/editions` | Every printing of a work | ✅ if ≥3 editions | W3b |
| `/book/<slug>/reviews` | Paginated reviews | ✅ if ≥3 reviews | **W11** |
| `/author/<slug>` | Author — bio, works, translations | ✅ *(gated)* | **W4** |
| `/publisher/<slug>` | Publisher — catalogue, imprints | ✅ *(gated)* | **W5** |
| `/series/<slug>` | Series in reading order | ✅ | W8 |
| `/genre/<slug>` | Genre hub | ✅ | **W6** |
| `/language/<slug>` | Language hub — *the wedge* | ✅ | **W7** |
| `/language/<slug>/<form>` | e.g. `/language/malayalam/novels` | ✅ | W7b |
| `/translations/<slug>` | A translation group as one page | ✅ | W9 |
| `/list/<slug>` | Editorial list | ✅ | **W10** |
| `/reader/<username>` | Public reader profile | ✅ if opted-in | W12 |
| `/browse?…` | Faceted browse | ❌ `noindex, follow` | W6b |
| `/search?q=` | Search results | ❌ `noindex, follow` | **W2** |
| `/isbn/<isbn>` | **ISBN address** — either form | 301 → `/book/<slug>` | — |
| `/b/:uuid`, `/a/:uuid`, `/p/:uuid` | **Legacy** | 301 → slug URL | — |

Facet combinations explode; only the canonical hubs (`/genre/x`,
`/language/x`, `/language/x/<form>`) are indexable. Everything else in
`/browse` is `noindex, follow` so crawlers still walk the links without
indexing 4,000 near-duplicate filter pages. This is the single most common way
catalog sites get themselves demoted.

### 4.3 Keeping the old URLs alive

`/b/:uuid` must keep working forever, unconditionally:

- It's in the sitemap Google has already crawled.
- **Universal / app links are bound to it** — `apple-app-site-association` lists
  `/b/*`, `/a/*`, `/p/*` and, per the note in CLAUDE.md, iOS only re-evaluates
  the association **at install**. Removing those paths orphans every already-
  installed app.
- Every share card ever generated points at it.

So: `/b/:uuid` → **301** to `/book/<slug>`, and the AASA + `assetlinks.json`
gain `/book/*`, `/author/*`, `/publisher/*` **in addition to** the old paths.
Ship the association-file change **before** the redirect, and expect Apple's CDN
to lag ~24 h.

---

## 5. The pages

Each page below lists what it answers, what it links to (crawl paths matter as
much as content), and its structured data. Drawn in
[web-mockups.html](web-mockups.html).

### W1 · Home — `/`

Today `/` is a 76 KB launching-soon marketing page. It becomes the front door of
a reference site, with the app pitch demoted to one band.

Above the fold: **the search box** (a book site's home page is a search box —
everything else is proof it has answers), then a rotating *"Reading Room"* hero
featuring one book with real editorial copy.

Below: **Recently added** · **Highest rated** · **Browse by language** (the 14
Indic languages as a typographic grid — this is the hub row that feeds crawl
depth) · **Translations, both ways** (the signature module: original ↔
translation pairs) · **Authors A–Z** entry · one honest app band.

- **Links out to:** every hub, ~40 books, ~12 authors. Home is the crawl root;
  every indexable hub must be ≤2 clicks from it.
- **JSON-LD:** `WebSite` + `SearchAction` (earns the sitelinks search box in
  Google), `Organization`, `ItemList` per row.

### W2 · Search — `/search?q=`

Server-rendered results, grouped **Books · Authors · Publishers · Series** (the
API already has `/catalog/search/all`). Cross-script matching is the party
trick: typing `chemmeen` finds `ചെമ്മീൻ`, and the result says so —
*"ചെമ്മീൻ · matched your spelling 'chemmeen'"*. That is a moment a reader
remembers.

Zero results is a page, not a dead end: nearest matches by fold, the genre/
language hubs, and *"Add this book"* → the app.

- `noindex, follow`. Search pages must never be indexed; they generate infinite
  near-duplicate URLs.
- Progressive enhancement only: the form works with JS disabled (plain `GET`);
  ~3 KB of deferred JS adds typeahead.

### W3 · Book page — `/book/<slug>` — **the flagship**

Answers, in order, above the fold: **what it is** (cover, title, subtitle, author,
year, language, form) · **what people think** (rating out of 5, count,
distribution) · **what it's about** (blurb) · **what to do** (track it in Kitabi,
buy it — `buy_links` is already `[WIRED]` on `Edition`).

Below the fold, in this order because it's the order the questions arrive:

1. **Read it in another language** — the translation module. Original ↔
   translations, each with its *own* rating (per the 5 Jul decision that
   translations keep independent pools) plus the group average. **No competitor
   shows this.** Put it high.
2. **Editions** — every printing: publisher, year, ISBN, pages, format, cover.
   This is the "real bookshelf" feel, on the web.
3. **Reviews** — the public ones, newest first, with the rating histogram.
4. **More by this author** · **More from this publisher** · **In this series**
5. **Readers also shelved** — from co-occurrence in library entries.
6. **The facts table** — ISBN, pages, form, genres, first published, contributors.

- **Links out to:** author(s), translator(s), publisher(s), series, every genre,
  language hub, translation group, ~12 related books. A book page is the densest
  crawl node on the site; that is intentional.
- **JSON-LD:** `Book` (with `workExample` per edition — the existing `_og.js`
  already builds this correctly, reuse it verbatim), `AggregateRating` **only
  when a real rating exists**, `Review` per public review, `BreadcrumbList`,
  `Person` for authors.

> ⚠️ **Never emit `AggregateRating` with a fabricated or zero value.** Google
> issues manual actions for it, and Kitabi's `aggregate_rating` is legitimately
> null on most works today. Omit the field; don't zero it.

### W4 · Author — `/author/<slug>`

Portrait, name + pen name, bio, primary language, the "🔗 on Kitabi" badge when
`linked_user_id` is set (an author who is a verified reader here is a genuinely
novel signal — say so). Then: **Works**, **Translated by them** (`work_translators`
is already modelled), **Translated into other languages**, **Publishers they
work with**, a small **timeline** by `first_publish_year`.

- **JSON-LD:** `Person` + `ItemList` of works, `BreadcrumbList`.
- **Data-quality note:** the seed has duplicate author rows (`Basheer, Vaikom
  Muhammad` *and* `Vokom M. Basheer`). Two rows for one author means two thin
  pages competing with each other — a textbook duplicate-content problem.
  Merging is in the §9 track and is a prerequisite for indexing author pages.

### W5 · Publisher — `/publisher/<slug>`

Logo, primary language, catalogue paged, authors published, languages, a
**decade histogram**. Publisher pages are low-competition and rank easily — for
regional publishers (DC Books, Mathrubhumi, Green Books) Kitabi could plausibly
be the best page on the internet within a month.

### W6 · Genre hub — `/genre/<slug>` · W7 · Language hub — `/language/<slug>`

The hub template, twice. Editorial intro paragraph (150–250 words, **hand-written
per hub — this is what makes a hub not a thin list**), a "start here" row of 6
flagship books, the full paged grid with sort, sub-hubs, and related hubs.

`/language/malayalam` is the single most valuable page on the site. It should
read like the front page of a Malayalam-literature magazine: the canonical
novels, the living writers, the translations in and out, the publishers. Written
once, properly, in English *and* (later) Malayalam under `/ml/`.

- **JSON-LD:** `CollectionPage` + `ItemList`, `BreadcrumbList`.

### W8 · Series · W9 · Translation group · W10 · Editorial list

- **Series** — reading order (`series_number` exists), completion state, one card
  per entry.
- **Translation group** — one page for a book across all its languages, canonical
  to the *original* work. This is the page that wins *"Aadujeevitham English
  translation"*.
- **Editorial list** — `/list/malayalam-novels-to-start-with`. Curated,
  hand-written, evergreen. Lists are the highest-ROI SEO artifact a catalog site
  can produce and cost only writing time. Ten good lists at launch.

### W11 · Reviews · W12 · Reader profile

Reviews paginated with the histogram; `Review` JSON-LD; author line resolves to a
public profile or a stable anonymous placeholder (the API already does exactly
this). Reader profiles render only for opted-in public profiles — the visibility
flags are already wired (rule 16), and the web must honour them or the wiring was
pointless.

---

## 6. Performance — the budget, and how each number is met

Not "make it fast" — a budget, enforced.

| Metric | Budget | Today (est. mobile 4G) |
|---|---|---|
| **TTFB** (cache hit) | **< 100 ms** | 620 ms |
| **TTFB** (cache miss) | < 500 ms | 620 ms + 310 ms client fetch |
| **LCP** | **< 1.2 s** | ~2.8 s |
| **CLS** | **< 0.02** | unmeasured; covers have no dimensions → likely poor |
| **INP** | < 200 ms | n/a |
| HTML, gzipped | **≤ 14 KB** critical | 20.5 KB shell + 1.1 KB JSON later |
| Blocking requests before paint | **0** | 1 CSS (Google Fonts) + 2 handshakes |
| JS required for content | **0 bytes** | 100% of content |

### How each is met

1. **Render on the edge, cache the HTML.** Kills the 310 ms client fetch and the
   620 ms origin wait in one move. (§3)
2. **Self-host the fonts.** `fonts.googleapis.com` costs a DNS lookup, a TLS
   handshake, a CSS round trip, *then* the font fetch from a second origin —
   before a single glyph paints. Self-hosted, subset, preloaded:
   - `Fraunces` variable, latin subset, `woff2` ≈ 34 KB
   - `Inter` variable, latin subset ≈ 26 KB
   - `Noto Sans Malayalam` ≈ 42 KB — loaded **only via `unicode-range`**, so an
     English page never downloads it and a Malayalam page gets it automatically
   - `font-display: swap` + `<link rel=preload>` on the two latin faces
   - Saves an estimated **300–500 ms** to first paint on mobile. There is no
     downside; the licences (SIL OFL) permit self-hosting.
3. **Inline the critical CSS, defer the rest.** One shared `site.css` for
   below-fold, `<style>` for the first screen. The existing pages already inline
   everything — keep that instinct, just split it.
4. **Every image gets explicit `width`/`height`** (or `aspect-ratio: 2/3` on the
   cover frame, which the design system already specifies). This alone takes CLS
   to ~0. Covers below the fold get `loading="lazy" decoding="async"`; the LCP
   cover gets `fetchpriority="high"` and **no** lazy attribute.
5. **Proxy the covers.** Today they hotlink `covers.openlibrary.org` — a third
   party with no SLA to Kitabi, which rate-limits, and which is a second origin
   handshake. Serve `/img/c/<id>` from a Pages Function: fetch once, `cache.put()`
   for 30 days, `immutable`. Backfill the hot ones into the **existing Supabase
   `covers` bucket** (CLAUDE.md is explicit: that bucket, not a new store).
6. **No JS on the critical path.** Search typeahead, the cover lightbox, and the
   rating histogram tooltip are ~4 KB, `defer`, and every one of them degrades to
   a working plain-HTML behaviour.
7. **Preconnect to nothing.** After (2) and (5) there are no third-party origins
   left. That is the point.

**Enforcement:** a Lighthouse CI step in `.github/workflows/` that fails the
build if LCP > 1.2 s or the HTML exceeds budget on three sampled page types. A
budget nobody measures is a wish.

---

## 7. What the API has to grow

| # | Gap | Endpoint | Notes |
|---|---|---|---|
| 1 | **Reviews are auth-gated** | `GET /public/book/{slug}` includes them | `/catalog/works/{id}/reviews` takes `CurrentUser`. Public reviews are already visibility-flagged and already anonymize private profiles — the gate is simply wrong for the web |
| 2 | **No page-shaped payloads** | `/public/book|author|publisher|series|genre|language/{slug}` | The one-payload rule (§3). Thin projections over existing services |
| 3 | **No slug lookup** | ↑ same, keyed by slug | Needs the `slug` column + backfill migration |
| 4 | **No totals on browse** | `X-Total-Count` on `/catalog/browse/works` | Can't render "1–40 of 312" or a last-page link without it. Crawlers need a finite pagination set |
| 5 | **No discovery feeds** | `/public/home` → recently added, highest rated, trending | Trending = library-entry adds in 30 days. Computed in Postgres, cached 1 h. No Redis (rule 8) |
| 6 | **`similar_works` is title-matching only** | `/public/book/{slug}` → `related` | Upgrade to: shared genre + language + author + co-occurrence in library entries |
| 7 | **Sitemaps list everything** | Filter to indexable rows (§8.3) | Currently emits all 1,402 works including empty ones — that teaches Google the site is thin |
| 8 | **No cache purge hook** | `POST /internal/purge` | Fired on Work/Author/Publisher update |

All eight are additive. None changes an endpoint the app depends on — which
matters, because per CLAUDE.md the deploy order is API-first and the app must
tolerate the previous payload shape.

---

## 8. SEO — the strategy, not the checklist

### 8.1 The one that matters

Server-render the content. Everything below is worth a few percent; this is worth
the whole thing.

### 8.2 Structured data

| Page | Types |
|---|---|
| Home | `WebSite` + `SearchAction`, `Organization` |
| Book | `Book`, `workExample` per edition, `AggregateRating` *(only if real)*, `Review`, `BreadcrumbList` |
| Author | `Person`, `ItemList`, `BreadcrumbList` |
| Publisher | `Organization`, `ItemList` |
| Hubs / lists / series | `CollectionPage`, `ItemList`, `BreadcrumbList` |

The existing `_og.js` already builds a correct `Book` object with `workExample`
and omits null fields properly — that code is good and gets lifted into the
shared renderer, not rewritten.

### 8.3 The indexation gate — the counter-intuitive one

**Do not index all 1,402 works.** A large fraction have a romanized-garbage
title (`"Hīro-hīro warasip", arathāta, Kalādhārī, kalādhārīpūjā` is a real row),
no description, no cover, no genre, one edition. Publishing 1,000 pages like that
teaches Google the domain produces thin pages, and it drags down the 200 good
ones. This is the mechanism that has killed more catalog sites than slow servers.

A work page is `index, follow` only if it clears a **content floor**:

> a cover image **or** a description ≥ 120 chars **or** ≥ 1 review **or** ≥ 2
> editions **or** ≥ 1 rating — **and** a title that isn't obvious transliteration
> noise.

Everything else: `noindex, follow` — still crawlable, still linked, still there
for a human with the URL, just not competing. It flips to `index` automatically
the moment a reader adds a cover or a blurb, which turns the app's "Improve this
entry" flow into an SEO engine. Same gate on authors (needs a bio or ≥2 works)
and publishers (≥3 editions).

**The sitemap emits only indexable rows.** That is a change to
`sitemap_service.build_page` — today it emits every non-deleted row.

Expected effect at launch: ~250–400 indexed works instead of 1,402, and they
rank. The number goes up as the catalog improves, which is the correct incentive.

### 8.3b The ISBN address — `/isbn/<isbn>`

An ISBN is the highest-intent query this site can receive: the person typing it
is holding the book. The number was already on every book page, in the editions
table and the "This edition" rail — and that was worth almost nothing, because
body text carries little ranking weight and **no URL, title or canonical carried
the ISBN at all**. There was nothing for that query to rank.

So `/isbn/<isbn>` is an addressable URL per edition that **301s to the canonical
`/book/<slug>`**, funnelling its authority into the real page rather than
competing with it. It is also the shape other catalogues and library systems
naturally link to us with. It stays out of the sitemap deliberately — rule 1 of
`sitemap.xml` is *list final URLs, never redirects*.

Alongside it, the book page's **meta description** now ends with `· ISBN <n>`
for the primary edition, with the blurb clamped to make room. The `<title>` was
considered and rejected: it belongs to the title and author, and a number there
would cost every reader-facing query to win one machine-facing one.

**Both ISBN forms resolve.** The same book is `8126403454` on a 2005 printing and
`9788126403455` on a 2019 one, and the catalogue stores whichever form a
contributor typed, a scanner read, or OpenLibrary answered with. Lookups expand
to every equivalent form (`services/isbn.variants`), new writes canonicalise to
ISBN-13 (`NormalizedIsbn`), and migration `000041` backfilled the rows that
predate both. All three are needed: normalising writes does nothing for stored
rows, and a backfill can never be assumed to have reached every one.

`GET /public/isbn/{isbn}` is **DB-only and never falls through to OpenLibrary** —
it is the most public endpoint on the site, and a crawler walking guessed ISBNs
must not be able to spend a third party's quota on our behalf (§11).

### 8.4 Crawl architecture

- Home links every hub. Hubs link every book. No indexable page is >3 clicks deep.
- Pagination: each page self-canonical with a unique title
  (*"Malayalam novels — page 2 of 14"*); never canonicalize page 2 to page 1
  (it de-indexes the deep catalog).
- `/search` and `/browse?…` are `noindex, follow` and `Disallow`ed for
  aggressive crawlers in `robots.txt`, but stay linked so equity flows.
- Sitemaps extend beyond works/authors/publishers to **series, genres,
  languages, lists, translation groups**, with `<image:image>` for covers.
- `hreflang` reserved for `/ml/` when the Malayalam UI lands. Ship the
  `<link rel="alternate">` scaffolding now so it isn't a retrofit.

### 8.5 What earns links

Rankings need links, and a catalog page earns none. The three things here that do:

1. **The translation graph** — *"every Malayalam novel available in English"* is
   a page journalists and r/books link to. Nobody else can build it.
2. **Editorial lists** — ten hand-written, genuinely-useful lists.
3. **Author pages for living regional writers** — better than their Wikipedia
   stubs, and they and their publishers will link to them.

---

## 9. The catalog-quality track — the actual moat

A perfect site over a bad catalog ranks for nothing. Running in parallel with the
build, not after it:

1. **Merge duplicate authors.** `Basheer, Vaikom Muhammad` / `Vokom M. Basheer`
   are one person. Fuzzy-match on `title_fold`-style folding of names, propose
   merges, admin-approve in the existing console. **Prerequisite for indexing
   author pages at all.**
2. **Fix the titles.** ~30% of seeded works carry OpenLibrary transliteration
   noise. Native title + a clean romanization; `title_translit`/`title_fold`
   already exist to hold it.
3. **Attach genres.** `browse/genres` returns `[]`. Classify the seed set against
   a small closed vocabulary (~40 genres) — LLM-assisted with human review, using
   the Anthropic client already in the API. Without this there are no genre hubs.
4. **Cover coverage.** Missing covers → typeset covers (the design system already
   specifies them, and they're attractive) so no page has a hole.
5. **Descriptions for the top 300.** 120–200 words each. This is the single
   highest-leverage manual task on the list: it flips 300 works past the content
   floor and gives every page a real meta description.
6. **Editorial hub intros** — 14 language hubs + ~40 genre hubs.

Items 3, 5 and 6 are the difference between a database with a website and a
publication. Budget them as writing work, not engineering work.

---

## 10. Phasing

Each phase ships something live and measurable.

| Phase | Scope | Done when |
|---|---|---|
| **W0 · Foundations** (~1 wk) | `slug` migration + backfill; `/public/*` read layer; public reviews; `X-Total-Count`; self-hosted fonts; cover proxy | `curl /public/book/chemmeen` returns a whole page's data in one call, < 200 ms |
| **W1 · SSR the three pages we have** (~1 wk) | `functions/_lib/` renderer; `/book`, `/author`, `/publisher` server-rendered; `/b/:uuid` 301s; AASA/assetlinks updated **first**; edge cache | A JS-disabled browser sees the full book page. TTFB < 100 ms warm |
| **W2 · Front door** (~1 wk) | `/`, `/search`, `/browse`; home feeds endpoint; search grouping + cross-script match line | Search for `chemmeen` returns `ചെമ്മീൻ` in server HTML |
| **W3 · Hubs** (~1 wk) | `/genre`, `/language`, `/language/x/<form>`, `/series`, `/translations` + editorial intros | Every indexable page ≤3 clicks from home |
| **W4 · Indexation** (~3 d) | Content floor; sitemap filtering; extended sitemaps; JSON-LD everywhere; Search Console + Bing; Lighthouse CI | Rich Results test passes on all types; sitemap emits only gated rows |
| **W5 · Depth** (~2 wk, parallel) | Author merge; genre classification; 300 descriptions; 10 editorial lists; reader profiles | `browse/genres` non-empty; ≥400 works past the floor |
| **W6 · Malayalam UI** (`[LATER]`) | `/ml/` + `hreflang` | — |

W0+W1 is the whole "it works and it's fast" story and is ~2 weeks. W5 is what
makes it rank, and it never really finishes.

---

## 11. Protecting the API

Publishing the catalogue means publishing the API surface behind it, so this
needs stating plainly: **you cannot stop a non-browser client from calling a
public endpoint.** Anything the browser or app sends, curl can send. Any key
shipped to a client is public. CORS is a *browser* policy protecting your users'
sessions from other sites — curl ignores it entirely. "Block others" is not an
achievable goal, and chasing it costs effort that belongs elsewhere.

Two things follow.

**Edge SSR removes the browser as an API caller.** Today `/b/:id` fetches
`api.kitabi.in` from the browser, which is exactly why the network inspector
shows everything. After W1 only the Pages Function talks to the API,
server-to-server, and the inspector shows one HTML document. That also makes an
edge↔origin shared secret a *real* secret, because it never leaves a server —
so `/public/*` can reject anything that isn't the edge.

**The controls are rate and cost, not secrecy.** Ranked by what abuse actually
costs, as measured 4 Aug 2026:

| Surface | Then | Now |
|---|---|---|
| **LLM endpoints** (`/catalog/cover-extract`, `/recommendations`) — the only two where a request costs money | Auth'd, but **no quota, no cap, no breaker anywhere in the API** | ✅ **Done** — `llm_usage` + `services/llm_quota.py`: per-reader daily quota + global daily circuit breaker (migration `000037`) |
| **`GET /catalog/isbn/{isbn}`** — public, proxies OpenLibrary, writes to our DB | Fully public: an anonymous caller could get Kitabi rate-limited by a third party and fill the catalog with junk | ✅ **Done** — signed-in only; needed no app change (the Dio interceptor already attaches the token) |
| Catalogue scraping — 14 public GETs, `browse/works?limit=100` = 82 KB in 0.56 s | No limits | **Left open on purpose** — crawling this is the point. Bounded later by `Cache-Control` (repeat reads never reach Railway), not by blocking |
| A single IP hammering the API into an outage (pool is `10 + 10`) | No limits | 📝 **Written, not applied** — `infra/cloudflare/rate_limits.py`. Free plan allows **one** rate limiting rule, IP-only, short window: a **burst shield, not an anti-scraping control**. Spent on availability, since spend is already bounded by `llm_quota`. Blocked on a Zone→WAF token (the Actions one is Pages-scoped and must not be widened) |
| CORS | `allow_methods=["*"]`, `allow_credentials=True`, `Authorization` allowed | ✅ **Done** — `["GET"]`, credentials off, `Accept` only. The public web is read-only and unauthenticated (rule 2 below), so this now matches it exactly |
| Catalog writes | Auth'd + the revision-approval queue | Adequate; rate-limit at the edge |
| Personal data | JWT + RLS deny-by-default + `user_id` scoping | Correct already |

The reframe worth keeping: **an uncapped LLM budget can hurt you; a fully
crawled catalogue is the plan working.**

⚠️ **One ordering constraint for W1.** Today the browser calls `api.kitabi.in`
directly, so a per-IP rate limit means "per reader". After edge SSR it does not:
most API traffic becomes the Pages Function calling the API server-side, so a
per-IP ceiling can throttle *Cloudflare itself* and take the public site down
under exactly the traffic spike it exists to survive. The edge→origin shared
secret must land with a `skip` rule ordered ahead of the limiter **before** W1
ships, not after.

## 12. Rules this must obey

Inherited, non-negotiable:

1. **No new service, no new bill, no new credential** (rule 8). Cloudflare Pages
   Functions, the existing FastAPI, the existing Supabase `covers` bucket.
2. **The web is read-only.** No public write path, no unauthenticated mutation.
   Every action a visitor might want (rate, review, shelve, lend) is a door into
   the app. This keeps RLS deny-by-default (rule 11) intact and the attack
   surface at zero.
3. **Visibility flags are honoured** (rule 16). A private profile, a private
   review, a private library never appears — the API already resolves this
   correctly; the web must not route around it.
4. **Work vs Edition stays split** (rule 17). Ratings/reviews/translations on the
   Work; cover/ISBN/pages on the Edition. The URL scheme reflects it:
   `/book/<slug>` is a Work, editions are a section of it, never their own pages.
5. **Reading Room theme** ([screen-design.md](screen-design.md)) — paper, ink,
   oxblood, gold; Fraunces + Inter; covers in one frame; quiet, literary, no
   feed. The site should look like the app's older sibling, not a different
   product.
6. **Landing page stays dependency-free** — no build step, no framework
   (CLAUDE.md). This plan holds that line; §3 says what would break it.
7. **`STATUS.md` updated in the same commit** as anything that changes
   architecture, deployment or feature state.

---

## 13. Deliberately not in v1

- User-generated content on the web (write requires the app).
- Accounts / sign-in on the web.
- A recommendation feed (the LLM hook stays quiet, per the product positioning).
- Comments, forums, follows.
- AMP (dead), a PWA shell, client-side routing.
- Ads or affiliate links beyond the already-`[WIRED]` `buy_links`.

## 14. Open decisions for the owner

1. **Slug column vs. hash-suffixed UUID.** Recommendation: slug column (§4.1).
   Costs one migration; buys clean URLs permanently.
2. **Content floor thresholds** (§8.3) — the proposed floor indexes ~250–400 of
   1,402 works at launch. Comfortable, or too aggressive?
3. **Genre vocabulary** — who owns the ~40-genre closed list, and is
   LLM-assisted classification with human review acceptable for the seed set?
4. **Editorial writing capacity** — §9 items 5 and 6 are ~40 hours of writing.
   Solo, hired, or LLM-drafted-then-edited?
5. **`/reader/<username>` at launch or later** — public profiles are wired but
   there are few readers yet; empty profile pages are thin pages.
6. **Buy links** — `buy_links` is `[WIRED]` and empty. Affiliate programmes are a
   revenue path but also a disclosure obligation (and a bill-adjacent
   relationship). In or out for v1?
