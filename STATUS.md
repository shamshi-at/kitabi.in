# Kitabi — Status (Source of Truth)

> **Living document.** Update this file in the same commit whenever architecture,
> integrations, deployment, or feature status changes — it's the one place to look
> for "what is this, what's it built with, what's live, what's done." Don't let it
> drift: if a fact here would surprise someone reading the code, fix the fact here.
>
> Other docs stay narrower: [CLAUDE.md](CLAUDE.md) is dev conventions and non-negotiable
> rules, [feature-map.md](feature-map.md) is the full product spec, [docs/tasks.md](docs/tasks.md)
> is the phase-by-phase checklist, [docs/screen-design.md](docs/screen-design.md) is design
> tokens. This document summarizes and cross-links all of them plus the live/deployed state
> those docs don't cover.

**Last updated:** 6 Jul 2026

---

## Snapshot

Solo-built personal library app, pre-launch. **Phases 1–3 (auth & profile, shared
catalog, personal library + sync engine) are complete** — real Google + Apple sign-in,
a real Supabase project, a real Railway deployment at a real custom domain, a full
shared-catalog backend (works/editions/authors/publishers/genres/series) backed by
OpenLibrary with cache-on-first-use, and now a full offline-first personal library:
Drift schema, a sync engine ported from rupee-diary (push/pull, idempotent, conflict
rules), and the S5 library grid + S6 book detail screens (reading status, progress,
notes, ratings, reviews, lending, personal tags). Phases 4–8 (dedicated lending flows,
import, insights, recommendations, launch plumbing) are not started. The landing page
is live and public; the mobile app is not yet store-submitted. **Not yet verified: a
real end-to-end run with a signed-in user and real airplane-mode testing** — the sync
engine is thoroughly unit-tested (in-memory Drift + fake API client) and the app boots
cleanly with all the new plumbing wired in, but no session in this repo has driven it
through a real Google sign-in to see the library screens live (would need the owner's
own account).

---

## What this is

Kitabi ("Beyond the Bookshelf") is a mobile-first personal library app positioned
between reading trackers (Goodreads, StoryGraph) and collection apps (Libib): ownership
tracking + free first-class lending + an Edition-level "real bookshelf" feel, with a
regional/translation angle (`.in`, Malayalam roots) and quiet, transparent LLM
recommendations. Long game: personal app now, community platform later, without a
rewrite — see [feature-map.md](feature-map.md) for the full four-layer product spec.

---

## Architecture

Same architecture as the sibling project `rupee-diary` (proven there; see that
project's own `STATUS.md`), adapted for a catalog + personal-library domain instead
of shared budgets:

```
┌───────────────────────┐
│    Flutter App         │  ← user works here, ALWAYS against local DB (Layer 2 data)
│  ┌─────────────────┐  │
│  │  Drift (SQLite)  │  │  ← source of truth on device for personal library data
│  └────────┬────────┘  │
│     Sync Engine         │  ← queue, retries, conflict rules — built Phase 3
└──────────┬────────────┘
           │ HTTPS (JWT)
┌──────────▼────────────┐      ┌───────────────────┐
│   FastAPI (Railway)    │◄────►│ Supabase Postgres  │
│  - shared catalog API   │ pool │ - canonical data    │
│  - personal-data sync   │ 6543 │ - Auth (Google/Apple)│
│  - recommendations      │      │ - RLS deny-by-default│
└────────────────────────┘      └───────────────────┘
```

Two data tiers, never conflated (feature-map.md's core principle):
- **Layer 1 — shared catalog** (books, authors, publishers, genres, series):
  server-authoritative, fetched/cached, not user-synced. **Built in Phase 2** —
  `works`/`editions`/`authors`/`publishers`/`genres`/`series` tables (migration
  `000003`), backed by OpenLibrary (`api/app/services/openlibrary_client.py`) with
  cache-on-first-use: a book fetched once from OpenLibrary lives in our own Postgres
  for every later search. Ratings/reviews/translations attach to the **Work**;
  ownership/cover/ISBN/pages attach to the **Edition** (feature-map.md rule 17).
  **A translation is its own Work**, not a language variant of an Edition — its own
  authors/editions and its own independent rating pool, linked to the original only
  via a shared `translation_group_id` (decided 5 Jul 2026). A separate, read-time-only
  `translation_group_rating` field averages across the whole group for display
  ("4.2 across all translations") without merging the underlying per-translation pools.
- **Layer 2 — personal** (library entries, statuses, notes, tags, lending, reviews,
  progress): offline-first, Drift is the source of truth, synced via the sync engine
  (queue + push/pull). **Built in Phase 3**, ported from rupee-diary's proven pattern
  (CLAUDE.md: "reuse, don't reinvent") — same push-then-pull loop, same idempotency
  via a client-generated op UUID (`sync_ops` ledger), same delete-wins/last-write-wins
  conflict rules writing a `conflict_history` row. The one structural difference:
  Kitabi has no cross-user sharing in V1, so everything scopes by `user_id` alone (no
  `budget_id`/role checks), and the conflict signal is "a different one of *my*
  devices" (`device_id`, generated once per install) rather than "a different user."
  Tables: `library_entries`, `ratings`, `reviews`, `personal_tags`,
  `library_entry_tags`, `lending_records`, `activity_log_entries` (`[WIRED]`, written
  server-side as a mutation side effect, pull-only). A denormalized `cached_books`
  table (app-side only) gives the library grid offline-readable titles/covers/authors,
  populated the moment a book is added.

The `Profile` row (this session's Phase 1 work) is neither — it's the user's own
identity row, keyed directly by the Supabase auth user id, updated via direct online
`GET/PATCH/DELETE /me` calls, no sync queue involved. It now also carries an optional
unique **`username`** handle (set in the profile screen, validated `^[a-z][a-z0-9_]{2,19}$`,
lowercased, unique) — how other readers find you to lend to (`GET /users/search?q=`).

**Reputation / scoring** (added 6 Jul 2026): a StackOverflow-style score computed at
read time (`services/scoring_service.py`, `GET /me/score`, + `score` on `/me`) from the
rows a reader owns — books added (+10, via `works.created_by_user_id`), authors added
(+5, `authors.created_by_user_id`), reviews (+10), books tracked (+2), finished (+5),
lending records (+3). No ledger to keep in sync; just indexed COUNTs. Migration `000011`
adds `profiles.username`, `works.created_by_user_id`, `authors.created_by_user_id`
(verified upgrade+downgrade on a scratch DB — **pending deploy to Supabase**; the active
`.env` `DATABASE_URL` points at prod, so run the migration deliberately, not casually).

**Lending counterparty** (added 6 Jul 2026): the lend/borrow sheets' borrower field
(`BorrowerField`) now searches Kitabi users by username (sets the record's dormant
`borrower_user_id`, already accepted by the sync `LendingRecordCreate` schema) or takes a
free-text **private contact** — suggested from past borrowers (`pastBorrowerNames` DAO),
not shared, later linkable. Advances feature-map rule 14's "real user reference later".

---

## Tech stack

| Part | Stack | Version notes |
|---|---|---|
| `app/` | Flutter — Riverpod (`flutter_riverpod` ^2.6.1, codegen not yet used), go_router ^14.6.2, **Drift ^2.22.1 (full schema: 12 tables — 7 syncable Layer 2 entities, sync_queue/sync_state/conflict_history/key_values, and a denormalized cached_books offline read cache)**, Dio ^5.7.0, supabase_flutter ^2.8.0, sign_in_with_apple ^6.1.0, flutter_secure_storage ^9.2.2, google_fonts ^6.2.1, flutter_svg ^2.0.0, **workmanager ^0.9.0 (now wired: 15-min background sync)**, mobile_scanner ^6.0.2 (ISBN scan), image_picker ^1.1.2 + **image_cropper ^9.0.0 (crop picked images to grid before upload)**, connectivity_plus (sync-on-reconnect trigger), **flutter_local_notifications ^18.0.1 + timezone + flutter_timezone (on-device lending due-date reminders)** | iOS deployment target **15.5** (bumped from 14.0 — `mobile_scanner`'s MLKit requirement); SDK `^3.12.2`. `image_cropper` (UCrop) needs a `<activity com.yalantis.ucrop.UCropActivity>` in AndroidManifest.xml (added); on iOS it resolves via Swift Package Manager automatically (verified: release IPA built clean 6 Jul 2026) |
| `api/` | FastAPI 0.115.12, Python 3.12+, fully async — SQLAlchemy 2.0.36 async + asyncpg 0.30.0, Alembic 1.14.0, Pydantic 2.10.4, PyJWT[crypto] 2.10.1, APScheduler 3.11.0, httpx (OpenLibrary client), Docker | ruff + black line length 100 |
| `landing-page/` | Dependency-free static HTML/CSS, no build step, no frameworks | Fraunces + Inter via Google Fonts CDN |
| Database | Supabase Postgres — RLS deny-by-default, Data API disabled | Region: Southeast Asia (Singapore) |
| Auth | Supabase Auth — Google (browser-redirect `signInWithOAuth`) + Apple (native `signInWithIdToken`) | No password/OTP auth |
| Metadata source | **OpenLibrary** — Search API, Books API (`jscmd=data` ISBN lookup), Covers API. No API key/credential required | Chosen over Google Books (needs a managed API key) and any paid source (adds a bill) — see CLAUDE.md rule 8 |

---

## Repository layout

Monorepo root — see [CLAUDE.md](CLAUDE.md) for the full convention. Three independent
parts, each with their own README and CI workflow:

| Directory | What | Status |
|---|---|---|
| `landing-page/` | Static "launching soon" site | **Live** at kitabi.in |
| `api/` | FastAPI backend | **Live** at api.kitabi.in — auth/profile + shared catalog (search, ISBN lookup, add/edit, author/publisher browse) |
| `app/` | Flutter mobile app | Auth flow + library-first home + catalog screens working (global search across library/books/authors/publishers, ISBN scan → adds to library, add/edit form with author/publisher **picker pages**, author/publisher browse, shareable book/author/publisher links) + personal-library grid & book detail |
| `docs/` | Mockups, design tokens, task checklist | — |

---

## Integrations & external services

| Service | Purpose | Account / project ref | Configured in |
|---|---|---|---|
| **Supabase** | Postgres + Auth (Google, Apple) | Project ref `lwyifccwirfmgdvemgkz`, region Southeast Asia (Singapore), org "Shamsheer AT's Projects" (workspace also holds rupee-diary) | `api/.env` (`DATABASE_URL` = Supavisor transaction pooler, port 6543; `SUPABASE_URL`) |
| **Google Cloud OAuth** | Google sign-in | One **Web application** OAuth client (not Android/iOS native), redirect URI = Supabase's `/auth/v1/callback` | Configured in Supabase → Authentication → Providers → Google |
| **Apple Developer** | Apple sign-in | App ID `in.kitabi.kitabi` (Sign in with Apple capability), Services ID `in.kitabi.kitabi.web`, a Sign in with Apple key (Key ID + Team ID `62686X3746`) | Supabase → Authentication → Providers → Apple. Secret JWT regenerated via `api/scripts/gen_apple_secret.py` (expires ~6 months — no automation for this yet, see Open decisions) |
| **Railway** | API hosting | Project `kitabi-api`, service `kitabi-api`, connected to `shamshi-at/kitabi.in` (branch `main`, Root Directory `api`) for git-based auto-deploy | `api/railway.json` (Dockerfile builder, `/healthz` healthcheck); env vars set directly in Railway dashboard (not in repo) |
| **Cloudflare** | DNS (kitabi.in), landing page hosting | `api` CNAME → Railway target (proxied), SSL/TLS Full (strict); Pages project `kitabi-in` for the landing page | DNS: Cloudflare dashboard (manual). Pages deploy: `.github/workflows/deploy.yml`, secrets `CLOUDFLARE_API_TOKEN`/`CLOUDFLARE_ACCOUNT_ID` |
| **GitHub Actions** | CI (lint/test/build checks only — not deployment) | `shamshi-at/kitabi.in` | `.github/workflows/api-ci.yml`, `app-ci.yml`, `deploy.yml` (landing only) |

Deliberately **not** using: Firebase (not yet needed — no push notifications built),
any paid metadata API (open decision), Redis/queues (cost rule — CLAUDE.md rule 8).

---

## Deployment — live URLs

| What | URL | Hosted on | Notes |
|---|---|---|---|
| Landing page | https://kitabi.in | Cloudflare Pages, git-deploy from `landing-page/` on push to `main` | Live, public. `/b/:id`, `/a/:id`, `/p/:id` are served by Cloudflare **Pages Functions** (`landing-page/functions/`) that inject real Open Graph tags (cover/title/blurb) server-side, so shared links preview richly in iMessage/WhatsApp/Slack — bots don't run the pages' client JS. Humans still get the JS-rendered page |
| API | https://api.kitabi.in | Railway service `kitabi-api`, proxied CNAME via Cloudflare (Full strict) | Live; auth/profile + catalog endpoints (incl. global search + author/publisher create). CORS now allows `kitabi.in` for the public share pages |
| API (origin, fallback) | https://kitabi-api-production.up.railway.app | Direct Railway domain | Keep working in case the custom domain ever breaks |
| Mobile app | — | Not store-submitted | Auth verified on iOS Simulator (Phase 1); catalog screens verified on an Android emulator against a local API (Phase 2) — `mobile_scanner`'s MLKit dependency can't build on an Apple Silicon iOS simulator (no arm64 simulator slice), so the scan screen specifically needs a real iOS device or an older x86_64-capable simulator runtime to verify there. Real app icon + splash screen now in place (see below). An IPA has been built pointed at production (`app/build/ios/ipa/kitabi.ipa`), but it's **development-signed only** — no Apple Distribution certificate exists yet, so it can only run on devices registered to the provisioning profile, not TestFlight/App Store |

Redeploy the API by pushing to `main` (Railway auto-deploys); no manual `railway up`
needed anymore. Redeploy the landing page the same way (push to `main` touching
`landing-page/**`).

---

## Environments & secrets

Secrets live in exactly two places, never in the repo:
- **`api/.env`** (gitignored) — local dev database URL, Supabase URL. Copy from `api/.env.example`.
- **Railway dashboard env vars** (production) — `DATABASE_URL` (Supavisor pooler), `SUPABASE_URL`,
  `ENV=production`, `SCHEDULER_ENABLED=true`.
- **GitHub Actions repo secrets** — `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` (landing page deploy only; API deploy doesn't go through Actions).
- **Apple's `.p8` private key** — kept locally outside the repo (used only to run `api/scripts/gen_apple_secret.py` when the OAuth secret needs regenerating); never committed.

---

## CI/CD

Mirrors rupee-diary's pattern exactly (see that project's own CI for comparison):

- **`api-ci.yml`** (paths: `api/**`) — ruff, black, pytest against a real `postgres:17-alpine`
  service container, pip-audit (advisory, `continue-on-error`), `docker build`.
- **`app-ci.yml`** (paths: `app/**`) — `flutter pub get`, `build_runner` (now generates real
  Drift + Riverpod code — the full personal-library schema and DAOs), `flutter analyze`, `flutter test`.
- **`deploy.yml`** (paths: `landing-page/**`) — the only workflow that actually deploys anything;
  ships to Cloudflare Pages.
- **API deployment is NOT via GitHub Actions** — Railway's own git integration watches
  `main` and redeploys on push (Root Directory `api`, set in Railway's dashboard, not
  expressible in `railway.json`).
- No backup workflow yet (rupee-diary's `backup.yml` — nightly encrypted `pg_dump` → R2 —
  is the reference; tracked in [docs/tasks.md](docs/tasks.md) Phase 8, not built since
  there's no real user data yet).

---

## Features — status

Full spec in [feature-map.md](feature-map.md); phase-by-phase checklist in
[docs/tasks.md](docs/tasks.md). Current state by phase:

| Phase | What | Status |
|---|---|---|
| 0 — Foundations | Monorepo, scaffolds, landing page, logo, mockups | Mostly done — CI workflow ✅, theme ✅; local dev runbook still open |
| 1 — Auth & profile | Google + Apple sign-in, profile bootstrap, visibility switchboard | **✅ Done, verified live in production** |
| 2 — Shared catalog | Books/authors/publishers/series, ISBN scan, Work vs Edition | **✅ Done** — OpenLibrary-backed, cache-on-first-use, migration `000003`, `GET /catalog/search`, `GET /catalog/isbn/{isbn}`, `POST/PATCH /catalog/works`, `PATCH /catalog/editions/{id}`, `GET /catalog/authors?q=` + `GET /catalog/publishers?q=` typeahead, author/publisher browse; app has search, ISBN scan, add/edit form (author/publisher are now dropdown-cum-add-new typeaheads; typeset cover previews live as you type), author/publisher browse screens |
| 3 — Personal library + sync engine | Drift schema, sync queue, push/pull, status/notes/tags/ratings/reviews | **✅ Done** — migration `000004`, `POST /sync/push` + `GET /sync/pull`, delete-wins/LWW conflict rules, `[WIRED]` activity log; app has S5 library grid + S6 book detail (status/progress/notes/rating/review/lending/tags), workmanager + connectivity-triggered background sync. ISBN scan "Add" now creates a library entry (was a no-op that only popped the scanner). Sync engine verified via unit tests (mocked API, in-memory Drift), not yet via a real signed-in device run |
| 4 — Lending | Lend/borrow records, linked vs self-logged, due reminders | **In progress** — Slices A–C: Lending ledger (S8) with **Lent out** and **Borrowed** tabs (Out now / With-you-now / Returned, computed due stamps, mark-returned / "I've returned it"). Borrowed side via migration `000005` (`direction`/`edition_id`/`linked_loan_id`/`note`, nullable `library_entry_id`); log-borrowed sheet (S8c, inline catalog search); S9 lend bottom sheet; **due-date local reminders** (`flutter_local_notifications`, on-device, scheduled 9am on the due date, cancelled on return — firing not yet device-verified). Still to build: cross-user match/mirror `[WIRED]` (Slice D) |
| 5 — Import | Goodreads/CSV import | **Core done** — `import_service.parse_csv` (Goodreads + generic, fuzzy columns; unit-tested) + `POST /import/preview` (parse + local catalog match by ISBN/title). App S2 screen: paste CSV → preview matched/unmatched → import matched into the library (status/rating/review), offline-first. CSV **export** via `buildLibraryCsv` + share_plus from the profile. Follow-ups: native file picker (paste for now — file_picker's Android plugin conflicts with the SDK toolchain), and create-if-missing (OpenLibrary fetch) for unmatched rows |
| 6 — Insights & search | Dashboard, stats, filters, author/publisher browse | **Core done** — **bottom-nav shell** (Home · Library · [+] · Lending · Insights, `StatefulShellRoute`) + the real **S3 home dashboard** (currently-reading with page progress, gold-edged lending nudge, 2×2 shelf-count cards). AI pick deferred to Phase 7. **global search (S4)** — library-first (offline Drift) then catalog (API); **Insights/stats (S10)** — reading-goal ring (device-local goal), year selector, books/pages/reading-now stats, and a dependency-free books-per-month bar chart from a pure `computeInsights`. **filter sheet (S4b)** — library grid filters by status/language/favourites with a live count. Phase 6 core complete; follow-ups: S10 language donut + pages/month line, S4b genre/year facets |
| 7 — Recommendations & share | LLM recs, per-book + personal share cards | **Core done** — **share cards (S6c/S13)** (`BookShareCard` → PNG via `RepaintBoundary` + `share_plus`, include-my-rating toggle, from the book page) and **LLM recommendations (S11)**: `GET /recommendations` reasons picks from the reader's ratings via Claude (gated behind an optional `ANTHROPIC_API_KEY` — dormant/no bill when unset), opt-in S11 screen with a "why" per pick, always-visible off switch, + Wishlist / Not-for-me, and a quiet "For you" home card. Live LLM output not yet verified (no key set) |
| 8 — Launch plumbing | Version gate, backups, app icons, store listings, privacy policy | **Mostly done** — version gate (426 + update screen), Supabase keep-warm job, nightly encrypted R2 backup workflow, privacy + terms pages, Railway deploy + custom domain + app icons/splash all ✅. Remaining: store listings + store badges (pre-submission) |

All 19 v1 screen mockups exist in [docs/kitabi_screens.html](docs/kitabi_screens.html),
audited against feature-map.md so every `[V1]` feature has a designed home before it's built.

---

## Recent milestones

- **6 Jul 2026** — On-device feedback pass (10 fixes). **API latency**: a single
  fetched work went 1.7s → **0.19s** by loading one joined query instead of
  selectinload's four round-trips (`_WORK_JOINED`); summary lists dropped the unused
  genres load; the engine now normalizes any `postgres://`/`postgresql://` scheme to
  asyncpg so the pool + pooler-safe connect args always apply, and keeps a warmer,
  recycled pool. **The remaining ~2s was geographic and is now fixed** — the Railway
  service was running in `sfo` (US) while Supabase is in Singapore; pinning a single
  Singapore replica via `railway.json` `multiRegionConfig` co-located them and took
  every endpoint from ~2s to **~0.2–0.3s** (verified live). See the resolved gap below.
  **Covers**: fixed the `TypesetCover` infinity bug (library-grid covers
  rendered blank because font/padding were computed off `width: infinity`; now via
  `LayoutBuilder`), and a `scripts/backfill_covers.py` filled real OpenLibrary covers
  for editions that have them (5/82 — regional titles have sparse coverage, the rest
  keep the improved typeset covers). **Home**: title merged into the top action row
  (removed dead space); shelf cards are now tappable (Owned/Read/Wishlist → the library
  tab, deep-linking `?status=`; Lent out → the ledger). **Sync banner**: moved below
  the notch (was over the clock) and restyled as a slim centered pill. **Browse**:
  bolder entry button + a **sort (title/newest/oldest/author) and language filter** on
  the Books tab (`GET /catalog/browse/works?sort=&language=`, `GET /catalog/browse/languages`).
  **Share**: the landing `_redirects` now rewrite `/b/:id` to the extensionless clean
  path so shared links stop 308-redirecting to `/book` and dropping the id; the share
  card capture waits for `endOfFrame` and falls back to sharing text+link if rasterising
  fails. API 64 tests + app 28 tests green, lint clean, Docker builds.

- **6 Jul 2026** — Discover/browse screen + `[WIRED]` buy links. A dedicated
  **Browse** surface (`/catalog/browse`, reached from a book icon on the home header
  and the search screen's empty state) lets users wander the whole catalog with three
  infinite-scroll tabs — **Books · Authors · Publishers** — backed by new paginated
  `GET /catalog/browse/{works,authors,publishers}` endpoints (alphabetical, offset
  paging, keep-alive per tab). Author/publisher rows tap through to their browse pages;
  book rows to book detail. **Buy links wired but dormant** (`[WIRED]`): a `buy_links`
  JSONB column on Edition (a list of `{retailer, url}` — Amazon, Flipkart, … — so a book
  page lists every store it's available at; migrations `000008` added a single `buy_url`,
  `000009` replaced it with the list), threaded through `EditionOut`/`EditionUpdate`, with
  a **"Where to buy"** section on the book page (app) and the public landing book page that
  appears **only when `buy_links` is non-empty** (via `url_launcher` in-app) — so
  integrating external-ecommerce links later is just populating the field, no rewrite. API
  62 tests + app 28 tests green, ruff/black + analyze clean, Docker builds.

- **6 Jul 2026** — Search, author/publisher pickers, and shareable links (feedback pass).
  **Global search (S4)** now spans four things in one screen — the offline library (Drift)
  plus the catalog's **books, authors, and publishers** via a new `GET /catalog/search/all`
  (`{works, authors, publishers}`); authors/publishers tap through to their browse pages,
  and a search icon now sits on the home header. **Author & publisher pickers**: the add-book
  form's author/publisher fields open dedicated picker pages (`/catalog/author-picker`,
  `/catalog/publisher-picker`) that search existing catalog entries (showing portrait/logo +
  **primary language**) or add a new one with details — backed by new `POST /catalog/authors`
  and `POST /catalog/publishers` and a new `primary_language` column on both (migration
  `000007`). Works now accept `author_ids`/`publisher_id` (canonical picks) alongside the old
  name path. **Shareable links**: the book share sheet's "Copy link" now produces a real URL
  (`https://kitabi.in/b/{id}`), the share-card capture was hardened (frame-wait + iPad
  `sharePositionOrigin` + error surface), and author/publisher browse pages gained share
  buttons. Those links land on **new public landing pages** (`book.html`/`author.html`/
  `publisher.html`, clean-routed via `_redirects` as `/b/:id` `/a/:id` `/p/:id`) that fetch
  the public catalog API (CORS opened to `kitabi.in`), render the details, and always show a
  "Get Kitabi" download banner — degrading to a friendly fallback + banner when the API is
  unreachable. **Content deep links** (`app_links` listener scoped to kitabi.in, mirrored
  in-app routes, iOS associated-domains + Android autoVerify intent filter, landing
  `.well-known/apple-app-site-association` + `assetlinks.json`) so a shared link can open the
  app when installed. API 59 tests + app 27 tests green, ruff/black + analyze clean.
  **Placeholders a human must fill before universal links verify on-device:** `TEAMID` in the
  AASA file and the signing `SHA256` in `assetlinks.json` (both under `landing-page/.well-known`).

- **6 Jul 2026** — Phase 8 launch plumbing + Phase 5 (import) + phase follow-ups. **Import
  (S2)**: `import_service.parse_csv` (Goodreads + generic) + `POST /import/preview` (catalog
  match); app pastes CSV → previews → imports into the library; CSV **export** from the profile.
  **Version gate**: `VersionGateMiddleware` (426 + update payload) ↔ Dio `X-App-Version` +
  blocking `UpdateScreen`. **Keep-warm** APScheduler job (6-hourly, advisory-locked). **Nightly
  encrypted R2 backup** workflow (skips until secrets set). **Privacy + Terms** pages on the
  landing site. Follow-ups shipped too: author portraits/pen-names + publisher logos in browse
  screens, S10 language donut + pages/month line, S4b genre facet. API 54 tests + app 27 tests
  green, lint clean, Docker + Android APK build. Deferred: native file picker (paste for now),
  store badges (pre-listing), lending Slice D `[WIRED]`.

- **6 Jul 2026** — Seed catalog: major Kerala authors, publishers, works. Migration `000006`
  adds `authors.pen_name`/`authors.image_url` and `publishers.logo_url`. `api/scripts/seed_catalog.py`
  (idempotent, upserts by name/title, uses the pooler-safe engine) loads 37 major Malayalam
  authors — with pen names (Madhavikutty, MT, Uroob, Anand, VKN…) and Wikimedia portrait URLs —
  10 publishers (DC Books + Manorama logos), and ~80 major works with Malayalam editions.
  **Run against the production Supabase catalog** (Layer 1 shared data, no user PII; idempotent
  and reversible); verified live via `GET /catalog/search` and `/catalog/authors`. Author
  portraits / publisher logos aren't surfaced in the app UI yet (author/publisher browse screens
  are a follow-up).

- **6 Jul 2026** — Phase 7 — recommendations & share. **Share cards (S6c/S13)**: `BookShareCard`
  (cover, title, catalog-avg or your rating, blurb or your review, kitabi.in mark) rasterised via
  `RepaintBoundary` and handed to the OS share sheet with `share_plus`, from a sheet with an
  "include my rating & note" toggle. **LLM recommendations (S11)**: `GET /recommendations` gathers
  the reader's ratings + catalog candidates and asks Claude for reasoned picks with a plain-words
  "why" — gated behind an optional `ANTHROPIC_API_KEY` so it's dormant with no external call/bill
  until the owner opts in (rule 8). Opt-in, off-by-default S11 screen with an always-visible off
  switch and + Wishlist / Not-for-me; a quiet "For you" card on home. API 43 tests + app 26 tests
  green, lint clean, Android build verified with `share_plus`. Live LLM output not yet verified
  (no key configured).
- **6 Jul 2026** — **Translations & multi-edition, now with UI.** The `[WIRED]` translation link
  is live end-to-end: `POST /works/{id}/link-translation` (now rejects self-links) + a new
  `WorkOut.translations` (sibling Works in the group, computed in `_work_out`). New
  `POST /works/{id}/editions` (`EditionCreate`, inherits the Work's language) adds a printing to
  an existing Work — no new DB columns. App: `linkTranslation`/`createEdition` on the API client;
  a **Work picker** (search + pick, excludes self); an **Add-edition** screen (ISBN+scan, format,
  pages, publisher, cover); and two new **book-page sections** — *Editions* (list + "Add another
  edition") and *Also in other languages* (linked translations + "Link a translation"). This is
  the Dantha Simhasanam ↔ Ivory Throne flow (a translation is its own Work, group-linked). 4 new
  API tests; 30 app + 70 API tests green, lint clean.
- **6 Jul 2026** — **Animated splash.** The bare-logo splash now plays a staggered Reading Room
  intro — the mark settles in, "Kitabi" (Fraunces) rises, the gold line draws across, the
  "Beyond the Bookshelf" tagline fades in — then a quiet three-dot loader + "Opening your reading
  room…" status while auth/profile resolve. Honours `MediaQuery.disableAnimations` (reduced
  motion shows the settled state). Widget test asserts name/tagline/status render.
- **6 Jul 2026** — **Author & publisher share cards.** Sharing an author/publisher now renders
  an image card (portrait/logo + name + works/titles count + kitabi.in mark) instead of a bare
  text link, matching books. New `EntityShareCard` + `showEntityShareSheet`; the rasterise +
  image-or-text-fallback capture logic is extracted to `share_capture.dart` and shared with the
  book sheet. Both sheets now `precacheImage` the cover/portrait so the shared PNG never captures
  a half-loaded image.

- **6 Jul 2026** — Phase 6 continued — global search + insights. **Global search (S4)**: the
  search screen now shows an "In your library" section (offline Drift match by title/author,
  status pill → book detail) above the catalog API results. **Insights/stats (S10)** replaces
  the stub: a reading-goal ring (goal stored device-local in `key_values`, tap to edit), a
  year selector (this year / last year / all time), books-read / pages-read / reading-now
  stats, and a dependency-free books-per-month bar chart — all reduced by a pure, unit-tested
  `computeInsights`. 23 app tests green (new: library search, insights stats), analyze clean.

- **6 Jul 2026** — Phase 6 started — navigation shell + home dashboard. A persistent
  **bottom-nav shell** (`StatefulShellRoute.indexedStack`: Home · Library · [+] · Lending ·
  Insights) replaces the temporary app-bar icons; the centre "+" pushes the add flow, and
  detail screens (book, author/publisher, add/scan, profile) push full-screen over the nav.
  Library and Lending lost their back buttons (they're tabs now). The interim home became the
  real **S3 dashboard**: currently-reading cards with page progress, a gold-edged **lending
  nudge** (soonest-due active lend, tap → ledger), and 2×2 shelf-count cards (Owned / Read /
  Lent out / Wishlist). Insights is a stub pending S10. The AI-pick card stays Phase 7. 21 app
  tests green (new: home shelf-count render), analyze clean.

- **6 Jul 2026** — Phase 4 Slice C — the lend flow + reminders. **S9 lend bottom sheet**
  (to-whom, lent-on, optional due date, note; shared field widgets with the log-borrowed
  sheet) replaces the old lend dialog. **Due-date local reminders** via
  `flutter_local_notifications` (+ `timezone`/`flutter_timezone`) — on-device only (no push,
  no server; rule 8), scheduled at 9am local on the due date when a lend/borrow has one and
  cancelled when the book is returned. Native config added: Android core-library desugaring +
  POST_NOTIFICATIONS/RECEIVE_BOOT_COMPLETED + boot receiver, iOS UNUserNotificationCenter
  delegate. Scheduling logic (stable id, 9am time) is a pure unit-tested function; 20 app
  tests green, analyze clean. **Reminder firing not yet verified on a real device** (same
  standing signed-in-device gap).

- **6 Jul 2026** — Phase 4 Slice B — the **Borrowed** side of the ledger. Migration `000005`
  adds `direction` (lent/borrowed), `edition_id` (a borrowed book isn't owned, so it's carried
  by the catalog edition instead of a library entry), `linked_loan_id` (dormant cross-user
  correlation `[WIRED]`), and `note`; `library_entry_id` becomes nullable. Drift schema bumped
  to v2 with a `TableMigration`. Ledger screen gains Lent-out / Borrowed **tabs**; the Borrowed
  tab shows self-logged borrows (With-you-now / Returned) with "I've returned it", plus a
  **log-a-borrowed-book sheet** (S8c) with inline catalog search. The DAO join resolves the
  book via the library entry *or* the record's own `edition_id`. 17 app tests + 40 API tests
  green (borrowed sync push/pull, borrowed-join, logBorrowed), lint clean, Docker builds.

- **6 Jul 2026** — Phase 4 (Lending) started — Slice A: the **Lending ledger** screen (S8,
  Lent-out side). New `LendingRecordsDao.watchAllActive()` joins each synced lending record
  through its library entry to the cached book; reactive `allLendingProvider` feeds an Out-now
  / Returned ledger with a computed due stamp (Due in Nd / Due {date} / Overdue / No due date)
  and mark-returned. The book-detail lend dialog now captures an optional due date. Home gains
  a lending entry point (temporary until the Phase 6 bottom nav). 16 app tests green (3 new:
  DAO join, mark-returned + sync-op, screen render), analyze clean. Next slices: Borrowed tab
  + log-borrowed flow, full lend sheet, due-date reminders.

- **6 Jul 2026** — Post-Phase-3 UX pass from real on-device feedback: (1) home was an
  empty placeholder → now a library-first landing (currently-reading row + recent-books
  grid + add CTA; full S3 dashboard stays Phase 6); (2) **bug** — the ISBN-scan "Add"
  button only popped the scanner and never created a library entry, so scanned books
  vanished → now adds to the library, caches for offline, and opens the book; (3)
  add/edit form author & publisher became dropdown-cum-add-new typeaheads
  (`GET /catalog/authors?q=` + `/catalog/publishers?q=`, authors as removable chips);
  (4) the typeset cover on the form now redraws live as the title/author are typed.
  `libraryEntriesProvider` switched to a reactive Drift stream so adds surface on the
  always-alive home route without hand-invalidation. API + app tests + lint green,
  Docker builds.

- **6 Jul 2026** — Fixed the real cause of "Couldn't sign in" on a TestFlight build:
  `SUPABASE_URL`/`SUPABASE_PUBLISHABLE_KEY` were never passed as `--dart-define`s to
  any local IPA build, so `supabaseConfigured` was false and the app silently used
  `UnconfiguredAuthService` (throws on every sign-in attempt, no build-time warning).
  Added `app/dart_defines.env` (gitignored) + `scripts/build_ipa.sh`/`run_dev.sh`,
  which read every required define and fail loudly if one's missing — replacing
  hand-typed `--dart-define` flags, which is exactly how this and the earlier
  `API_BASE_URL` bug both happened. Rebuilt and confirmed via `strings` on the
  compiled binary that the Supabase project ref and `api.kitabi.in` are present and
  `localhost:8000` is absent.
- **6 Jul 2026** — Real app icons + native splash screens: `flutter_launcher_icons`
  (full-bleed icon source, no pre-baked rounding — the OS applies its own mask;
  Android adaptive icon with an oxblood background layer) + `flutter_native_splash`
  (paper background + the existing rounded Gold Line mark, matching `SplashScreen`
  exactly). Also found and fixed a real bug: the first IPA build had no
  `API_BASE_URL` dart-define, so it defaulted to `http://localhost:8000` — unreachable
  from a real device, breaking anything that talks to the API. Rebuilt pointed at
  `https://api.kitabi.in` (confirmed healthy). The IPA is still development-signed
  only (no Apple Distribution certificate in this environment), so it can only run
  on a device registered to the provisioning profile — not TestFlight/App Store yet.
- **6 Jul 2026** — Phase 3 complete: personal-library sync engine ported from
  rupee-diary (migration `000004`; `POST /sync/push` idempotent via a `sync_ops`
  ledger; `GET /sync/pull?cursor=`; delete-wins/last-write-wins conflict rules keyed
  by `device_id` since Kitabi has no cross-user sharing). App-side: full Drift schema
  (12 tables), repositories, `SyncEngine`, workmanager 15-min drain + connectivity
  trigger, a denormalized offline cache for library-grid display. UI: S5 library grid
  (status pills, favourite ribbon, lending band, filter chips) and S6 book detail
  (add/remove, 5-state status picker, progress, notes, star rating, review +
  visibility, lending, personal tags). 36 backend tests total, 12 Flutter tests
  (5 new sync-engine unit tests with a fake API client + in-memory Drift).
- **5 Jul 2026** — Phase 2 complete: metadata source decided (OpenLibrary), shared
  catalog schema + migration (`works`/`editions`/`authors`/`publishers`/`genres`/`series`),
  catalog search + ISBN lookup (cache-on-first-use, verified live against the real
  OpenLibrary API) + add/edit + author/publisher browse endpoints, `[WIRED]` translation
  linking and aggregate rating; app got a catalog search screen, `mobile_scanner` ISBN
  scan screen, add/edit form, and author/publisher browse screens, all with tappable
  author/publisher names. Verified end-to-end on an Android emulator against a local API
  (iOS Simulator can't build `mobile_scanner` on Apple Silicon — see Open decisions).
- **4 Jul 2026** — Phase 1 complete: Google + Apple sign-in built, tested end-to-end on
  a real iOS simulator against a real Supabase project (real profile row confirmed in
  the database); API deployed to Railway with git-based auto-deploy; custom domain
  `api.kitabi.in` live with a valid certificate; CI workflows added.
- **4 Jul 2026** — Author/publisher browse pages, borrowed-books shelf (both directions
  of lending), and generic per-book share cards designed into the mockups + feature map.
- **3 Jul 2026** — Landing page redesigned in the Reading Room theme; logo finalized as
  "The Gold Line" after five concept rounds; full SEO metadata + multilingual quote carousel.
- **2 Jul 2026** — Monorepo restructure (landing-page/api/app), API and Flutter scaffolds,
  12 initial screen mockups, design tokens.

---

## Open decisions / known gaps

- ~~**API ↔ DB not co-located**~~ — **RESOLVED 6 Jul 2026.** The ~2s-per-request
  latency was the Railway service running in **`sfo` (US)** while Supabase is in
  **Singapore** — every query paid the cross-region RTT. Root cause found via
  `railway status --json`: a leftover dashboard `multiRegionConfig` pinned the
  replica to `sfo`, so setting `deploy.region` alone didn't move it. Fixed in
  config-as-code (`api/railway.json`) by declaring
  `deploy.multiRegionConfig: {"asia-southeast1-eqsg3a": {numReplicas: 1}}`, which
  replaced the US placement with a single Singapore replica next to the DB.
  **Verified live: 2s → ~0.2–0.3s on every catalog endpoint** (book detail 2.0→0.2s,
  browse 4.7→0.23s, search 5.7→0.24s). The code round-trip reductions (single joined
  work fetch, lighter summary loads) compound on top. If a second region/replica is
  ever added, keep at least one replica co-located with Supabase's region.

- **No Apple Distribution certificate in this local environment** — only an Apple
  Development identity exists in this Keychain, so IPAs built here via
  `scripts/build_ipa.sh` are development-signed (devices registered to the
  provisioning profile only). **A real TestFlight build does exist** (seen in
  App Store Connect, "Ready to Submit"), which means it was produced by a
  different pipeline than this local one (Xcode Cloud or another machine) —
  that pipeline's own signing setup is out of scope for what's tracked here.
  **Important:** if that pipeline builds independently (not via this repo's
  `scripts/build_ipa.sh`), it needs the same three `--dart-define` values
  (`API_BASE_URL`, `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`) configured in its
  own build settings/environment — the "couldn't sign in" bug (6 Jul 2026, see
  milestones) was caused by these being silently absent, and that would repeat
  on any build path that doesn't set them, not just local ones.
- **Apple OAuth secret expiry** — the JWT Supabase uses for Apple sign-in expires every
  ~6 months (`api/scripts/gen_apple_secret.py` regenerates it); no reminder/automation
  exists yet — worth a calendar reminder or a scheduled check.
- **No backup job yet** — fine while there's no real user data; must exist before real
  users sign up (rupee-diary's `backup.yml` is the reference).
- **Local dev / Supabase project creation runbook** — not yet written (Phase 0 task).
- **`mobile_scanner` can't be verified on an Apple Silicon iOS Simulator** — Google's
  MLKit pods ship no arm64 simulator slice, and the only iOS runtime installed in this
  dev environment (iOS 26.5) has no x86_64 fallback either. A Podfile `post_install`
  hook excludes arm64 for `sdk=iphonesimulator*` (real devices unaffected), but the
  simulator itself can't build at all without an older x86_64-capable runtime. Verified
  instead on an Android emulator; verify the scan screen on a real iPhone before launch.
- **User-photo cover upload** — the app picks a photo (`image_picker`), crops it to a 2:3
  book-cover portrait (`image_cropper`, `core/image_crop.dart`), uploads it to the Supabase
  Storage bucket **`covers`** as `<editionId>.jpg` (`upsert: true`), then points the
  edition's `cover_url` at the public URL (tap the cover on the book page). Every image
  picker in the app crops before upload — covers to 2:3, author portraits and publisher
  logos to 1:1 square — so uploads always match the shape they render in. This is the one
  place the app talks to Supabase Storage directly (via the user's auth JWT), not through
  FastAPI — separate from the deny-by-default Postgres tables, so rule 11 is untouched.
  Covers are shared (path is per-edition, and it patches the shared `Edition.cover_url`) —
  consistent with Editions being Layer-1 catalog data (rule 17).
  - **Owner setup (done 6 Jul 2026):** `covers` bucket created **Public** (the app renders
    covers with a plain `Image.network(getPublicUrl(...))` that carries no auth header, so
    the bucket must be public — an authenticated SELECT policy alone won't make images load),
    plus one Storage policy on `storage.objects`: SELECT+INSERT+UPDATE for `authenticated`
    with `bucket_id = 'covers'` (INSERT+UPDATE both required because the upload upserts; no
    DELETE — the app only overwrites). Until this exists the upload throws and the app shows
    "couldn't upload the cover."
  - **Front + back covers** (added 6 Jul 2026): `Edition.back_cover_url` (migration 000010)
    lets a user photograph both sides of a book. Every image picker now offers **camera or
    gallery** (`showImageSourceSheet`) and crops before upload. The **add-book form** has
    front + back cover slots (2:3 crop; new books upload to `covers/<uuid>.jpg` and carry the
    URLs in the create payload; edits PATCH the edition); the **book page** shows a back-cover
    thumbnail under the front and uploads to `<editionId>-back.jpg`. Only the front cover is
    cached for the offline grid; the back shows on the book page only.
  - **Author portraits & publisher logos reuse the same `covers` bucket** (added 6 Jul 2026):
    the author/publisher "add new" pickers now let users pick+upload a photo instead of
    pasting a URL (`pickAndUploadCatalogImage`, `catalog_image_upload.dart`), stored under
    `authors/<uuid>.jpg` / `publishers/<uuid>.jpg`. The Storage policy is bucket-scoped
    (`bucket_id = 'covers'`), so these prefixes need **no extra owner setup**.
- **Add-book form UX pass (6 Jul 2026):** help text under Series / Book № and the author
  field (co-authors are added one at a time via repeated picks — already multi-author);
  the ISBN field carries a **Scan** button that opens the barcode scanner in `returnResult`
  mode (`Routes.catalogScanResult` → `IsbnScanScreen(returnResult: true)`) and prefills the
  whole form from the OpenLibrary lookup, every field still editable; author/publisher
  pickers show most-used **suggestions** on a blank search via `GET /catalog/browse/{authors,
  publishers}?sort=popular` (order by work/edition count); primary-language is now a fixed
  dropdown (`kCatalogLanguages`) instead of free text.
- **Phase 3 not yet verified with a real signed-in device run.** The sync engine's
  logic is thoroughly unit-tested (in-memory Drift + fake API client covering
  push/pull/conflicts/idempotency), and the app boots cleanly on an Android emulator
  with all the new tables/workmanager/providers wired in — but no session has driven
  it through a real Google sign-in to see the S5/S6 screens live or done a literal
  airplane-mode check on a device. Needs the owner's own account.
- **S5 library grid doesn't filter by personal tag yet** — tags can be created and
  assigned from S6, but the grid's filter chips are only status + favourites. Small
  follow-up, not a redesign.
- **Ticker animation for overflowing generated-cover titles not built** (S5/S6
  mockups) — plain text ellipsis for now; a pure polish item.
- **No dedicated conflict-history viewer** — `conflict_history` rows are written
  correctly (delete-wins/LWW) but there's no screen surfacing them yet; `[WIRED]`
  per CLAUDE.md rule 6, same pattern as the activity log.
