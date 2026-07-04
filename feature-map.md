# Feature Map — Personal Library App (community-ready)

Every feature from your spec, sorted onto four layers. The layering is what lets a
solo personal app become a community platform later **without a rewrite**.

**Legend**
- `[V1]` — build now
- `[WIRED]` — build the *data shape* or *toggle* now, even though the feature is dormant. Cheap today, brutal to retrofit.
- `[LATER]` — genuinely defer. Needs a crowd or scale before it does anything.

**The one principle:** keep *shared* data, *personal* data, and *visibility* separate
from day one. In a well-layered personal app, every public/private toggle is a
community feature lying dormant.

---

## Layer 1 — Shared Catalog
*The global book record. Two users who own the same book point at the **same** entry,
not two copies — even while you're the only user filling it in.*

| Feature | Tag | Note |
|---|---|---|
| Book core: title, subtitle, description, cover, page count, pub date, language | `[V1]` | The catalog record |
| ISBN | `[V1]` | Identifier + dedupe key |
| Edition field | `[WIRED]` | See "Work vs. Edition" below — decide the model now |
| Authors (as catalog entities) | `[V1]` | Linkable — tap a name to browse every catalog work by them |
| Publishers (as catalog entities) | `[V1]` | Same, spanning authors instead of titles |
| Genres (global, descriptive) | `[V1]` | Belongs to the book, *not* to you |
| Series | `[V1]` | Cheap, readers love series ordering |
| Global/descriptive tags | `[WIRED]` | Keep separate from *personal* tags (Layer 2) |
| Add / edit a book | `[V1]` | Your data-entry path |
| Translated-book linking (original ↔ translation) | `[WIRED]` | Structure now, full UI later. **Decided 5 Jul 2026: a translation is its own Work**, not a language variant of an Edition — its own authors/genres/editions, and its own independent rating/review pool once Phase 3 lands (a translation is its own literary object; a fresh translation shouldn't inherit the original's reviews). Linked Works only share a `translation_group_id` for cross-navigation |
| Aggregate rating (avg across users) | `[WIRED]` | Computes for free *if* ratings attach here (see below). A **second**, separate aggregate — average *across every Work in a translation_group* — is computed at read time for display ("4.2 across all translations") without merging the underlying per-translation pools |
| Report incorrect info | `[LATER]` | Needs other users to matter |
| Verification status / verified badge | `[LATER]` | Nothing to moderate when solo |
| Author profile pages + author reviews | `[LATER]` | The *browse* page (works list) is `[V1]` — see Layer 1; a full profile (bio, follows, aggregate author rating, reviews of the author) is the later, reviewed-entity version |
| Publisher profile pages + publisher reviews | `[LATER]` | Same distinction as authors |

---

## Layer 2 — Personal Layer
*Your relationship to a shared book. This attaches **you** to a catalog entry.*

| Feature | Tag | Note |
|---|---|---|
| Add book to library / remove | `[V1]` | Core loop |
| Reading status: Pending, Reading, Read, Stopped, Wishlist | `[V1]` | |
| Start date / finish date | `[V1]` | |
| Personal notes | `[V1]` | Truly private. "Lent to mom, she folds pages" |
| Personal tags / shelves | `[V1]` | "beach reads," "to lend to Dad" — yours, not global |
| Favorite flag | `[V1]` | |
| Star rating (1–5) | `[V1]` | But **attaches to the shared book** — see below |
| Review (text) | `[V1]` | Attaches to book + you, with a visibility flag |
| Edit / delete review | `[V1]` | |
| Lending record ("lent to ___, on ___, returned ✓") | `[V1]` | A *record*, not a flag — see below |
| Borrowed-books shelf (books you borrowed from friends) | `[V1]` | Same ledger, other side — self-logged, or linked when the lender is also a Kitabi user |
| Reading progress updates (% or page) | `[V1]` | Lightweight |
| Reading sessions (timed logs) | `[LATER]` | Nice-to-have; skip for the thin slice |
| Quote / highlight capture (OCR a page) | `[LATER]` | Great "futuristic" add for v1.5 |
| Per-item visibility toggles (library / review) | `[WIRED]` | The dormant community switch |

---

## Layer 3 — Intelligence
*Reads from Layers 1 + 2. None of it needs a crowd.*

| Feature | Tag | Note |
|---|---|---|
| Dashboard summary cards (total, read, reading, wishlist, reviews) | `[V1]` | "Points earned" card → later |
| Stats: status-wise, language-wise, year-wise | `[V1]` | |
| Visualizations: pie / bar / line | `[V1]` | |
| Global search (your library + catalog) | `[V1]` | |
| Filters: language, genre, year, status, author, publisher | `[V1]` | "Verified" filter → later |
| Browse by author / publisher (tap a name → every catalog work by them) | `[V1]` | Uses the Layer 1 catalog entities already wired to be linkable |
| AI recommendations (LLM-reasoned, from your ratings) | `[V1]` | Your "futuristic." LLM sidesteps cold-start |
| Embedding-based similarity ("books like this") | `[LATER]` | The cheaper/faster v1.5 upgrade |
| Semantic / mood search ("like X but less bleak") | `[LATER]` | Strong differentiator for v1.5 |
| Shelf-scan-to-library (camera reads spines) | `[LATER]` | High-wow; pairs with ISBN scanner |
| Spoiler-aware AI reading companion | `[LATER]` | v1.5+ |
| Reading goals / challenges (personal) | `[LATER]` | Personal version is easy; defer for focus |
| AI-generated book insights | `[LATER]` | |

---

## Layer 4 — Community (dormant)
*Build **none** of this now. The point is that the seams already exist, so switching
it on is mostly building **views** over data that was already shaped to be shared.*

| Feature | Tag | Note |
|---|---|---|
| Follow users / public profiles | `[LATER]` | Profile + visibility flags are already wired |
| Activity feed | `[LATER]` | Your personal activity log *is* this — see below |
| Aggregate ratings shown publicly | `[LATER]` | Already computing if ratings live in Layer 1 |
| Book clubs | `[LATER]` | |
| Reading challenges (shared) | `[LATER]` | |
| Contribution tracking (books/reviews added) | `[LATER]` | Log your own activity now → becomes this |
| Points & rewards | `[LATER]` | |
| Badges / achievements / levels / leaderboards | `[LATER]` | Gamification needs scale |
| Peer-to-peer lending — social layer (borrower profile pages, notifications feed, in-app requests) | `[LATER]` | The lightweight version — a lending record optionally linking to a real Kitabi user so it appears on their Borrowed shelf automatically — is `[V1]`; this row is the fuller social layer on top |
| Review responses / community notifications | `[LATER]` | |
| Admin / moderation portal | `[LATER]` | Earns its keep only when there's shared content to police |

---

## Auth, platform & plumbing

| Feature | Tag | Note |
|---|---|---|
| Google Sign-In | `[V1]` | |
| Apple Sign-In | `[V1]` | |
| Session / token handling | `[V1]` | Whatever your stack needs |
| Mobile OTP login | `[LATER]` | SMS cost + rate-limit plumbing; add when you want it |
| Email OTP, Facebook, Instagram, WhatsApp linking | `[LATER]` | |
| Device tracking / login history | `[LATER]` | |
| **CSV import (Google Sheets export + Goodreads)** | `[V1]` | **Your front door.** Your users are already in a spreadsheet |
| Social share cards ("refer a book") | `[V1]` | Per-book (cover, rating, blurb) from any book page, plus a personal-endorsement variant with your rating + review; works fine solo |
| Lending-due reminder (local notification) | `[V1]` | Small, but a real spreadsheet-beater |
| Mobile app | `[V1]` | The platform |
| Web app | `[LATER]` | Mobile-first |

---

## The wiring that matters now

These are the handful of "do it now or pay dearly later" decisions. Everything else
can be added incrementally; these are expensive to reverse.

1. **Rating vs. review vs. notes are three things in three places.**
   - *Rating* (stars) → attaches to the **shared book**, so a cross-user average computes for free the day you go community.
   - *Review* (text) → attaches to **book + user**, with a visibility flag.
   - *Personal notes* → stay truly private on your library entry, forever.
   Splitting these now is what lets community aggregation work later with no migration.

2. **Lending is a record, not a flag — and it already has two sides.** Store "lent to
   ___, on ___, returned ✓" as its own little entry. The borrower/lender name is free
   text by default, but when it matches an existing Kitabi user, the record can carry
   an optional real-user reference now — that's what makes the loan appear on the
   *other* person's Borrowed shelf automatically, without waiting for full peer-to-peer
   community features. Same one record either way; only the reference is optional.

3. **Your personal activity log *is* the future feed.** Logging "you finished X, rated Y,
   added Z" for your own stats is structurally identical to a community activity feed.
   Build it for yourself; flip it public later.

4. **Visibility toggles everywhere.** Profile, library, and per-review public/private —
   build the toggles now even though nothing is visible to anyone yet. Switching on
   community is then mostly building views, not reshaping data.

5. **Work vs. Edition.** Decide whether the core unit is the abstract *Work* or a specific
   *Edition* (ISBN/printing). Usual answer: ratings/reviews → Work; ownership, page count,
   cover → Edition; translations link Works. Cheap to design now, costly to retrofit once
   reviews and translations are attached.

6. **Personal tags ≠ global genres.** Your shelves are yours (Layer 2); genres belong to
   the catalog (Layer 1). Don't let one pollute the other.

---

## Your v1 cut (the thin slice that actually ships)

Auth (Google + Apple) → **CSV import** → shared catalog with ISBN scan + manual add →
personal library with status, dates, notes, personal tags, favorite → ratings + reviews
(with visibility flags wired) → **lending records, lent and borrowed** → dashboard +
stats → search + filters → **LLM recommendations** → per-book and personal share cards.

Everything tagged `[WIRED]` gets its data shape built in this slice even though the
feature stays dormant. Everything `[LATER]` is deliberately absent — and *can* be absent,
because the layering left room for it.

---

## Competitive positioning (2026)

The market splits into two camps that barely overlap. **Catalog trackers** (Goodreads,
StoryGraph, Fable) care about *what you read*. **Collection apps** (Libib, BookBuddy) care
about *what you own*. This app sits in the gap: ownership + lending (Libib's turf) with
recommendations + a community path (StoryGraph's turf). The gap is real and mostly unserved.

| Rival | What it is | Its weak spot | Your counter |
|---|---|---|---|
| **Goodreads** | The 150M-user giant; Amazon-owned since 2013 | Stagnant and resented — added a DNF shelf only in Mar 2026, still no half-stars, dated UI. Moat is network + Kindle sync, not features | Don't fight the network. Win on ownership/lending + modern feel + regional focus |
| **StoryGraph** | The beloved challenger; **built by a solo founder**, 5M+ users, App Store Award | Stats bar is *very* high; social side is thin; deliberately no generative AI | Don't try to out-stat it. Do clean stats; win on lending + edition-level library feel |
| **Fable** | Social — book clubs + in-app e-reader | Got burned by an AI summary scandal; now Scribd-owned | Cautionary tale: keep AI transparent and optional (see below) |
| **Libib** | Closest rival — multi-media home cataloging, barcode scan | **Lending is paywalled (Pro)**; top complaint is no covers in list view / wants a "real bookshelf" look | Lending free + first-class; Edition-model covers answer the exact aesthetic gripe |
| **Bookmory** | Solo-dev, mobile-only tracker, 4.8★ / 16k+ ratings | No web, no social (deliberate) | Proof a solo dev can win here; you add ownership + lending it lacks |
| **Basmo / Margins** | Habit tracking; OCR quote capture; cover-edition choice; mood search | Niche, pricey, small catalogs | They *validate* your quote-capture, edition, and semantic-search ideas in-market |

### Three strategic warnings

1. **The market has turned against AI in reading apps — and that's your headline feature.**
   StoryGraph markets *no generative AI* as a virtue; Pagebound is deliberately AI-free;
   Fable got burned by a bad AI summary. Your audience (Goodreads refugees, spreadsheet
   purists) skews AI-skeptical. **Don't abandon the recs — reposition them:** opt-in,
   transparent ("you rated X and Y → Z, *because…*"), private, a helper not a replacement.
   Put *lending and library* on the billboard; let reasoned recs be a quiet delight.

2. **Cold-start on catalog is the real risk.** Rivals have millions of books; you start
   empty. This makes the still-open **metadata-source decision** (OpenLibrary vs. Google
   Books vs. paid) the highest-leverage open item you have — it decides whether the app
   feels populated or broken on day one.

3. **Import is non-negotiable.** Every serious tracker accepts Goodreads CSV. Your
   spreadsheet users can't switch without it — which is why it's already `[V1]`.

### Your wedge (what none of them combine)

- **Free, first-class lending** — Libib gates it; trackers ignore it.
- **Ownership + Edition model** — directly fixes Libib's cover/"real bookshelf" complaint.
- **Regional / translation angle** — `.in`, Malayalam roots, Work-translation structure;
  none of these English-first apps touch it.

The recommendation engine is the *hook*, but it's the most crowded and most AI-wary space.
Treat **lending and library-feel as the wedge**; let the recs be the pleasant surprise.

*(Landscape as of mid-2026; competitor features and pricing move fast — re-check before launch.)*
