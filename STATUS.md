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

**Last updated:** 10 Jul 2026

---

## Snapshot

Solo-built personal library app, pre-launch but feature-complete on the v1 slice.
**Phases 1–8 are all built** — real Google + Apple sign-in on a real Supabase project,
a real Railway deployment at a custom domain co-located with the DB in Singapore
(~0.2s/request), a full OpenLibrary-backed shared catalog (works/editions/authors/
publishers/genres/series) with cache-on-first-use, and a full offline-first personal
library (Drift source of truth, a sync engine ported from rupee-diary: push/pull,
idempotent, delete-wins/LWW conflicts). On top of that: the **lending ledger** (lent +
borrowed, due reminders, rejected-loan handling, return reminders), **cross-user
connections + loan mirroring** (the first social layer), **FCM push** (connection +
lending events, opt-in), **CSV import/export**, **insights/stats**, **opt-in LLM
recommendations**, **share cards**, and **launch plumbing** (version gate, backups,
icons/splash, privacy/terms). The landing page is live and public.

**Shipping state:** the mobile app now has release builds — an iOS **IPA (build 26)**
and an Android **AAB (build 26)** — and is in **Play Store internal testing**; a
TestFlight build exists in App Store Connect. **Still worth a real device pass:** a
literal airplane-mode Layer-2 check and on-device verification of FCM push + the ISBN
scanner (the scanner can't build on an Apple Silicon iOS Simulator). The sync engine is
thoroughly unit-tested (in-memory Drift + fake API client).

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
  authors/editions and its own independent rating pool, linked to the original
  via a shared `translation_group_id` (decided 5 Jul 2026) plus, since 21 Jul 2026,
  a directed `works.original_work_id` self-FK (which side is the original) and
  translator credits on the `work_translators` join table (translators are Author
  rows — same catalog pages). A separate, read-time-only
  `translation_group_rating` field averages across the whole group for display
  ("4.2 across all translations") without merging the underlying per-translation
  pools. Full UI shipped 21 Jul 2026: "Translated from" + Translator on the add
  form (original picked from the catalogue or stubbed in place, four fields,
  catalogue-only), "Add a translation"/"Link existing" on the original's book
  page, and the duplicate-match fork (shelf copy / new edition / translation /
  different book) on the add form's similar-title panel.
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

**Lending connections — the consent layer** (added 6 Jul 2026): the first cross-user
feature, pulling forward the `[LATER]` peer-to-peer social layer (feature-map.md line 99).
New server-side `connections` table (migration `000012`: requester_id, addressee_id,
status pending/accepted/denied, unique pair, RLS enabled) — cross-user and **online-only,
not synced** (like `Profile`; the offline sync engine stays strictly per-user Layer 2).
`/connections` API: `POST` (request, or auto-accept if the other already asked — idempotent),
`GET` (incoming/outgoing/accepted), `POST /{id}/accept`, `POST /{id}/decline` (deny/cancel/
disconnect — either party, resendable), `POST /{id}/block` + `/unblock` (migration
`000013` adds `blocked_by`). A declined request can be **re-sent** (reopens to pending)
until the recipient **blocks** it (terminal); mutual requests **auto-accept**. Auth
required on all (`connection_service`, 9 tests).

**Push notifications (FCM)** (added 7 Jul 2026): first push pipeline. `device_tokens`
table (migration `000014`, RLS) + `POST/DELETE /devices`. A tiny FCM HTTP v1 sender
(`fcm_client`) using only PyJWT + httpx — **no firebase-admin dependency** — mints a
service-account JWT, caches the access token, and POSTs `messages:send`; dead tokens
auto-pruned. Fires (via FastAPI `BackgroundTasks`, off the response path) on connection
request received + accepted. **Opt-in like recs** (CLAUDE.md rule 8): dormant unless
`FIREBASE_CREDENTIALS` (the Firebase Admin service-account JSON) is set in the API env —
now set in Railway. Firebase project `kitabi-in`; iOS + Android apps (bundle/package
`in.kitabi.kitabi`); APNs `.p8` key uploaded. App: `firebase_core`/`firebase_messaging`,
token registered with `/devices` on sign-in (cleared on sign-out), taps open the
connections inbox; `GoogleService-Info.plist` added to the Runner target, `google-services`
Gradle plugin, `aps-environment`/`remote-notification` wired. **Follow-up:** book
returned/due pushes (need sync-engine hooks + a scheduler job) — infra is ready. App: lending
to a Kitabi user fires a connection request on save (best-effort, offline-safe); the ledger
shows a **Request pending → Linked** pill per lent card and a badged connections inbox
(`ConnectionsScreen`, `/connections`) to approve/deny; once accepted, future lends to that
user auto-link. **No push notifications yet** — approvals surface via the pull inbox, because
FCM-send from the API would need a new Firebase service-account credential (CLAUDE.md rule 8);
push is the natural follow-up.

**Cross-user lending** (added 7 Jul 2026): loans now flow between connected readers.
When you lend to an **accepted connection**, the server **mirrors** it onto the borrower's
account — a linked `direction='borrowed'` record (`lend_mirror_service`, correlated by
`linked_loan_id`, gated on `connection_service.are_connected`, run *after* the lender's sync
op commits so a mirror failure never rejects the loan; tracks returns/soft-deletes; 3 tests).
It pulls to the borrower via the normal cursor and appears on their **Borrowed** shelf. New
`GET /catalog/editions/{id}` → the Work for an edition, so the borrower's app can hydrate a
borrowed book it never added (`cacheBorrowedBooks`). App: a separate **Borrowed section** in
the library (slate "FROM X" band), and tapping a connection opens a **per-connection loans**
screen (lent to / borrowed from them). Also this session: progress card page-count fix
("p. 50 of 109", not "of 50"), and a warning before lending a book you're currently Reading.

**Reader languages** (added 7 Jul 2026): `profiles.preferred_languages` (JSONB list, migration
`000015`) on `/me`. Captured in a one-time onboarding step after sign-in (router gates on it —
re-asks until ≥1 is set, server-side so it follows the account across devices), editable in the
profile. The add-book language dropdown now lists the reader's languages first (falls back to the
full list) with a "manage in profile" note. Also this session: the transient "Syncing…" pill was
removed (routine sync is silent; only the *error* banner remains), and the full-screen book page
got a back button that falls back to Home when there's nothing to pop.

**Sync correctness pass** (7 Jul 2026): lending changes now land on the other side
promptly, both directions. App: every repository mutation fires the sync trigger the
moment it enqueues (`Repo.onMutation` → `syncTriggerProvider`) instead of waiting up to
15 minutes for workmanager; `SyncEngine.syncNow` coalesces a trigger that arrives
mid-sync into a follow-up pass (the old `??=` guard silently dropped it); pull-to-refresh
on the library grid and all three ledger tabs runs a real push+pull round trip
(`syncNowProvider`). API: returns are now **bidirectional** — a borrower's "I've returned
it" reflects `returned_date` onto the lender's record (guarded: only the loan's named
`borrower_user_id` can reflect back) and pushes `lend_returned`; an existing mirror keeps
receiving the lender's returns/edits/deletes even after the connection is dropped (the
gate applies to *creating* a mirror, not keeping the pair in step); no born-deleted
mirrors; mirror failures are logged instead of swallowed. Fixed a 500 that killed a whole
push batch when a cross-device conflict snapshotted a row with plain `date` columns
(`_row_to_dict`). New coverage: two-user HTTP round-trip tests (`test_lend_sync_e2e`),
reverse-reflection/spoof-guard/disconnect mirror tests, and app-side coalescing +
onMutation tests.

**Sync hardening, second pass** (7 Jul 2026, same day): a full-surface defect sweep.
App: the outbox (`sync_queue`) is now **user-scoped** (schema v3 adds `user_id`; the
drain only pushes the signed-in reader's ops, so an account switch racing a sync can
never push one account's edits under another's JWT); a push rejected with
`deleted_wins` now **soft-deletes the row locally** (the pull that carried the delete
was skipped by the pending-op guard and rejected ops bump no seq — the push result is
the only signal); a partial/malformed push response can no longer **hang the drain
loop** (unanswered ops cost an attempt and error out after 5). API: migration `000016`
adds a **partial unique index** `uq_lending_mirror_pair (user_id, linked_loan_id)` —
dedupes then makes the concurrent-push duplicate-mirror race impossible (the create
retries into the update path on conflict); creates now **validate referenced-row
ownership** (a lending record/tag assignment hung off another user's library entry is
rejected `invalid_reference` — the FK alone only proves existence); unlinking a loan
(`borrower_user_id → null`) now **retires its mirror** (soft-delete + seq bump) instead
of leaving a frozen "with you" row on the former borrower's shelf.

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

| **Firebase (FCM)** | Push notifications only (no other Firebase product) | Project `kitabi-in`; iOS + Android apps, bundle/package `in.kitabi.kitabi`; APNs `.p8` **Production** key uploaded | `GoogleService-Info.plist` (iOS) + `google-services.json` (Android) in the app; API sends via FCM HTTP v1 with `FIREBASE_CREDENTIALS` (service-account JSON) set in Railway — no `firebase-admin` dependency |

Deliberately **not** using: any paid metadata API (open decision), Redis/queues
(cost rule — CLAUDE.md rule 8), and no Firebase product beyond FCM push.

---

## Deployment — live URLs

| What | URL | Hosted on | Notes |
|---|---|---|---|
| Landing page | https://kitabi.in | Cloudflare Pages, git-deploy from `landing-page/` on push to `main` | Live, public. `/b/:id`, `/a/:id`, `/p/:id` are served by Cloudflare **Pages Functions** (`landing-page/functions/`) that inject real Open Graph tags (cover/title/blurb) server-side, so shared links preview richly in iMessage/WhatsApp/Slack — bots don't run the pages' client JS. Humans still get the JS-rendered page. Book pages show the back-cover photo (when the owner photographed one) and both covers open in a dependency-free lightbox (8 Jul 2026). **Universal / app links live (22 Jul 2026):** the `.well-known` association files finally carry real values (Apple Team ID `62686X3746`; three Android SHA-256s — Play app signing, upload key, local debug), and `_headers` forces `application/json` on the extension-less `apple-app-site-association`, which Cloudflare otherwise serves as `octet-stream` and iOS silently rejects. Verified: Google's Digital Asset Links accepts all three fingerprints, and an Android device reports `kitabi.in`/`www.kitabi.in` **verified**. Note both caches lag a change — Apple's CDN up to ~24h, Google's ~1h — and iOS only re-evaluates the association at **install**, so a device must reinstall after a fix |
| API | https://api.kitabi.in | Railway service `kitabi-api`, proxied CNAME via Cloudflare (Full strict) | Live; auth/profile + catalog endpoints (incl. global search + author/publisher create). CORS now allows `kitabi.in` for the public share pages |
| API (origin, fallback) | https://kitabi-api-production.up.railway.app | Direct Railway domain | Keep working in case the custom domain ever breaks |
| Mobile app (iOS) | — | TestFlight | Release **IPA build 26** (`app/build/ios/ipa/kitabi.ipa`, App Store distribution) built via `scripts/build_ipa.sh`; a TestFlight build exists in App Store Connect. Deployment target 15.5. `mobile_scanner`'s MLKit can't build on an Apple Silicon iOS Simulator (no arm64 slice) — verify the scan screen on a real iPhone/Android. APNs **Production** key required for TestFlight push |
| Mobile app (Android) | — | Play Store internal testing | Release **AAB build 26** (`app/build/app/outputs/bundle/release/app-release.aab`) via `scripts/build_aab.sh`, uploaded to Play Console internal testing. Google-managed app signing (upload key local at `~/keys/kitabi-upload.jks`, gitignored). R8 minification off (was stripping WorkManager/Firebase registrars) |

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
| 2 — Shared catalog | Books/authors/publishers/series, ISBN scan, Work vs Edition | **✅ Done** — OpenLibrary-backed, cache-on-first-use, migration `000003`, `GET /catalog/search`, `GET /catalog/isbn/{isbn}`, `POST/PATCH /catalog/works`, `PATCH /catalog/editions/{id}`, `GET /catalog/authors?q=` + `GET /catalog/publishers?q=` typeahead, author/publisher browse; app has search, ISBN scan, add/edit form (author/publisher are now dropdown-cum-add-new typeaheads; typeset cover previews live as you type), author/publisher browse screens. **Cover-photo extraction (8 Jul 2026):** `POST /catalog/cover-extract` — when a scan finds nothing anywhere, the form's photographed front/back covers (our bucket URLs only) go to Claude vision (Haiku) and title/authors/publisher/blurb/series/language come back to prefill *empty* fields ("Fill in from photos" button; description is now an editable form field persisted on the Work). Same optional `ANTHROPIC_API_KEY` gate as recs — dormant/no bill when unset; live output not yet verified (no key set). **Duplicate detection (8 Jul 2026):** migration `000018` (pg_trgm + GIN trigram indexes) and `GET /catalog/works/similar?title=` — typo-tolerant near-match ranking (`similarity`/`word_similarity`/ILIKE, all index-served, any script); the add-book form shows a quiet, debounced, dismissible "Already in the catalog?" panel under the title (create mode only) so duplicates get caught before they're created. **Fuzzy global search (8 Jul 2026):** works/authors/publishers search is typo-tolerant + relevance-ranked on the same trigram indexes (migration `000019` adds publishers); ISBN stays exact, CSV import matching stays strict; the app debounces the network call (300ms) while the on-device library section stays per-keystroke. **Cross-script search (8 Jul 2026):** "Kayary" finds "കയർ" and "ചെമ്മീൻ" finds "Chemmeen" — migration `000020` adds romanized twins (`works.title_translit`, `authors.name_translit`, `publishers.name_translit`; `indic-transliteration` ITRANS + `anyascii`, backfilled + GIN-trigram-indexed), ORM event hooks (`models/translit_hooks.py`) keep them in sync on every write path, and search/duplicate-detection also match the romanized query (`pg_trgm.word_similarity_threshold` relaxed to 0.45 per-transaction — cross-romanization pairs like "thakazhi"/"takazhi" score ~0.56). Post-create the add form shows an "Added to the catalog" popup (metadata + Add to library → Adding… → Added ✓ / Create another / Close). **Wiki-style moderated edits (8 Jul 2026):** the book page's new "About this book" section (subtitle + description) carries an "Improve this entry" action into the edit form; `PATCH /catalog/works/{id}` now applies live only for the work's contributor (or unowned/imported works) and otherwise queues a `work_revisions` row (migration `000021`, RLS deny-by-default) — `GET /catalog/revisions/pending` + approve/reject endpoints power the profile's "Pending edits" inbox; the editor gets "Edit sent — the reader who added this book will review it". V1 approver = contributor; proper moderation later. **Author self-claims queued (22 Jul 2026):** "This is me" no longer writes `authors.linked_user_id` — it was hidden entirely (2fccf1f) as an unverifiable edit to shared catalog data, and is now back behind an approval queue. Both paths (the add-author checkbox and the button on an existing author) file a pending `author_claims` row (migration `000029`, RLS deny-by-default); the claimant alone sees a "Pending review" notice via a per-request `claim_pending` flag, every other reader keeps seeing the old value. `catalog_service.approve_claim` is the only writer of the link and is **manual for now** — no endpoint, no admin screen yet |
| 3 — Personal library + sync engine | Drift schema, sync queue, push/pull, status/notes/tags/ratings/reviews | **✅ Done** — migration `000004`, `POST /sync/push` + `GET /sync/pull`, delete-wins/LWW conflict rules, `[WIRED]` activity log; app has S5 library grid + S6 book detail (status/progress/notes/rating/review/lending/tags), workmanager + connectivity-triggered background sync. **Rate & review page (8 Jul 2026):** dedicated full-screen editor (big stars + roomy text + visibility toggle, one Save) replacing the old cramped dialog — opened in one tap from the S6 review card; marking a book Read shows a one-off self-dismissing snackbar prompt to review, only if the book has no rating/review yet; the add-book description field opens an "Edit full screen" text editor. **Cover viewer (8 Jul 2026):** tapping a cover photo on the book page opens a full-screen swipeable front/back viewer (pinch-zoom, night scrim, page dots) — editing moved to the small camera badge only, so viewing never opens the picker. **Cover uploads capped (8 Jul 2026):** every photo pick/capture goes through `pickImage(maxWidth/Height: 1600, quality: 85)` — uncapped 12MP camera covers made messaging apps drop the og:image link preview and left the share-card preview blank while the multi-MB JPEG decoded; the share sheets also now wait (bounded 6s) for the cover to decode before rasterising the card. Covers uploaded before the cap stay large until re-photographed. ISBN scan "Add" now creates a library entry (was a no-op that only popped the scanner). Sync engine verified via unit tests (mocked API, in-memory Drift), not yet via a real signed-in device run |
| 4 — Lending | Lend/borrow records, linked vs self-logged, due reminders | **In progress** — Slices A–C: Lending ledger (S8) with **Lent out** and **Borrowed** tabs (Out now / With-you-now / Returned, computed due stamps, mark-returned / "I've returned it"). Borrowed side via migration `000005` (`direction`/`edition_id`/`linked_loan_id`/`note`, nullable `library_entry_id`); log-borrowed sheet (S8c, inline catalog search); S9 lend bottom sheet; **due-date local reminders** (`flutter_local_notifications`, on-device, scheduled 9am on the due date, cancelled on return — firing not yet device-verified). Cross-user mirroring live (lend_mirror_service): a loan to a linked reader fans a `borrowed` mirror onto their account (and returns reflect both ways). **Lending/connections batch (8 Jul 2026):** accepting a connection now **backfills** loans that predate it (first-lend flow: request → accept → the borrower's shelf fills in; both the accept endpoint and the mutual-request path); Borrowed tab counts active loans only; notification taps survive cold start (pending external target consumed by the router redirect — also hardens kitabi.in app links); Connections gains a **Private contacts** section (free-text borrowers with open-loan counts, "Link" re-attaches all their records to a picked account + sends a request) and open-loan counts on accepted cards; the lend sheet's borrower field offers "Keep as a private contact" explicitly; footer Lending item badges pending requests (chain: footer → ledger header → inbox); ledger header shows at-a-glance chips (N out / N overdue / N with you); **global Search moved from the bottom nav to the Home and Library headers** — six equal row slots put the Add button off the true center line, so the nav is back to the S3 five-slot layout. The "+" is a flat tile in the middle slot (five equal slots → middle centre IS the screen centre, asserted in shell_nav_test). A centerDocked FloatingActionButton was tried and reverted (9 Jul 2026, owner report): the FAB floats above every modal bottom sheet, so "+" punched through on top of the lend sheet's own button; a regression test now opens a sheet and asserts the tile is covered. **Home + Insights rework (8 Jul 2026):** Home greets by name (time-of-day, /me full_name) with a diary date line, shows a "Fresh on your shelf" strip of the newest covers standing on a gold shelf line, a reading-goal slip (opens Insights), and a first-run 1-2-3 Scan/Shelve/Lend intro instead of a bare empty state; Insights adds avg-pages/most-read-author/longest-book superlatives, a daily rotating "Did you know" reading fact, and a fresh-user layout (settable goal ring + fact + what-grows-here preview) so day-one readers get something engaging. **10-item UX batch (9 Jul 2026):** disk-cached covers (cached_network_image + a 1500-object/60-day LRU cache behind every remote image); "I got this book" one-tap wishlist→shelf move; searchable lend pick-book sheet; the library grid's lending band now derives from the reactive ledger stream (instant); footer tabs reset to their branch root (goBranch initialLocation); ledger header search; **the public layer v1**: profiles public by default (migration `000022`, backfilled), `GET /users/{id}/profile` + `GET /users/{id}/library` (double-gated on profile+library visibility, private ≡ not-found), a READERS section in global search, and an in-app public reader page (avatar, score/shelf-count chips, Connect, their public shelf); the profile screen shows the account picture |
| 5 — Import | Goodreads/CSV import | **Core done** — `import_service.parse_csv` (Goodreads + generic, fuzzy columns; unit-tested) + `POST /import/preview` (parse + local catalog match by ISBN/title). App S2 screen: paste CSV → preview matched/unmatched → import matched into the library (status/rating/review), offline-first. CSV **export** via `buildLibraryCsv` + share_plus from the profile. Follow-ups: native file picker (paste for now — file_picker's Android plugin conflicts with the SDK toolchain), and create-if-missing (OpenLibrary fetch) for unmatched rows |
| 6 — Insights & search | Dashboard, stats, filters, author/publisher browse | **Core done** — **bottom-nav shell** (Home · Library · [+] · Lending · Insights, `StatefulShellRoute`) + the real **S3 home dashboard** (currently-reading with page progress, gold-edged lending nudge, 2×2 shelf-count cards). AI pick deferred to Phase 7. **global search (S4)** — library-first (offline Drift) then catalog (API); **Insights/stats (S10)** — reading-goal ring (device-local goal), year selector, books/pages/reading-now stats, and a dependency-free books-per-month bar chart from a pure `computeInsights`. **filter sheet (S4b)** — library grid filters by status/language/type/genre/favourites with a live count, all served offline from the cached-book mirror (Type = `works.form`, added 16 Jul 2026), plus a single-select **Shelf** row from personal tags (17 Jul 2026). **Library shelves view + floating controls (17 Jul 2026):** an All books ⇄ Shelves toggle on the library grid — shelf tiles (statuses, Favourites, personal tags, "+ New shelf") with fanned standing covers, tap-to-open as a filtered grid — and the header scrolls away in favour of an oxblood `ExpandingFab` that fans into Search / Filter (badge) / Sort. Phase 6 core complete; follow-ups: S10 language donut + pages/month line, S4b year facet |
| 7 — Recommendations & share | LLM recs, per-book + personal share cards | **Core done** — **share cards (S6c/S13)** (`BookShareCard` → PNG via `RepaintBoundary` + `share_plus`, include-my-rating toggle, from the book page) and **LLM recommendations (S11)**: `GET /recommendations` reasons picks from the reader's ratings via Claude (gated behind an optional `ANTHROPIC_API_KEY` — dormant/no bill when unset), opt-in S11 screen with a "why" per pick, always-visible off switch, + Wishlist / Not-for-me, and a quiet "For you" home card. Live LLM output not yet verified (no key set) |
| 8 — Launch plumbing | Version gate, backups, app icons, store listings, privacy policy | **Mostly done** — version gate (426 + update screen), Supabase keep-warm job, nightly encrypted R2 backup workflow, privacy + terms pages, Railway deploy + custom domain + app icons/splash all ✅. Remaining: store listings + store badges (pre-submission) |

All 19 v1 screen mockups exist in [docs/kitabi_screens.html](docs/kitabi_screens.html),
audited against feature-map.md so every `[V1]` feature has a designed home before it's built.

---

## Recent milestones

- **19 Jul 2026** — **The reading status/session cards merge into one, with a
  proper reading log** (owner pick "B" from a 3-option mockup). One `_ReadingCard`
  now carries the status pill, a gold→oxblood progress bar, started + inline edit,
  and Start-a-session / manual-log; its footer opens `showReadingLogSheet` — a
  scrollable, day-grouped log with a week sparkline, each sitting's time/pages/
  duration, and a delete for stray micro-sessions (`deleteSession`, soft +
  synced). Verified on the emulator (card, log, live delete). 119 tests green.
- **19 Jul 2026** — **The book page's shelf section becomes a little bookcase**
  (owner pick "B" from a 3-option mockup). The bare "SHELVES · yours only" +
  "＋ add" chip row is now a ribboned card — gold bookmark edge, shelf name in
  Fraunces, a fan of the shelf's other books on a gold ledge (the same
  miniature bookcase the Shelves wall uses), a live "This copy + N others"
  count, and Move / Remove actions; the empty state quiets to "Not on a shelf
  yet · Choose a shelf". Reflects one-book-one-shelf. Verified on the emulator
  (move updates the card live, remove drops to the empty state). 119 tests green.
- **19 Jul 2026** — **Total-page capture fixed across every progress path**
  (owner report: on a book with no page count, typing the total while logging
  never reached the book or the cloud, and progress stayed blank). One shared
  `saveBookTotalPages(db, api, editionId, total)` (mirror locally + PATCH the
  Edition) now backs all four entry points, and a total field was added where it
  was missing — the **manual-log sheet** and the **progress editor** (pencil)
  had none. The reading timer's own save was reading the edition id off a
  stream provider that hadn't emitted on that route (so it silently dropped the
  total); it now looks the entry up directly (`libraryEntriesDao.getById`).
  **And the book page's `libraryEntryProvider` was a one-shot fetch** — the
  timer's save landed in Drift but the page kept showing the stale entry
  (progress "—") because only the manual-log path hand-invalidated it; it's now
  a reactive stream (`watchByEditionId`), so a write from *any* path refreshes
  the page live. Result: the total saves to the local mirror + syncs to the
  catalog, and progress shows its percentage immediately from every entry point
  (verified end-to-end on the emulator, incl. the timer wax-seal face). 119 tests green.
- **18 Jul 2026** — **Shelving a book becomes a proper two-way picker** (owner
  report: couldn't select a shelf you'd made from the book page, and an empty
  shelf was a dead end). Two sheets (`shelf_sheets.dart`): from a book, "Add to
  a shelf" lists every shelf with a tap-to-toggle checkmark + a New-shelf door
  (replacing the type-the-exact-name dialog); from a shelf, an empty personal
  shelf shows an "Add books to this shelf" button — and the same action rides
  the floating control while any personal shelf is open — opening a picker of
  the whole library to shelve/unshelve. `libraryTagsProvider` is now a stream so
  chips/checkmarks update live. 113 tests green, verified on the emulator.
- **18 Jul 2026** — **The catalogue (Discover/browse) becomes a bookshop wall.**
  The Books tab is now a three-across grid of standing covers on gold ledges
  (title/author caption, corner quick-add badge), the same "cool" Apple
  Books-style treatment the owner asked for. The tall header (back + title)
  steps back on scroll and snaps back on scroll-up while the Books/Authors/
  Publishers tabs stay pinned (`NestedScrollView` — floating/snap `SliverAppBar`
  over a pinned tab bar). The old inline sort/language/type/genre dropdown row
  is gone; search + filter moved to the shared `ExpandingFab` (Search on every
  tab, Filter with an active-facet badge on Books, opening the facets as a
  bottom sheet). Facets stay server-side (the list is paged). Authors/Publishers
  keep their row tiles. All in `browse_screen.dart`; 111 tests green, verified
  on the Android emulator.
- **17 Jul 2026** — **The library grows a Shelves face and its controls learn to
  float** (owner picks from the mockup rounds: expanding button + S1 shelf
  tiles). The library grid gains an **All books ⇄ Shelves** segmented toggle
  (choice persists per device via KeyValues): the Shelves face is a 2-up wall
  of tiles — one per non-empty reading status, Favourites, then every personal
  tag A–Z and a gold-bordered "+ New shelf" — each with up to three fanned
  standing covers on a gold ledge and a live count; tapping a tile opens that
  shelf as a filtered grid (back arrow + shelf name replace the header).
  Shelves are the existing synced personal tags (rule 18) — no schema change,
  no backfill. The header now scrolls away entirely; search/filter/sort moved
  to a new `ExpandingFab` (core widget): a single oxblood circle that fans
  into labelled Search / Filter / Sort mini-buttons with a gold active-filter
  badge visible even collapsed, honouring reduced motion. The filter sheet
  gains a single-select **SHELF** chips row so a personal shelf composes with
  every other facet, and the grid gains explicit sort (Recently added default /
  Title A–Z / Author). Verified end-to-end on the Android emulator (toggle,
  tiles, open-shelf, fan, filter-with-shelf, create-shelf).
  form restaged** (release **build 63**). `works.form` (API migration `000026`,
  mirrored into Drift `cached_books.form`, schema v6) is a closed vocabulary
  (`WORK_FORMS`: Novel / Short stories / Poetry / Memoir / …) — one per work,
  deliberately *not* a genre, because Malayalam publishing organises by form first
  (നോവൽ, ചെറുകഥ, കവിത) and the library filter needs it as a clean facet rather than
  something fished out of genre tags. The filter sheet (S4b) gains a Type row that
  works offline; the cover-extract vision prompt can suggest a form (gated to the
  vocabulary, so a creative answer drops rather than prefills). The add/edit form
  (S7b) is restaged in three acts — capture strip first (scan + photograph, both
  full-width; the scanner used to hide as an icon inside the ISBN field ten fields
  down), then the essentials (cover, title, author, language, Type, Genre — the
  last two one-tap chip rows, since they drive the filter), then everything else
  folded into a "More details" disclosure that auto-opens on edit or after a
  prefill (announced by a gold provenance banner). Save is a sticky bar.
  **Sync fixes shipped alongside:** duplicate library entries for one edition are
  merged by a post-pull heal (`library_dedupe.dart`) instead of crashing the book
  page's Yours tab with "Bad state: Too many elements"; pull now applies
  `ownership` and `reading_sessions` (both were silently dropped — a borrowed book
  came back "owned" on a fresh install, and reading history never restored); and
  `start_date`/`finish_date` go on the wire date-only, so reading dates actually
  sync. The book-page byline lists every author, not just the first.
- **10 Jul 2026** — **Reading sessions (timed logs), pulled forward from the v1.5
  parking lot into v1 (owner request), plus a Home + Insights rework to match.**
  A new syncable `reading_sessions` table (API migration `000023`, Drift schema v4)
  wired into the generic sync push/pull registry alongside ratings/reviews; the live
  "timer running" state stays device-local (KeyValues-backed, survives an app
  restart mid-session) and only becomes a synced row once stopped — only one session
  runs app-wide at a time, starting a new one auto-stops and logs whatever was
  running. The book page gets a "Reading Session" card (Start + a recent-sessions
  log) that opens a full-screen pocket-watch view — a real sweeping hand via
  `AnimationController`, an "in the zone" badge past 20 minutes — and stopping shows
  a wax-seal confirmation (session minutes, this-week total, an optional page-number
  field) before returning to the book page. A persistent mini-bar in `ShellScaffold`
  follows a running session across every tab, with its own quick-stop (skips the
  wax-seal ceremony on purpose — that's reserved for the watch face itself). Two
  rounds of HTML mockups (a first pass judged "too literal/gimmicky" and "not modern
  enough," a second modern-app-instincts pass the owner picked) led to reworking Home
  as "The Stat Wall": the goal slip became an oversized editorial hero number, the
  four shelf-count cards flattened from a bordered 2×2 grid into one typographic row,
  the fresh-covers strip dropped its skeuomorphic shelf-line/shadow, and
  currently-reading cards went dark (mini-player styling) with a live gold dot when
  their session is the one actively running. Insights gained a gradient area chart of
  the week's reading minutes per day, a this-week-vs-last-week delta, and one
  plain-language observation derived from session timestamps ("You read most on
  Wednesdays, often around 9–10 PM"). Verified with dedicated unit tests
  (`ActiveSessionController`, `computeReadingTimeStats`) and a full widget-test flow
  (start → watch face → stop → wax seal → back on the book page); not yet verified
  live on an emulator (flagged explicitly rather than skipped silently)
- **9 Jul 2026** — **Book page redesigned as "the Frontispiece"; every shelf gets one
  card system ("Grid B").** Mocked before building — three hero directions for the
  book page, then a separate card-system mock (one cover frame + a state-overlay
  vocabulary + two grid finishes) — owner picked Direction A (Frontispiece) and Grid
  B (pure shelf, no caption). The book page's old flat grey header is now
  `_Frontispiece`: a gradient wash of the book's own derived colour, a large
  front+back cover, a genre eyebrow, serif title, tappable author/publisher, one
  compact meta line (year · pages · language), an aggregate rating cluster, then the
  reader's own star row. A gold-rule "❦" divider (`_TheBookDivider`) now separates
  "your copy" from the shared catalogue record — every existing section (status,
  progress, review, public reviews, notes, tags, lending, about, editions,
  translations, buy links) carried over unchanged, just reframed either side of the
  divider. New shared `ShelfCover` widget puts a book's state (status pill, reading
  sliver, favourite ribbon, lent/borrowed band) as overlays directly on the cover
  with no caption row — wired into the library grid, its Borrowed section, and a
  public profile's shelf, so a book looks identical everywhere it's listed;
  `TypesetCover` gained `accentFor`/`tintFor` so the grid and the book page's hero
  derive the same colour from a book's title/author. Also fixed: `PersonLink`
  (lender/borrower names) now opens a linked user's public profile instead of a
  ledger-only screen — the ledger is still the profile's default tab, one tap away;
  an unlinked private contact still opens the old ledger screen. Verified live on
  the emulator across the library grid, the book page, and profile navigation.
- **9 Jul 2026** — **Book page rework, round 2 (mocked and owner-approved before
  building) — supersedes the "❦"-divider layout above.** Fixed a hero tint bug
  (`TypesetCover.tintFor`): the old version forced lightness to a flat 0.9 while
  halving saturation, so a muted cover (e.g. a faded photo scan) washed out to
  nearly nothing — now clamps a saturation floor (0.32) and a lower lightness
  ceiling (0.80). The hero gained a solid "spine rail" colour bar on its left edge
  and a filled (solid-background) genre chip. The reader's own star rating moved
  out of the hero entirely into the "MY REVIEW" card (above the review body); the
  hero now shows the *community* rating instead — aggregate stars + average +
  review count, live-computed from every `Rating` row on the Work (the old
  `Work.aggregate_rating` column was dead — nothing ever wrote to it) — as one
  plain (no link styling) tap target that jumps to the About tab. The "❦" divider
  became a YOURS / ABOUT segmented tab bar. The old 5-button status row merged
  into one status+progress card with a "Change ›" tap target opening a bottom
  sheet to switch status. Readers' reviews rebuilt: a sort chip (Newest / Highest
  rated / Lowest rated, client-side, no extra fetch), a rating-distribution bar
  chart (from all ratings, not just reviewed ones — new `PublicReviewsPageOut` API
  shape wraps `reviews` + `rating_average`/`rating_count`/`rating_distribution`), a
  "no rating" label for star-less reviews, and a client-side "Show N more
  reviews" reveal past the first 5. Verified via a targeted widget-test regression
  (real Flutter layout engine, not just a smoke check) plus the full 71-test suite
  and `flutter analyze`; the regression test caught and fixed a real
  `_RatingDistribution` overflow (5 stars at 14px overflowed the old 62px-wide
  label column by 8px — widened to 78px) and confirmed the rating-above-review
  ordering in the review card.
- **9 Jul 2026** — **Reader profile redesigned as a "bookplate" (mocked before building).**
  Three rounds of HTML phone-frame mocks (owner-reviewed) landed on the "Card Ledger"
  direction: `PublicProfileScreen`'s header is a gold-hairline-inset card (Ex Libris
  eyebrow, gold-ringed avatar, real name), with the @handle appearing exactly once — in
  the app bar. Connection standing reads as a rotated corner stamp (moss "Connected",
  gold "Waiting for them to accept") or a single in-plate action button (Connect for a
  stranger, Accept+Deny for an incoming request, Resend for a declined one, Unblock for a
  blocked one); the destructive/rare actions (Disconnect, Block, Cancel request) moved
  off the plate into a top-right ⋮ menu that renders only when there's such an action.
  Score/Books/Read/Links are a ruled stat row inside the plate; the tabs are a counted
  segmented control (Ledger · N / Shelf · N), Ledger-first. The Shelf search was upgraded
  to the **advanced** cross-script search (the lend picker's pattern: 300ms-debounced
  transliteration-aware books-only catalog search, unioned by work id) so a Latin query
  finds a Malayalam-titled book on their shelf. Verified live across all connection states.
- **9 Jul 2026** — **Public reviews + a connection count on the profile.** New
  `GET /catalog/works/{id}/reviews` (`review_service.public_reviews`) is the first
  cross-user read of Layer-2 data — every reader's review is otherwise synced only to
  its own owner, so this is a deliberate, narrow carve-out: visible-only
  (`Review.visible`), each paired with that same reader's star rating for the book if
  they left one (a naked rating with no public review never surfaces — feature-map.md
  marks public ratings `[LATER]`, this doesn't pull that forward). Reviewer identity is
  resolved fresh on every call, never denormalized onto the review row: a public
  profile shows its real name and avatar, a private one shows a stable `User_XXXXXX`
  placeholder derived from the user id (same placeholder every time, so repeat reviews
  from an anonymous reader read as one consistent voice) — and it flips to the real
  identity on the very next fetch the moment they make their profile public again, with
  nothing to invalidate. The book detail page's new "WHAT READERS ARE SAYING" section
  lists these; a public reviewer's row opens their `PublicProfileScreen` (and from
  there, a connection request), a private one isn't tappable at all. Separately,
  `GET /users/{id}/profile` gained `connections_count` (`connection_service
  .count_accepted`), now a 4th cell on the profile's stats card.
- **9 Jul 2026** — **Connections becomes a roster; every connection action moves onto
  the profile page.** Follow-up to the same-day profile merge below. The Connections
  screen no longer carries any inline action buttons (Accept/Deny/Block/Cancel/Resend/
  Disconnect/Unblock) — every real-account row is now a plain person card (real avatar
  photo via a new `avatar_url` on `GET /connections`'s `other` object, falling back to
  an initial; a trailing chevron; no buttons) that opens `PublicProfileScreen`, where
  `_ConnectionActions` renders the right action set for every connection state (not
  just Connect/accepted like before) and keeps working even when the visited profile
  is private — accepting a request never depended on seeing their shelf. Private/
  unlinked contacts are the one exception (still a "Link" button; no profile to open).
  On the profile page itself: the Score/Books/Read counts moved into a bordered,
  icon-per-cell stat card instead of plain pills; the tab order flipped to Ledger-first
  (that's what most visits are for) with the Shelf tab now using `Icons.shelves`; and
  the AppBar's global-search icon was dropped in favor of a search box inside the Shelf
  tab, filtering the already-fetched shelf locally by title/author. Verified live on
  the emulator: accepting an incoming request from the profile page moved the person
  from "Requests to approve" to "Connected" on the Connections list with no navigation.
- **9 Jul 2026** — **Public profile rework: one screen, Instagram-inspired.** Merged
  `PublicProfileScreen` and the connection ledger into a single screen — previously the
  profile pushed to a second `ConnectionLoansScreen` for "Lending ledger", and the
  AppBar title duplicated the same full name shown in the body. Now the AppBar carries
  only `@username`; the body shows the name once, an avatar + 3-stat header row (Score /
  Books / Read, Instagram-style bold-number-over-caption), a Connect / pending / green
  "Connected" status pill, and a two-icon Shelf/Ledger tab bar that swaps content inline
  (no navigation — verified via back-stack depth on the emulator). A search icon in the
  AppBar opens global search. `LoanRow` and the counterparty loan filter were extracted
  from `ConnectionLoansScreen` (kept standalone only for private/unlinked contacts, who
  have no profile) so the row UI has one implementation. Connections' accepted-card tap
  now lands directly on the merged screen; the interim "View their library" icon button
  (added earlier the same day) is gone — redundant once the row tap goes to the one
  screen that has both tabs.
- **9 Jul 2026** — **Follow-up UX batch.** The lend pick-book sheet's search now unions
  its instant local substring filter with the books-only catalog search endpoint
  (`catalogSearchProvider`, transliteration-aware, 300ms debounced), matched by `workId`
  — a cross-script query finds a book you own the same way global search does, without
  ever blocking offline. Accepted-connection cards in Connections gained a **"View their
  library"** book-icon button opening `PublicProfileScreen` (shelf grid + "View loans")
  — previously that screen was reachable only via reader search, which requires the
  target to have set a username, so a connected friend with a public library had no
  discoverable path to actually be seen. The visibility toggle → API → DB chain was
  already correct end-to-end; the missing entry point was the real bug. Verified live
  on the Android emulator with seeded data for both flows.
- **7 Jul 2026** — **Full documentation pass.** Every source file (61 API `.py`,
  91 app `.dart`) now carries a module-level docstring/header; three new/refreshed docs:
  [docs/build.md](docs/build.md) (build/run/ship steps for all three parts),
  [docs/architecture.md](docs/architecture.md) (deep technical architecture + a
  file-by-file map of the whole tree), and this STATUS refresh. No code changed.
- **7 Jul 2026** — **Lending ledger filter + return reminders** (release **build 26**).
  The "Lent out" count is now active-loans-only (returned books drop out). A new
  **Rejected** tab surfaces still-out loans whose borrower declined the connection —
  the lender can **re-send** the request or **make private contact** (unlink the Kitabi
  user via `LendingRepository.updateBorrower` → a sync op that clears `borrower_user_id`;
  `LendingRecordUpdate` now accepts it). Connected borrowers can be nudged with a
  **Remind** push: `POST /connections/remind` (gated on an accepted connection) →
  `notify_return_reminder`. 3-tab ledger (Lent/Rejected/Borrowed). API 97 + app 30 tests
  green; both IPA + AAB built at build 26.
- **7 Jul 2026** — **Android Play Store internal testing.** First AAB release build
  (`scripts/build_aab.sh`, upload keystore + `key.properties`, Google-managed signing);
  fixed a launch crash from R8 stripping WorkManager/Room + Firebase/MLKit registrars
  (minification off), and a chain of compileSdk bumps (→36) with a plugin override.
- **7 Jul 2026** — **FCM push + cross-user lending.** First push pipeline (`fcm_client`,
  no `firebase-admin`; `device_tokens` + `/devices`; opt-in via `FIREBASE_CREDENTIALS`)
  firing on connection request/accept and book lent/returned/reminder. Loans now
  **mirror** onto a connected borrower's Borrowed shelf (`lend_mirror_service`). Reader
  **preferred languages** (`profiles.preferred_languages`, onboarding gate). See the
  Architecture section above for the full write-ups.

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
