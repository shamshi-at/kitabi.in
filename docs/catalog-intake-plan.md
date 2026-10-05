# Daily catalogue intake — plan

**Status:** proposed, 9 Sep 2026. Supersedes the hand-run `etl/` seed as the way
new catalogue rows arrive. Read [feature-map.md](../feature-map.md) rules 17–18
and CLAUDE.md's non-negotiables first; this plan changes *where books come from*,
not what a Work or an Edition is.

**The ask (owner, 9 Sep 2026):** load new books automatically every day; each one
a complete entry — title, author, publisher, images; no more records that need
adjusting afterwards; every record carrying a valid ISBN; Malayalam and
Indian-English first; budget available for a paid API if one is needed.

---

## 1. What is actually broken

Not the loader. `04_load.sql` is idempotent, `03_transform.py` fills the
translit columns, `06`/`08`/`09`/`10` all work. The problem is upstream of all
of them: **for Indic languages, OpenLibrary's records are US research-library
MARC** — Library of Congress South Asia Cooperative Acquisitions Program
transcriptions, written under cataloguing rules for a card catalogue, not for a
reader.

That is the source of every "adjustment record" in `etl/`:

| Script | Exists because |
|---|---|
| `09_marc_cleanup.py` (16 KB) | terminal periods, NFD titles, dangling `=`/`/`, inverted author names |
| `10_title_restore.py` (19 KB) | ALA-LC romanization — `Ardhi rate azadi` where the book says આઝાદી અડધી રાતે |
| `08_genre_classify.py` (15 KB) | OL subjects too noisy to seed, so genres are inferred afterwards |
| `06_backfill_script.py` | `COPY` bypasses the ORM, so search keys are recomputed afterwards |

Two of those (`09`, `10`) are pure repair work, and `10` needs an LLM *and a
human* per book because "is this a native title or a transliterated English one"
is a per-book judgement. **A pipeline that needs a human per row is not a
pipeline that can run every day.** The fix is to stop importing rows that need
repair, which means changing the source — not adding a fifth cleanup pass.

### Measured, 9 Sep 2026

Completeness = valid ISBN (checksum, via `api/app/services/isbn.py`) **and**
cover **and** author **and** publisher.

| Source | Sample | Valid ISBN | Author | Cover | Complete |
|---|---:|---:|---:|---:|---:|
| **OpenLibrary** — `language:eng subject:india`, readinglog-ranked | 60 | 100% | 100% | 98% | **98.3%** |
| **OpenLibrary** — a *publisher* seed (`Aleph Book Company`) | 40 | 100% | 100% | 72% | **~72%** |
| **Mathrubhumi Books** — product pages | 40 | 87.5% (0 invalid, 12.5% absent) | 100% | 100% | ~88% |
| **LookaBook** — product pages | 32 | 15.6% (0 invalid, 84.4% absent) | 100% | 100% | ~16% |
| **LookaBook** — Store API feed alone | 100 | 25% | 68% | 100% | ~25% |
| OpenLibrary — Indic seed already in the catalogue | 1,428 | — | 30 inverted names | — | 272 titles with MARC periods, 354 NFD |

**The finding that decides the budget question: money does not buy the broken
half.** OpenLibrary is already at 98.3% for Indian English — a paid API cannot
meaningfully beat that. And no paid aggregator (ISBNdb, Bowker, Nielsen) holds
better Malayalam data than the Malayalam publishers' own storefronts, because
the storefronts *are* the primary source. ISBNdb at $14.99–$299.99/mo
([pricing](https://isbndb.com/isbn-database), 1/3/5 calls per second by tier,
**billed per result returned, not per call**) would be paying for the half that
already works.

**Recommendation: spend nothing yet.** Revisit only if (a) Hindi/Tamil/Bengali
expansion finds no equivalent publisher feeds, or (b) we need author biographies
and subject headings at scale.

### Measured again, 3 Oct 2026 — new releases, and ISBNdb revisited

The owner's requirement sharpened: *new releases must be in the catalogue*. Two
measurements change what the sources above are good for.

**OpenLibrary is a backlist source only.** Editions it lists by publish year:

| Publisher | 2024 | 2025 | 2026 |
|---|---:|---:|---:|
| Penguin Random House India | 2 | 3 | 0 |
| HarperCollins India | 0 | 7 | 0 |
| Rupa Publications | 9 | 4 | 1 |
| Westland | 38 | 10 | 8 |
| Juggernaut | 1 | 16 | 4 |
| Mathrubhumi Books | 0 | 0 | 0 |

So the 98.3% figure above is true of the *older head* and says nothing about
this year's books. New releases have to come from the publishers' own sites.

**Many of those sites expose an open, newest-first product feed** (WooCommerce
Store API or Shopify `products.json`), which means one generic adapter per
storefront type rather than one per publisher. Newest 40 products of each:

| Publisher | Storefront | Titles | Valid ISBN in feed | Cover |
|---|---|---:|---:|---:|
| HarperCollins India | Woo | 5,178 | 40/40 | 35/40 |
| Mathrubhumi Books | Woo | 3,764 | 0/40 (on the product page) | 40/40 |
| Olive Publications (Malayalam) | Woo | 1,510 | 1/40 (product page) | 40/40 |
| Speaking Tiger | Woo | 999 | 0/40 (product page) | 40/40 |
| Roli Books | Woo | 512 | 36/40 | 40/40 |
| Juggernaut | Shopify | — | 0/40 (product page) | 40/40 |
| Seagull Books | Shopify | — | 40/40 | 40/40 |

Niyogi (112) and Hind Yugm (19, Hindi) are open too. **No open feed or sitemap
found:** Rupa, Hachette India, Pan Macmillan India, DC Books, Green Books,
Manjul. Penguin India and Aleph have sitemaps (Penguin's with `lastmod`), so a
page-by-page adapter is possible there.

**ISBNdb, looked at properly** (API spec v2.8.0 and its terms, at the owner's
request). Still no for seeding, for three reasons the September note did not
have: its terms let a subscriber store data only "with a current subscription
(data must be deleted if the subscription expires or is cancelled)", which
makes every seeded row a rental; the API has no browse-by-language endpoint and
its updates feed is Premium-only, unfiltered and ISBN-only; and its Malayalam
records are library-romanized (`Ātrēyakaṃ nōval` by `Ār Rājaśr̲ī`) — of 7
recent Mathrubhumi ISBNs it held 3, OpenLibrary 0. Two uses remain worth a
free-trial measurement: a second fallback for ISBN scans OpenLibrary misses,
and `/publisher/{name}?publishedFrom=` for the closed houses above. Scan misses
are not recorded today, so log them first — without that there is no
denominator to judge a trial against.

---

## 2. Sources

### Malayalam — the publishers' own storefronts

Both run WooCommerce with the **Store API open and unauthenticated**, and both
`robots.txt` permit crawling product pages:

| Store | Titles | Publishers | Valid ISBN (pages) | Gives |
|---|---:|---|---:|---|
| `www.mbibooks.com` (Mathrubhumi Books) | 3,726 | **one** — their own imprint (28/30 sampled, 2 blank) | **87.5%** | front **and back** covers, category, price; page HTML adds ISBN-13, author, publisher, page count, edition |
| `www.lookabook.in` (aggregator) | 3,354 Malayalam | **many** — DC Books 550, Mathrubhumi 44, Green Books 20, Insight 8, … | **15.6%** | covers, category, author; a `publication` and an author taxonomy |

**These two are not interchangeable, and neither is sufficient alone** — measured
9–11 Sep 2026:

- **Mathrubhumi is deep and clean but narrow.** It is a single publisher's own
  shop, not a Malayalam bookstore. Sampling `og:title` across the catalogue
  returned "Mathrubhumi Books" 28 times out of 30. DC Books — the largest
  Malayalam publisher, ~6,500 titles — is **not in it**, and neither are Current,
  Poorna, Olive, Chintha, Manorama or NBS.
- **LookaBook has the breadth and fails the ISBN gate.** Its product *pages*
  carry a valid ISBN on only 15.6% (n=32; 0 invalid, 84.4% simply absent). So it
  cannot be used to complete Mathrubhumi's ISBN gaps — it is worse on exactly
  that field. It adds publisher breadth for rows that would then be rejected.

**Realistic Malayalam yield today: ~3,300 books** (87.5% of Mathrubhumi's 3,726),
from one publisher — not the ~5,000 across many that a first read of the two row
counts suggests. For scale, the whole catalogue today is ~1,428 works and 772
covers, so this is still a 3× catalogue in the wedge language. But **Malayalam
breadth is blocked on DC Books**, and that is a conversation, not a crawler
(see below).

Two things to know before building against them:

- **The Store API is discovery, not the record.** Mathrubhumi's feed carries
  0% ISBNs; the ISBN is on the product page (`ISBN 13: …`), and the author and
  publisher come out of `og:title`, which is reliably `Title | Author |
  Publisher`. So intake is two requests per book, not one. Budget for that.
- **Titles are romanized here too** (0–1% native script in the feed). The native
  title is on the cover art and in the description. This does *not* reintroduce
  the `10_title_restore` problem — a Mathrubhumi romanization is the publisher's
  own house spelling of their own book, which is what Malayalam readers search
  and what the book is sold as, not a library's ALA-LC transcription of it. But
  it does mean **native-script titles remain a separate, later job**, and the
  plan should not pretend otherwise. `services/malayalam_script` is the tool;
  the honest position is that a romanized publisher title is a *good* record,
  and a native-script one is a better one.

### Indian English — OpenLibrary, already integrated

Free, no key, `services/openlibrary_client.py` already wraps it.

**Amended 11 Sep 2026, after building P1 and running it for real.** The 98.3%
figure above is true and was measured on the wrong population: it ranks by
reading-log count, which is the globally popular *head*, and covers there are
near-universal. The adapter that shipped walks curated **publisher** seeds —
a house's whole list, backlist included — and there the complete rate is about
**72%**, the entire gap being missing cover art (100% still carry a valid ISBN,
an author and a publisher). A first live run staged 47 candidates and held 24
of them for a cover.

That is not a problem with the source or the gate; it is the staging table
doing its job, and those 24 are exactly what P2 exists to resolve. But it does
mean **the honest planning number for English intake is ~70%, not ~98%** —
worth knowing before sizing how fast the catalogue fills.

What needs work is **selection**, not extraction: `language:eng subject:india`
sorted by reading-log returns Life of Pi and Siddhartha alongside The God of
Small Things, and one Devanagari कामसूत्र from a Spanish publisher. Selection
should be driven by curated seeds, not one query:

- publisher lists — Penguin India, HarperCollins India, Rupa, Westland, Aleph,
  Juggernaut, Bloomsbury India, Speaking Tiger, Context, Eka
- prize and bestseller lists — JCB Prize, Crossword, Sahitya Akademi (English),
  Amazon.in / Crossword weekly charts
- author expansion — every author already in the catalogue, walked for titles we
  do not have

A script/language gate rejects anything not actually in Latin script, and a
`subject:india`-only row from a foreign publisher is a candidate for review, not
an automatic accept.

### Not chosen, and why

- **ISBNdb** ($14.99+/mo) — buys the half that already works; see above.
- **Google Books** — the keyless quota is exhausted in practice (verified: the
  shared anonymous project returns 429), so it needs our own key. A free key is
  still a credential (rule 8) for data OpenLibrary already gives us.
- **Nielsen BookData India** — enterprise sales contact, no self-serve pricing;
  the right call *if* we ever want point-of-sale bestseller data, not for
  metadata.
- **dcbookstore.com** — a React SPA with no discoverable JSON API; every path,
  including `/api/books`, returns the HTML shell. **This is now on the critical
  path, not a footnote**: DC Books is the breadth gap. Two ways in, in order —
  ask them (below), or find the XHR endpoints the SPA itself calls, which is
  half an hour with the browser network panel.

### The one that is now critical: ask DC Books

`editions.buy_links` is already `[WIRED]` in the model and dormant. Mathrubhumi
and DC Books have an obvious interest in a reading app that sends readers to
their storefront. **A metadata feed in exchange for buy links is a fair trade
and turns a scrape into a partnership** — and it also settles the cover-copyright
question in §4 far better than any technical measure.

This was a nice-to-have when the plan assumed two usable Malayalam feeds. With
LookaBook failing the ISBN gate on 84% of rows, **DC Books is the difference
between "Malayalam means one publisher" and "Malayalam means Malayalam"** — 550
DC titles are visible on LookaBook alone, against a DC list of ~6,500. It is a
founder task and it should start before the code does.

---

## 3. Architecture

The current seed is a set of scripts a human runs from a laptop with a 9 GB
download. "Every day, automatically" means it moves into the API as a scheduled
job, alongside `backfill_covers` and `merge_exact`.

```
  discovery (per-source adapters, paged, resumable)
        │  writes candidates, never touches the catalogue
        ▼
  catalog_intake  ── the staging table (new)
        │  raw payload + source + state + first_seen_at
        ▼
  enrichment      ── second request per candidate; cross-source fill
        │
        ▼
  ┌─────────────────────────────────────────┐
  │  THE COMPLETENESS GATE                  │   fails → stays `incomplete`,
  │  valid ISBN ∧ title ∧ author ∧          │   retried when another source
  │  publisher ∧ cover                      │   can fill the hole
  └─────────────────────────────────────────┘
        │ passes
        ▼
  promotion  ── through the ORM/service layer, N per day, advisory-locked
        │
        ▼
  works · editions · authors · publishers      (+ /moderation/incoming audit)
```

### The staging table is the point

`catalog_intake` gives the pipeline a **memory**, which is what makes "what is
new today" answerable and re-runs idempotent. One row per candidate, keyed by
`(source, source_key)`, holding the raw payload, a state
(`discovered → enriched → complete → promoted | incomplete | rejected`), the
resolved ISBN, and `first_seen_at` / `promoted_at`. It is *not* a syncable table
(rule 10 does not apply — no `user_id`), and it is RLS-denied like everything
else (rule 11).

It buys three things the current pipeline cannot do: a candidate that fails the
gate today can be completed by a different source next week without re-crawling;
the daily budget is a `LIMIT` on a query rather than a crawl parameter; and the
gate's rejections are *inspectable* — "why is this book not in the catalogue" has
an answer.

### The completeness gate — "no more adjustment records", mechanically

**A record is complete or it is not in the database.** Not "mostly complete and
we will fix it later" — later is what produced `09` and `10`. Concretely:

1. **Valid ISBN** — `services/isbn.clean` then `canonical`; checksum enforced,
   not just shape. Measured: 87.5% of Mathrubhumi pages pass, 0% fail the
   checksum, 12.5% simply have no ISBN. The one bad number found in probing
   (`9189376880780`, a 918 prefix that cannot exist) is exactly what the gate is
   for.
2. **Uniqueness before insert** — `editions.isbn` is `UNIQUE`; existence must be
   checked against `isbn.variants()`, because the same book is ISBN-10 on one
   printing and ISBN-13 on another.
3. **Title, ≥1 author, publisher, cover** all present.
4. **Publisher resolved through `merge_service.canonical`** — the 4 Sep 2026
   lesson. Without it the intake re-creates "ഡി സി ബുക്സ്" every night beside the
   "DC Books" a human already merged it into.
5. **Promotion goes through the service layer, not `COPY`.** `translit_hooks`
   must fire so `title_translit` / `title_fold` are populated, and `ensure_slug`
   must run at promotion. Bypassing the ORM is precisely why `06_backfill_script`
   exists; a daily job must not recreate that debt.
6. **Genre/form at promotion, or not at all** — extend `08_genre_classify`'s
   prompt into the pipeline, metered through `services/llm_quota.consume` with
   its own feature constant (CLAUDE.md: any endpoint whose request costs money is
   metered before it ships), and allowed to answer *unknown*. A blank genre is
   not an incomplete record.

Rows that fail sit in `catalog_intake` as `incomplete` with the failing
predicate recorded. That queue is the honest measure of coverage, and it is where
a second source (or a paid one, if we ever buy one) gets pointed.

**Tightened 3 Oct 2026 — a real book number, and the name of one book.**
Owner: *"I don't want any books which has no valid ISBN or name doesn't seem
like a valid book."* The gate already required a checksum-valid ISBN and
refused MARC headings; measured against nine storefront feeds and the live
OpenLibrary adapter, that still let through things that are not books or are
not named like one. Now also refused:

- **Numbers that are not book numbers:** `979-0` (the ISMN range — sheet
  music) and placeholders that pass the checksum (`978-1-234-56789-7`, a body
  of one repeated digit).
- **Names that are not titles** (`title_not_a_title`): punctuation only,
  filler words (`untitled`, `test`), an ISBN or stock number in the title
  column, markup, a URL, the publisher's own name — and what a shop adds to a
  title: a format or edition label (`[Paperback]`, `(Tamil Edition)`), a
  tagline after a pipe, a search-engine listing, display capitals.
- **Products that are not one book** (`title_not_a_book`): combos, box sets,
  `(Set)`, "3 Book Pack", gift cards, calendars and dated diaries.

On ~2,750 real storefront titles the *not-a-book* rules refused 18, every one
a true non-book. The *shop-styling* rules refuse far more, and that is the
point of putting them here: **58 of 300 Mathrubhumi titles and 86 of 300 Olive
titles pass as their feeds print them**, because both list in capitals. The
gate refuses; the adapter (P3) is what must supply a properly written title,
and a re-crawl re-screens the row. On the live OpenLibrary adapter the same
rules refused 10 of 331 — `Annihilation of Caste [Paperback] Ambedkar, B. R.`,
`FIRE AND BLOOD` — rows the old gate would have published.

This applies to what the intake creates. A reader adding their own book is
unchanged: an ISBN stays optional there, because older regional books
genuinely have none.

### "Added by default"

Per the ask, a complete record is **published live**, not held for review. That
matches how the catalogue already works — readers' contributions are public the
moment they are created, and `/moderation/incoming` is a review-by-default audit
queue, not a gate. Intake rows appear there like any other addition, tagged with
their source.

### Daily rhythm

- **Discovery** — weekly per source (a storefront does not add 3,000 books a
  day); plus a daily pass over the store's newest page and sitemap `lastmod`, so
  genuinely new releases arrive within a day.
- **Enrichment + promotion** — daily, `N` books, advisory-locked
  (`LOCK_CATALOG_INTAKE`), same shape as `backfill_covers`: small batch, paced,
  bails out after consecutive failures.
- **Backlog first, then new.** ~5,000 Malayalam candidates at 50/day is 100 days
  of "new books every day" before the queue even reaches steady state. Malayalam
  publishing runs a few thousand titles a year across all houses, so the
  long-run rate is realistically 10–30/day — which is a healthy "new in
  catalogue" feed, and worth knowing now rather than being surprised by.

---

## 4. Covers — the one real cost, and a decision to make

This needs an owner call before any code, because the numbers do not fit.

- Mathrubhumi cover art measured at **~600 KB each**.
- 5,000 books × 600 KB = **~3 GB**. The Supabase free tier gives **1 GB of
  storage**, and the `covers` bucket already holds reader uploads, author
  portraits, publisher logos and campaign artwork.
- Egress is the tighter constraint and we have already been bitten: **5.75 GB of
  5 GB used, 7 Sep 2026**.
- The edge proxy `landing-page/functions/img/c.js` allowlists exactly two hosts
  (`covers.openlibrary.org`, `*.supabase.co`) — and its allowlist and the app's
  `image_proxy.dart` **must agree**. Any new cover origin is a two-file change,
  by design.

Three options:

| | Storage | Egress | Ownership | Rule 8 |
|---|---|---|---|---|
| **A. Hotlink + edge cache** — add `mbibooks.com` to both allowlists | 0 | 0 from us | none — "a cache is not ownership" | clean |
| **B. Resize, then Supabase bucket** — Pillow, longest edge 800px, JPEG q80 → ~50 KB | ~250 MB | metered, but the app already proxies through the edge | full | adds Pillow (a dependency, not a bill or credential) |
| **C. Cloudflare R2** — 10 GB free, **zero egress fees** | fits easily | free | full | R2 already exists as the backup target, but CLAUDE.md explicitly says covers go in the Supabase bucket, "never a second store" |

**Decided 3 Oct 2026: C — Cloudflare R2.** The owner chose it once §1's source
list grew: the open storefront feeds measured that day (below) put the backlog
near 12,000 titles, past the ~10,000 line this section already named as where C
becomes the honest answer. Built as `services/cover_ingest` + `r2_client`; the
single-store line in CLAUDE.md now records the exception. Measured on real
covers, a normalised cover is **~80 KB**, not ~50 (Mathrubhumi: 348 KB at
1059×1654 → 79 KB at 512×800), so budget ~1 GB for 12,000 — a tenth of R2's
free 10 GB.

One thing this changes from the table above: **no allowlist edit is needed.**
The bucket is served from its own custom domain (`covers.kitabi.in`), which is
already our origin on Cloudflare's edge with no egress meter, so the web and the
app fetch it directly rather than through `/img/c`.

**Owner setup (once), in the Cloudflare dashboard and Railway:**

1. R2 → create a bucket, e.g. `kitabi-covers`. A new bucket — not the backup one,
   which must stay private.
2. Bucket → Settings → Custom Domains → connect `covers.kitabi.in`.
3. R2 → Manage API Tokens → create a token with **Object Read & Write**, scoped
   to that bucket only. Note the Access Key ID and Secret Access Key.
4. Railway → `kitabi-api` → Variables: `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`,
   `R2_SECRET_ACCESS_KEY`, `R2_COVERS_BUCKET=kitabi-covers`,
   `R2_COVERS_PUBLIC_URL=https://covers.kitabi.in`.

Until all five are set the pipeline is dormant: the intake promotes only covers
the edge proxy already serves and holds the rest.

**Done and verified, 3 Oct 2026.** To check it again at any time — it prints
whether each setting is present and well-formed (never its value), uploads one
real cover through the same code the job uses, and fetches it back from the
public domain:

```bash
cd api && railway run .venv/bin/python scripts/check_cover_storage.py
```

A variable added in the Railway dashboard is only *staged* until **Deploy** is
pressed; until then `railway run` reports all five as missing.

*The original recommendation, kept for the reasoning:* **B.** It keeps the single-store rule CLAUDE.md asks for, keeps
ownership (which was a deliberate decision, not an accident), and 250 MB is
survivable. Resizing is required either way — storing 600 KB covers unresized is
not a real option at any destination. **C is the honest answer if Malayalam
intake later grows past ~10,000 titles**, and CLAUDE.md's line should then be
revisited on the numbers rather than treated as settled; it was written when the
catalogue held 772 covers.

**Also flag, not an engineering question:** cover images are copyrighted, and
copying them into our own bucket is a stronger act than hotlinking. Metadata
(title, author, ISBN, publisher) is largely factual and not the concern. The
partnership conversation in §2 is the clean resolution and another reason to
start it early.

---

## 5. Phasing

Each phase ends with something running, and nothing is built on a source that
has not been proved first.

**P1 — Intake spine (no new source).** ✅ **Done, 11 Sep 2026.**
`catalog_intake` + migration 000053 (RLS on, zero policies); `intake_gate` pure
and 53-test-covered; `intake_service` promoting through
`catalog_service.create_work_with_edition`; `intake_openlibrary`;
`jobs/catalog_intake` on a 02:30 UTC cron under an advisory lock, **dormant
unless `CATALOG_INTAKE_ENABLED=1`**. Verified end-to-end against live
OpenLibrary into the dev database: 47 discovered, **0 catalogue rows written by
discovery**, 10 promoted with valid ISBNs, real publishers, slugs and covers.

**Seeing a night before allowing one:** `api/scripts/preview_intake.py` runs
the real adapters against the real sources, screens through the real gate and
asks the real database which books it already holds — then prints exactly what
tonight would create. It writes nothing (the session is opened
`postgresql_readonly`, verified to have Postgres itself refuse an INSERT) and
has no `--apply`, because promoting is the job's business and its switch is the
Dockerfile flag. Point it at **production**: a preview against an empty dev
database cannot tell you which books you already have, and that is most of what
separates a useful night from a wasted one.

```bash
DATABASE_URL="$(grep '^DATABASE_URL=' api/.env | cut -d= -f2-)" \
  api/.venv/bin/python api/scripts/preview_intake.py
```

Three defects the live run found that mocked tests could not, all now pinned by
regression tests: the work-level cover fallback was dead code (`cover_i` was
never among the fields requested); `publisher:"Juggernaut Books"` matches an
*Australian* press and shelved a YA novel under an Indian-English seed; and OL
returns names like `Juggernaut Books Pty,`. A fourth was in shared code —
`marc_cleanup.clean_work` needed two passes on `"Mukajjiya kanasugaḷu" /`,
because stripping the dangling ` /` re-exposes quotes `_unquote` has already
gone past. It iterates to a fixed point now, which is what a door-time gate
depends on and what the etl README already warned about.

**P2 — Cover pipeline.** 🟡 **Built 3 Oct 2026; live once the owner's R2 setup
(§4) is done.** Fetch → normalise (800px JPEG) → store in R2, run by `promote`
before the Work exists, so no book is ever live with a cover that does not load.
*Done when:* a promoted book's cover is served from `covers.kitabi.in`.

**P3 — Storefront adapters.** 🟡 **Built 3 Oct 2026; runs when the intake is
switched on.** Widened from "the Malayalam adapter" once OpenLibrary turned out
to hold no new releases at all (§1): `services/intake_storefront` reads a
publisher's WooCommerce Store API newest-first, and three shops are configured —
**HarperCollins India** (5,178 titles), **Mathrubhumi** (3,764) and **Speaking
Tiger** (999).

- **Two passes.** `discover` stages every product on a feed page (one request
  per hundred books); `enrich` reads the product page of rows the gate is
  holding, once each, for what the feed lacks. What the page said is kept
  apart from the feed's fields and laid back over them at every staging, so
  the nightly re-crawl cannot undo it. No cursor table: every product is
  staged, so a shop's row count *is* how deep its backlist crawl has got.
- **New releases first.** A row first seen on a shop's newest page is marked
  and promoted ahead of the backlog; otherwise this week's book waits behind
  months of backlist at the daily limit.
- **Mathrubhumi's pages carry the title in Malayalam.** The feed has
  `SPINOSAURUS`; the page's `<h1>` has സ്പൈനോസോറസ്. 22 of 24 newest books came
  out complete with a native title, author, ISBN, page count and both covers.
- **A second printing joins its book.** The hardback and paperback are two
  products; `promote` attaches the second as an Edition when title, language
  and an author match (a shortened name — `Scott Fitzgerald` — counts). The
  same title by a *different* author is held for a person rather than guessed.
  Against production this found three real second printings in one preview
  (`400 Days`, `The White Tiger`, `The Palace of Illusions`) that would
  otherwise have been duplicate Works.
- **An author we already have keeps the name we have them by.** A shop's
  `Shakespeare William` or `Scott Fitzgerald` is credited to the existing
  author row — same words in another order, or a shortened form that keeps the
  surname, and only when exactly one author matches.
- **A night is shared between the shops.** New releases take turns by source,
  so the first fifty are not all one publisher's.
- **Polite.** One request a second, identified, robots.txt read per shop and
  asked per page; a product page is only ever fetched from the shop's own host.

**Who did what.** Neither HarperCollins nor Speaking Tiger says who is author,
translator or illustrator — they list every credited name the same way. One
name is the author; several are staged as `contributors` and the book waits on
`author_roles` (~20% of both shops' newest pages). The prose on the page
usually does say ("in Kalpana Kannabiran's English translation"), so since
4 Oct 2026 `services/author_roles` asks the LLM — and uses the answer only when
plain string matching can verify every role against the publisher's own text
(a quote that is really there, about that person, saying the right thing).
One unknown holds the book. On eleven real held books: five resolved, all
correct; six held, including one where the model named a translator as an
author. Under a cent a book, metered, asked once. What it cannot resolve —
roughly half — still waits for a person, with the model's reply on the row.

**Not configured, and why:** Niyogi (robots.txt disallows the feed), Roli
(covers are 3D mock-ups; author strings carry ranks), Olive (fields are free
text in capitals), Seagull and Juggernaut (Shopify, and the author is a URL
slug or absent). Penguin India, Rupa, Hachette, Pan Macmillan, DC Books and
Green Books expose no feed at all.

**P4 — Malayalam breadth: DC Books.** *Not* LookaBook — it carries an ISBN on
15.6% of pages, so as an intake source it would deposit rejects, and it cannot
fill Mathrubhumi's 12.5% gap because it is weaker on the same field. Its real
uses are (a) a **discovery list** — its `publication` and author taxonomies name
books and publishers we should go looking for elsewhere, without promoting
anything, and (b) a fallback cover/author source for a book already identified
by ISBN. The breadth work itself is DC Books, via a feed if the conversation
lands or via their SPA's own endpoints if it does not.

**P5 — Selection quality for Indian English.** Curated publisher/prize/bestseller
seeds, author expansion, script gate.

**P6 — Retire the repair scripts.** `09` and `10` stay for the existing 1,428
rows; they must not be needed by anything P1–P5 produces. *That is the
acceptance test for this whole plan:* re-run `09_marc_cleanup.py plan` after a
month of intake and it should report **0 changes** against every row the daily
job created.

---

### The first night — 4 Oct 2026

1,607 rows staged, **150 published** (HarperCollins 51, Mathrubhumi 47,
Speaking Tiger 52; OpenLibrary 0, because new releases go first), in 21
minutes, with no failed row. 45 Malayalam books under Malayalam titles; every
cover in R2; 60 author-role questions, 17 resolved.

Eight of the 150 were undone and each became a rule (§3's gate, tightened the
same day): brand or bracketed author names, `Various`, selling lines in
titles, volume sets, and Hindi titles a shop labels English. Replayed over the
night's own rows the new gate refuses exactly those eight.

Two measurements that change the forecast:

- **Mathrubhumi's older pages mostly lack a Malayalam title.** 74 of the first
  208 pages read are held for `title_script`; the newest listings nearly all
  have one. Its ~3,700 titles will not all arrive under this rule.
  **Owner decision, 4 Oct 2026: keep them held** — a smaller Malayalam shelf
  under real titles over a larger one under romanizations. Nothing to build;
  the count is on the console's Nightly intake screen.
- **Author roles resolve about a quarter of the time** (17 of 60), not the
  ~45% of the eleven-book test.

**The second night (5 Oct 2026) published one book.** Not a source problem
and not the gate: the run crashed two seconds into publishing, on the row after
an undone book (see STATUS.md, 5 Oct). Fixed the same day — one row can no
longer end a run, a removed book is not re-added, and the console reports a
night that stops early. The 600 rows found that night and the 149 that should
have gone out are in the queue; nothing was lost (they were published the
same morning by a catch-up run).

**The backlist takes turns between sources** (owner decision, 5 Oct 2026).
It was taken strictly in the order it was found, and OpenLibrary is crawled
first every night — so Mathrubhumi's 237 ready books sat behind 181 of
OpenLibrary's and two nights went out entirely in English. Now each source
gives one book in turn, oldest first within a source, and a source with books
fills the night when the others run dry. On the queue as it stood that
morning, a night of 150 is HarperCollins 37, Mathrubhumi 38, OpenLibrary 38,
Speaking Tiger 37. New releases still go before any backlist.

## 6. Open decisions for the owner

**The intake was switched on 4 Oct 2026** (`ENV CATALOG_INTAKE_ENABLED=1` in
`api/Dockerfile`). See a night before it happens with
`scripts/preview_intake.py`; undo one with `scripts/revert_intake.py --since
<date>` (a dry run until `--apply`); stop it by deleting the `ENV` line.

1. ~~**Cover storage — A, B or C** (§4).~~ **Decided 3 Oct 2026: C, Cloudflare
   R2.** Remaining owner action is the one-time setup listed in §4.
2. **Approach DC Books about a feed + buy links.** Now the critical path for
   Malayalam breadth, not a nice-to-have — without it, "Malayalam" means one
   publisher's ~3,300 titles. Should start now; blocks P4, not P1–P3.
3. ~~**Daily promotion budget**~~ — **150 a night since 4 Oct 2026** (owner).
   At 50 the three storefronts' ~10,000 titles would have taken most of a year.
   Product-page reads were raised with it (300 a night), because two of the
   three shops are complete only once their page is read.
4. ~~**Romanized publisher titles**~~ — **settled 3 Oct 2026 by what the
   source turned out to have.** Mathrubhumi's product pages carry the title in
   Malayalam, so there is no need to accept a romanization: the gate now holds
   any book whose language is not written in Latin letters and whose title is
   (`title_script`). This reverses the earlier recommendation, on the owner's
   "name doesn't seem like a valid book" — and it is one rule in
   `intake_gate`, easily relaxed if a later source only has romanized titles.
5. **Confirm the reading of "no more adjustment records"** — this plan reads it
   as *"records must be born complete; no post-hoc repair passes"*, and that
   reading is what produced the gate in §3. If it meant something else, §3
   changes.
