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

**Last updated:** 4 Aug 2026

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

**Shipping state: LIVE ON BOTH STORES — Google Play 31 Aug 2026, App Store
1 Sep 2026.** Android is public at
<https://play.google.com/store/apps/details?id=in.kitabi.kitabi> (package
`in.kitabi.kitabi`); iOS is public at <https://apps.apple.com/app/id6787361959>
(app id **6787361959**, "Kitabi - Beyond the Bookshelf", version 1.0 from build
**136**). Both were cut from the `main` that carries the device-safe migration
rework (`71a3b2e` — the v12 rebuild would have wedged every install upgrading
from ≤v11; do not ship anything older). **Both store URLs are facts the site
depends on** — they are the constants `PLAY_STORE_URL` and `APP_STORE_URL` in
`landing-page/functions/_lib/components.js`, which every server-rendered page's
app band reads; `landing-page/app.html` carries the same pair by hand (hero CTA,
closing band, FAQ, and the `installUrl`/`downloadUrl` in its JSON-LD). The App
Store link deliberately carries **no country segment**: Apple resolves
`/app/id…` to the visitor's own storefront, and this site's readers are in India
and its diaspora both. The inert-badge branch in `storeButton` stays — a store
without a URL renders as a `<span>` that says so, because a reader must never
learn which button works by tapping it. Complete listings live in `docs/store/{android,ios}/`: copy, keywords,
App-Privacy answers, and framed screenshots (Play phone/tablet sets; App Store
iPhone 6.5″ 1284×2778 + iPad 13″ 2048×2732, generated 26 Aug against the production
API — regeneration recipe in `docs/store/ios/listing.md`). Privacy policy discloses
in-app promotions as of 25 Aug 2026. Promotions verified end-to-end on-emulator
(serve → render → click-navigation → dismiss → telemetry), pubspec at `0.1.0+137`
(next cut: 138). **Open while review runs:** the nightly
backup secrets (`BACKUP_DATABASE_URL`/`BACKUP_PASSPHRASE`/`R2_*` — still unset per
`gh secret list`, 26 Aug: the workflow silently self-skips, owner action before first
real user data); the real-device pass (airplane-mode Layer-2 check and the ISBN
scanner — never yet run on real iOS hardware; push is already confirmed arriving on
the owner's iPhone, 26 Aug, which also settles the once-listed "APNs production key"
item: the `.p8` Production key has been in Firebase all along, see the integrations
table). **Done on Android approval (31 Aug 2026):** the landing
page's "Launching soon" badges became the real Play link — which also surfaced that
`/app`, linked from every public page's header and footer, had been a 404 since the
reference site took `/` over: the marketing page was still deployed but unreachable
(Pages 308s `/index.html` to `/`, which a Function renders). It is `app.html` served
at `/app` now. **Still open:** release the iOS rollout and bump pubspec when App
Store Review clears.

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
| `app/` | Flutter — Riverpod (`flutter_riverpod` ^2.6.1, hand-written providers; `riverpod_generator`/`riverpod_annotation` **removed 14 Aug 2026** — nothing used them and they pinned `analyzer` to 7.x, which broke `build_runner` on Dart 3.13), go_router ^14.6.2, **Drift ^2.22.1 (full schema: 12 tables — 7 syncable Layer 2 entities, sync_queue/sync_state/conflict_history/key_values, and a denormalized cached_books offline read cache)**, Dio ^5.7.0, supabase_flutter ^2.8.0, sign_in_with_apple ^6.1.0, flutter_secure_storage ^9.2.2, google_fonts ^6.2.1, flutter_svg ^2.0.0, **workmanager ^0.9.0 (now wired: 15-min background sync)**, mobile_scanner ^6.0.2 (ISBN scan), image_picker ^1.1.2 + **image_cropper ^9.0.0 (crop picked images to grid before upload)**, connectivity_plus (sync-on-reconnect trigger), **flutter_local_notifications ^18.0.1 + timezone + flutter_timezone (on-device lending due-date reminders)** | iOS deployment target **15.5** (bumped from 14.0 — `mobile_scanner`'s MLKit requirement); SDK `^3.12.2`. `image_cropper` (UCrop) needs a `<activity com.yalantis.ucrop.UCropActivity>` in AndroidManifest.xml (added); on iOS it resolves via Swift Package Manager automatically (verified: release IPA built clean 6 Jul 2026) |
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
| `landing-page/` | **The public book site** — every page rendered at the edge by Cloudflare Pages Functions (`functions/_lib/`, plain template literals, no framework and no `node_modules`), plus the legacy `/b/` `/a/` `/p/` share links, which now 301 to their canonical slug URLs | **Live** at kitabi.in — all 14 page types, 1,195 URLs in the sitemaps. Plan: [docs/web-platform-plan.md](docs/web-platform-plan.md), mockups: [docs/web-mockups.html](docs/web-mockups.html). The author page as a reference page is designed but **deferred** — [docs/author-page-plan.md](docs/author-page-plan.md), [docs/author-mockups.html](docs/author-mockups.html) |
| `api/` | FastAPI backend | **Live** at api.kitabi.in — auth/profile + shared catalog (search, ISBN lookup, add/edit, author/publisher browse) |
| `app/` | Flutter mobile app | Auth flow + library-first home + catalog screens working (global search across library/books/authors/publishers, ISBN scan → adds to library, add/edit form with author/publisher **picker pages**, author/publisher browse, shareable book/author/publisher links) + personal-library grid & book detail |
| `etl/` | OpenLibrary → curated catalog seed pipeline: bulk-dump path (01–04) + live-API per-language seed job (07) | Live-API job run against prod: 100 books × 14 languages (13 Indic + India-focused English), covers included |
| `infra/cloudflare/` | Edge protection for the kitabi.in zone, as code — `rate_limits.py` (idempotent, dry-run by default) + README | **Written, not applied.** Needs a Zone→WAF→Edit token; the Actions `CLOUDFLARE_API_TOKEN` is Pages-scoped and must not be widened |
| `docs/` | Mockups, design tokens, task checklist | — |

---

## Integrations & external services

| Service | Purpose | Account / project ref | Configured in |
|---|---|---|---|
| **Supabase** | Postgres + Auth (Google, Apple) | Project ref `lwyifccwirfmgdvemgkz`, region Southeast Asia (Singapore), org "Shamsheer AT's Projects" (workspace also holds rupee-diary) | `api/.env` (`DATABASE_URL` = Supavisor transaction pooler, port 6543; `SUPABASE_URL`) |
| **Google Cloud OAuth** | Google sign-in | One **Web application** OAuth client (not Android/iOS native), redirect URI = Supabase's `/auth/v1/callback` | Configured in Supabase → Authentication → Providers → Google |
| **Apple Developer** | Apple sign-in | App ID `in.kitabi.kitabi` (Sign in with Apple capability), Services ID `in.kitabi.kitabi.web`, a Sign in with Apple key (Key ID + Team ID `62686X3746`) | Supabase → Authentication → Providers → Apple. Secret JWT regenerated via `api/scripts/gen_apple_secret.py` (expires ~6 months — no automation for this yet, see Open decisions) |
| **Railway** | API hosting | Project `kitabi-api`, service `kitabi-api`, connected to `shamshi-at/kitabi.in` (branch `main`, Root Directory `api`) for git-based auto-deploy. **A push to `main` is a production deploy**, via Railway's own GitHub integration — invisible in `.github/workflows/` and never shown by `gh run list`, and not gated on CI going green | `api/railway.json` (Dockerfile builder, `/healthz` healthcheck); env vars set directly in Railway dashboard (not in repo). **The Dockerfile migrates on boot** — `CMD` is `alembic upgrade head && uvicorn …`, so every deploy *and every restart* applies pending migrations to the production DB |
| **Cloudflare** | DNS (kitabi.in), landing page hosting | `api` CNAME → Railway target (proxied), SSL/TLS Full (strict); Pages project `kitabi-in` for the landing page | DNS: Cloudflare dashboard (manual). Pages deploy: `.github/workflows/deploy.yml`, secrets `CLOUDFLARE_API_TOKEN`/`CLOUDFLARE_ACCOUNT_ID` |
| **GitHub Actions** | CI (lint/test/build checks only — not deployment) | `shamshi-at/kitabi.in` | `.github/workflows/api-ci.yml`, `app-ci.yml`, `admin-ci.yml`, `deploy.yml` (landing only) |
| **Railway (admin)** | Admin console hosting (`admin.kitabi.in`) | Same Railway project; a **second service** pointed at the same Supabase DB. Root Directory = repo root, Dockerfile `admin/Dockerfile` (bundles `api/app`), config `admin/railway.json`. **Live and serving** — verified 5 Aug 2026: `admin.kitabi.in/healthz` → `{"status":"ok"}`, root 303s to sign-in (this row previously said "not yet created in the dashboard", which was stale). Which Railway project owns it is not recorded here — only `api/` is linked locally, so the dashboard is the authority | `admin/railway.json` (Dockerfile builder, `/healthz`); `ENV=production` flips the Secure cookie flag. Deliberately does **not** run alembic — it shares the API's database, and one migrator is the point |

| **IndexNow** | Telling Bing/Yandex/Seznam/Naver a new book page exists | No account, no key exchange, no bill — ownership is proved by serving `kitabi.in/9b4aeafec5fe4eeaba383d6eb42bee5a.txt`. **Google does not participate.** Fired on book create for works that clear the content floor | Key + endpoint in `api/app/services/indexnow.py`; key file at `landing-page/<key>.txt` (must stay in `[[path]].js`'s ASSET_FILES **and** deploy.yml's copy list); enabled by `ENV INDEXNOW_ENABLED=1` in `api/Dockerfile` |
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
| Mobile app (iOS) | https://apps.apple.com/app/id6787361959 | **App Store — public, live 1 Sep 2026** (app id 6787361959, version 1.0) | Shipped as **App Store version 1.0**, from IPA build **136** — submitted 31 Aug, approved 1 Sep 2026. The store's marketing version is 1.0 while pubspec reads 0.1.0; they are different numbers and only the store's is public. Build notes from the 126 cut, all still true of the tooling: (`app/build/ios/ipa/kitabi.ipa`, 33 MB, `app-store-connect` export, signed *Apple Distribution: Shamsheer A T (62686X3746)*, both extensions embedded) built 14 Aug 2026 via `scripts/build_ipa.sh`. The number is **not** pubspec's `+125`: Flutter's export options set `manageAppVersionAndBuildNumber`, so Xcode increments past whatever App Store Connect already holds — pubspec is a floor for iOS and authoritative only for Android. Verified after build: `CFBundleVersion` 126 and all three `--dart-define`s present in the Dart snapshot (`strings Payload/Runner.app/Frameworks/App.framework/App` — they live there, not in `Runner`, which is what makes the 6 Jul "unconfigured IPA" bug invisible to a casual check). Deployment target 15.5. `mobile_scanner`'s MLKit can't build on an Apple Silicon iOS Simulator (no arm64 slice) — verify the scan screen on a real iPhone/Android. APNs push confirmed working on a real iPhone (26 Aug 2026) |
| Mobile app (Android) | https://play.google.com/store/apps/details?id=in.kitabi.kitabi | **Play Store — public, live 31 Aug 2026** | Release **AAB build 126** (`app/build/app/outputs/bundle/release/app-release.aab`, 79 MB) built 14 Aug 2026 via `scripts/build_aab.sh`, **upload pending** — 124 was uploaded first and Play then rejected the rebuild as a duplicate `versionCode`, which is what a store number is for. Verified after build: `versionCode` 126 / `versionName` 0.1.0 in the merged manifest, `jarsigner -verify` → *jar verified* with signer SHA-256 `1C:EE:94:5E:…:86:A1` (the upload key, not a debug fallback), and all three `--dart-define`s present in `base/lib/arm64-v8a/libapp.so`. Toolchain note: the Android SDK now lives at `~/Library/Android/sdk` (the Homebrew `android-commandlinetools` install belongs to a different macOS user and is read-only, so `sdkmanager` exits 0 while installing nothing). Google-managed app signing (upload key local at `~/keys/kitabi-upload.jks`, gitignored). R8 minification off (was stripping WorkManager/Firebase registrars) |

Redeploy the API by pushing to `main` (Railway auto-deploys); no manual `railway up`
needed anymore. Redeploy the landing page the same way (push to `main` touching
`landing-page/**`).

⚠️ **So `git push origin main` ships the API to production, migrations included** —
there is no separate release step, nothing to approve, and CI does not gate it. The
container's start command is `alembic upgrade head && uvicorn …`, which has three
consequences worth holding on to: a migration merged to `main` reaches the
production database within about a minute; a migration that *fails* takes the start
command with it, so the health check fails and Railway restart-loops rather than
serving a half-migrated API; and a migration must therefore be safe against the
**previous** version of the code, which is what serves traffic while the new image
rolls. The landing page is the safe one — Cloudflare Pages only, no database.

---

## Environments & secrets

Secrets live in exactly two places, never in the repo:
- **`api/.env`** (gitignored) — local dev database URL, Supabase URL. Copy from `api/.env.example`.
- **Railway dashboard env vars** (production) — `DATABASE_URL` (Supavisor pooler), `SUPABASE_URL`,
  `ENV=production`, `SCHEDULER_ENABLED=true`, **`AMAZON_ASSOCIATE_TAG=kitabi0b-21`** (set
  8 Aug 2026 — Associates India account live). Optional, not set: `CUELINKS_CID` (wraps the
  generated Flipkart link in Cuelinks' Link Kit redirect — Flipkart's direct programme is
  closed to new publishers, so this is the only route) and the legacy
  `FLIPKART_AFFILIATE_ID`. All three are plain URL params, not credentials; unset means the
  link renders untagged rather than disappearing.
- **GitHub Actions repo secrets** — `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` (landing page deploy only; API deploy doesn't go through Actions).
- **Apple's `.p8` private key** — kept locally outside the repo (used only to run `api/scripts/gen_apple_secret.py` when the OAuth secret needs regenerating); never committed.

---

## CI/CD

Mirrors rupee-diary's pattern exactly (see that project's own CI for comparison):

- **`api-ci.yml`** (paths: `api/**`) — ruff, black, pytest against a real `postgres:17-alpine`
  service container, **pip-audit (blocking as of 31 Aug 2026** — see Security posture below),
  `docker build`.
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

### Security posture

Post-launch audit, 31 Aug 2026 (Android live; iOS was still in review then, approved 1 Sep). What was checked
and what it found:

- **SQL injection — not possible.** Every query is SQLAlchemy expression API or
  a `text()` with bound parameters; the only f-strings in raw SQL interpolate
  hardcoded association-table objects (`merge_works`), never input. Filter and
  sort params are `Literal`/regex allowlists (`^(title|year_desc|…)$`). Verified
  live against the deployed API: classic, UNION, stacked, and **time-based blind**
  (`pg_sleep`) payloads on `/catalog/search`, `/public/search`, `/public/suggest`
  all return literal-text results with no timing signal.
- **Auth — sound.** Supabase JWT verified with PyJWT against the project JWKS,
  asymmetric algorithms only (`["ES256","RS256"]` — HS\* is deliberately absent,
  which defeats the key-confusion class outright), `iss`/`aud`/`exp`/`sub`
  required. Verified live: no-token, garbage-token, and a forged **`alg=none`**
  token all 401. Every mutation route requires `CurrentUser`; unauthenticated
  routes are read-only GETs.
- **Tenancy — enforced.** `/sync/push` validates `entity` against a `Literal`,
  binds `user_id` server-side (never from the payload), and checks ownership of
  both the row and its FK references (`_refs_owned`). Public/cross-user reads gate
  on `profile_visible` / `library_visible` with defense in depth at each read.
- **SSRF — closed.** Cover extraction only accepts URLs under our own public
  `covers` bucket (`allowed_image_url`); the paid call is metered
  (`llm_quota.consume`) after every cheap rejection.
- **Rate/cost abuse** — the API is behind Cloudflare (verified `server: cloudflare`
  on `api.kitabi.in`); LLM endpoints are metered per-reader with a global breaker.
  CORS is `GET`-only, no credentials, `Accept` only.
- **Dependency CVEs.** PyJWT bumped 2.10.1 → **2.13.0** (clears 7 auth-path CVEs;
  none were exploitable in our config, but it is the auth library — kept current).
  **pip-audit in CI is now blocking** (was `continue-on-error`), with a documented
  ignore-list for 7 Starlette advisories that survive only because
  `fastapi==0.115.12` pins `starlette<0.47.0` while every fix is `≥0.47.2`. All 7
  are unreachable or low-severity here (no `HTTPEndpoint`, `StaticFiles` only in
  the admin app behind Cloudflare, tiny authenticated form bodies, no host-header
  auth). **Tracked follow-up: bump FastAPI (0.115 → current) to clear the Starlette
  line, then drop those ignores.** Not done autonomously — it is a broad framework
  bump on production and wants its own tested change.
- **Minor / accepted.** `/openapi.json` is public (`/docs` is 404 in prod) — it
  describes shape, not secrets, and every route is already access-controlled;
  worth gating behind admin-only later but not a live risk. No stack traces leak
  (validation errors only, no debug mode).

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
| 6 — Insights & search | Dashboard, stats, filters, author/publisher browse | **Core done** — **bottom-nav shell** (Home · Library · [+] · Lending · Insights, `StatefulShellRoute`) + the real **S3 home dashboard** (currently-reading with page progress, gold-edged lending nudge, 2×2 shelf-count cards). AI pick deferred to Phase 7. **global search (S4)** — library-first (offline Drift) then catalog (API); **Insights/stats (S10)** — reading-goal ring (device-local goal), year selector, books/pages/reading-now stats, and a dependency-free books-per-month bar chart from a pure `computeInsights`. **filter sheet (S4b)** — library grid filters by status/language/type/genre/favourites with a live count, all served offline from the cached-book mirror (Type = `works.form`, added 16 Jul 2026), plus a single-select **Shelf** row from personal tags (17 Jul 2026). **Library shelves view + floating controls (17 Jul 2026):** an All books ⇄ Shelves toggle on the library grid — shelf tiles (statuses, Favourites, personal tags, "+ New shelf") with fanned standing covers, tap-to-open as a filtered grid — and the header scrolls away in favour of an oxblood `ExpandingFab` that fans into Search / Filter (badge) / Sort. **Time to finish (26 Jul 2026):** the reader's own reading pace, measured from timed sittings that recorded a page range, shown on *every* book page (owned or catalogue-only) as hours / sittings / weeks — with the actual + a calibration line on a finished book — plus a time-to-finish facet on the library filter. Not a crowd average: the shared figure stays locked until enough readers have logged pages. Phase 6 core complete; follow-ups: S10 language donut + pages/month line, S4b year facet |
| 7 — Recommendations & share | LLM recs, per-book + personal share cards | **Core done** — **share cards (S6c/S13)** (`BookShareCard` → PNG via `RepaintBoundary` + `share_plus`, include-my-rating toggle, from the book page) and **LLM recommendations (S11)**: `GET /recommendations` reasons picks from the reader's ratings via Claude (gated behind an optional `ANTHROPIC_API_KEY` — dormant/no bill when unset), opt-in S11 screen with a "why" per pick, always-visible off switch, + Wishlist / Not-for-me, and a quiet "For you" home card. Live LLM output not yet verified (no key set) |
| 8 — Launch plumbing | Version gate, backups, app icons, store listings, privacy policy | **Done (31 Aug 2026)** — version gate (426 + update screen), Supabase keep-warm job, nightly encrypted R2 backup workflow, privacy + terms pages, Railway deploy + custom domain + app icons/splash, store listings, and **store badges**: the landing page and the public web platform's app band carry both real store links (Play from 31 Aug, App Store from 1 Sep 2026). The inert-badge branch stays in `storeButton` for the next platform announced before it ships — a store with no URL renders as a `<span>` that says so, never a link that goes nowhere. Fixing the badges also revived `/app` itself, which had 404'd on every page's "Get the app" link since the reference site took `/` |
| 9 — In-app promotions | Banner + card on Home, admin composer, audience targeting | **✅ Built end-to-end (31 Jul 2026)** — design in [docs/promotions-plan.md](docs/promotions-plan.md), mockups in [docs/promotions-mockup.html](docs/promotions-mockup.html). First-party only: **no ad SDK, no advertising identifier, no ATT prompt, no new bill**. Migration `000034` adds `promotions` / `promotion_contents` / `promotion_events` (RLS deny-by-default) plus `profiles.promotions_opt_out`. `GET /promotions` resolves **server-side** — targeting applied, language variant chosen, dismissals and caps honoured, one per placement, ETag→304 on the usual poll; `POST /promotions/events` takes a batch idempotent on device-generated ids. Targeting: languages (from `profiles.preferred_languages`), platform (new `X-Platform` header), app-version range, account age, library size, reading status, genres, explicit reader ids, rollout %, exclusions — unknown facts fail *closed*. **Content variants are a separate mechanism from targeting**: one campaign carries per-language copy (null = default), so a Malayalam promo reaches Malayalam readers *in Malayalam* without a duplicate campaign. Deliberately **no geo targeting** (no location stored, and adding one means a bill or fingerprinting). Console gains a **Campaigns** section (editor+): list grouped by derived state, four-tab composer with a live phone preview, audience builder with a live estimate + narrowing bars, schedule/frequency, per-variant results, one-tap Stop now, full audit trail. App caches into Drift (`CachedPromotions`) so Home renders offline and an ended campaign expires on-device; its own append-only outbox (`PromotionEventQueue`), **not** the sync queue. Reader opt-out switch in Profile filters at the API. Verified on an Android emulator: both surfaces render, dismiss is instant and DB-backed, and the campaign→console→device round trip works |
| W — Public web platform | kitabi.in as a book reference site ("IMDB for books"): edge-rendered pages, search, hubs, lists, SEO | **Live (4 Aug 2026)** — plan in [docs/web-platform-plan.md](docs/web-platform-plan.md), 14 mocked page types in [docs/web-mockups.html](docs/web-mockups.html). The whole site is now **server-rendered at the edge** by the Cloudflare Pages Functions that were already there — no framework, no build step, no `node_modules`, no new bill (rule 8 holds). `functions/_lib/` is plain template literals: `html.js` (escaping by default), `css.js`, `api.js` (one page-shaped `/public/*` call per page + Cache API), `layout.js`, `components.js`, `jsonld.js`, `handler.js`, `pages/*`. Live: home, search, browse, book, author, publisher, series, genre + language hubs, translation index, 10 editorial lists, reviews, and the two directories. **Verified against production, not just tests:** a Googlebot request to an author page returns full book content in the `<body>` at 750 ms TTFB with `Person` + `BreadcrumbList` + `ItemList` JSON-LD (previously the body was the string *"Opening the book…"*); an unmatched URL is a real 404 rather than a 200 of stale marketing copy; **1,195 URLs are in the generated sitemaps** (796 works + 347 authors + 52 publishers, `/sitemaps/index.xml`), gated by the content floor rather than dumping all 1,402 works. Also shipped under W: stable `slug` columns with a backfill job and `/b/:uuid` → slug 301s; **cross-type ranked search** (banded EXACT/PREFIX/ALL_WORDS/SOME_WORDS scoring in `search_rank.py`, with a matcher floor so ranking can never return less than the matcher found) plus a typeahead; self-hosted brand fonts and a cover proxy; **771/772 hotlinked covers copied into our own Supabase `covers` bucket**; and **duplicate-entity merging** via a `merged_into_id` pointer (never a delete, so old URLs 301 and a merge is reversible) — an hourly exact-match auto-merge folded **28 authors and 53 publishers**, with the ambiguous rest queued for human review in the admin console. Still open: Lighthouse CI, `Cache-Control` on the public catalog GETs, app-side 429/503 handling, an edge→origin shared secret (**must land before more edge routes, or the per-IP rate limit throttles the edge itself**), genre classification (**still 0 works with a genre**, so the genre hubs remain thin), descriptions for the top 300 works, and submission to Google Search Console / Bing Webmaster |
| A — The author page | Wikipedia-model author pages: infobox, awards, sourced facts, `sameAs` | **Designed, deferred (4 Aug 2026)** — kept as a future plan, not scheduled. Nothing in it is time-sensitive: Wikidata is not going anywhere, the P648 match only gets better as the catalogue grows, and the work ahead of it (genres, descriptions, Search Console) is what actually makes the site rank. Full design done — plan in [docs/author-page-plan.md](docs/author-page-plan.md), six mocked states in [docs/author-mockups.html](docs/author-mockups.html). The live author page already renders the four catalogue-derived blocks (works, publishers, decade bar, stats); everything a *reference* lookup wants — dates, birthplace, awards, a lead paragraph, outbound identifiers — is missing, and **1,159 of 1,162 authors carry an OpenLibrary id**, which Wikidata records as property P648. So authors can be enriched by **identifier match, not name match** (no wrong-person risk), from a CC0 source with no API key and no bill. Verified against `Q546044` live: dates, birthplace, 6 occupations, **4 awards**, a Commons portrait (fixes the 74% with none), native-script labels in 8 languages (which the catalogue mostly lacks), and 14 Wikipedia sitelinks. Two hard rules the design turns on: **an LLM never sources a biographical fact about a real person** (the catalogue is full of living writers), and **every fact is stored with its provenance** — so where sources disagree the page says so (Wikidata really does hold *two* birth years for Thakazhi, 1912 and 1914) and where we know nothing the block disappears rather than printing "Unknown" |
| M — Kitabi Supporter | ₹149/yr membership, the gold **seal**, admin-granted complimentary memberships | **Designed 9 Aug 2026** — plan in [docs/supporter-plan.md](docs/supporter-plan.md), 13 mocked areas (app, public web, admin console) in [docs/supporter-mockup.html](docs/supporter-mockup.html); checklist is Phase M of [docs/tasks.md](docs/tasks.md). The second revenue line from [docs/revenue-plan.md](docs/revenue-plan.md) §3.2, with the price now fixed: **₹149/year, annual-only, one SKU** (~₹127 net after the 15% store cut; break-even is ~200 supporters against the ~₹25–30k/yr running cost). Two design decisions carry the whole thing. **The badge is a *Supporter seal*, not a verified tick** — "Verified" stays reserved for identity (`authors.linked_user_id` / `author_claims`), because Kitabi's wedge is readers handing each other *physical books* and a purchasable vetting-shaped mark is a real harm, not a branding quibble; hence the standing rules that no seal ever appears on a lending surface, the seal is tappable everywhere onto a sheet stating what it *isn't*, and absence is never marked. And **the subscription is bought and managed in the app on both stores** (owner decision, 9 Aug 2026), so the membership is bound to the Kitabi account and renews itself rather than depending on an admin — `in_app_purchase` (not RevenueCat: new service, new bill), one annual SKU, and **the server writes every entitlement only after verifying the receipt** (Apple's StoreKit 2 JWS verifies offline against Apple's roots; Google via `subscriptionsv2.get`), idempotent on a unique `(source, store_txn_id)` with `store_original_id` unique **across users** so one store subscription can't light up two accounts. One asymmetry is worth knowing before someone reaches for parity: **Apple's renewal notifications are a plain HTTPS webhook, Google's need a Cloud Pub/Sub topic — so Google gets polled** by the APScheduler job that already exists, and no new service is added. Admin-granted complimentary memberships stay exactly as designed (that was the other half of the brief), and the public web page describes the membership but never sells it. The in-app ask is a reserved `kind='supporter'` **promotion**, so it inherits Phase 9's targeting, frequency caps, offline dismissal and reader opt-out instead of growing a second nag system — capped at never-before-day-14, ≤3/year, ≥60 days apart, two dismissals = never again, all server-side. Nothing free today becomes paid: lending, library, sync, import and **export** are on an explicit never-list |

All 19 v1 screen mockups exist in [docs/kitabi_screens.html](docs/kitabi_screens.html),
audited against feature-map.md so every `[V1]` feature has a designed home before it's built.

---

## Recent milestones

- **1 Sep 2026** — **Console: a live dashboard, the moderation gaps closed, and a
  handbook inside the console.** Three things, from one question — what would
  somebody who has never seen the code need in order to run this?

  **The dashboard is now a live view** rather than six static counts. A dark
  "reading right now" panel (from `active_reading_sessions`, so it is a real
  number rather than a derived one) refreshes itself every 20 seconds by
  swapping in the same server-rendered fragment that painted it — no JSON API,
  no websocket, and a hidden tab polls nothing. It shows the **count** and
  aggregate shape (how many books, longest sitting) and deliberately **not who
  is reading what**: the first cut listed reader names against book titles,
  which is precisely the reader's private reading progress that the console
  promises everywhere else it never opens, dressed as a dashboard. Six today tiles, four trend
  cards with a direction against the previous equal window, a 7/28/90-day
  growth chart, and two feeds (newest readers, newest catalogue rows with who
  added them). The chart is plain SVG whose geometry is computed in
  `console/insights.py` and unit-tested — the console has no build step and
  takes no chart library. One thing that had to be got right: the four series
  share **one** scale (`spark(peak=…)`), because normalising each to its own
  maximum drew a day of 59 shelvings and a day of 16 reviews both touching the
  ceiling.

  **Two moderation surfaces that never existed.** Every queue in the console
  waited for something to be *flagged* — but any signed-in reader can create a
  work, an author, a publisher or an edition, and photograph a cover straight
  into the public bucket, and all of it is on kitabi.in immediately. So
  `/moderation/incoming` is a **review-by-default** feed of reader
  contributions (newest first, who added them, filterable by kind and period)
  and `/moderation/images` is a grid of the pictures readers uploaded, with a
  Remove that clears the column and puts the URL in the audit log so a mistake
  is undone by pasting it back. "Reviewed ✓" is an audit row rather than a new
  table, so the tick is itself part of the trail. Two asymmetries the queries
  had to respect: `publishers` and `editions` carry no `created_by_user_id`, so
  a publisher shows no contributor and an edition borrows its parent work's.

  **The rest of the gaps.** Readers gained paging, five saved filters and a
  matching count (the list was the 50 newest with no way to reach the 51st, over
  a heading that counted the whole table); a **Hide public profile** action — the
  gentle half of moderation, for an offensive display name, which takes the
  public page, shared library and public reviews down while the reader keeps
  their app; and last-seen plus device platforms on the detail page. The audit
  log gained filters (person, period, free text) and paging over its flat
  200-row cap. **Service health** (`/system`) is the first place the LLM meter
  has ever been visible: today's spend against the global daily cap, per-feature
  14-day trends, the heaviest accounts today, and which optional integrations
  are switched on — a limit nobody can see is a limit nobody notices hitting.

  **The handbook is a section of the console** (`/handbook`), not a document
  somebody has to remember to send: 17 topics written for a non-technical
  operator, role-filtered so nobody reads about a screen they cannot open, every
  heading separately linkable, searchable from the global search box, and
  reachable from a **? Help** button in the top bar of every screen. Content is
  data in `console/handbook.py` with a three-mark renderer that escapes first
  and refuses off-site links.

  Verified by driving the real ASGI app against a seeded local database — 52
  routes rendered, both new write paths exercised, and every new route confirmed
  to bounce a signed-out visitor. 45 admin tests (25 new), lint clean.

- **31 Aug 2026** — **Console: admin names in the audit log, and language/advanced
  filters on the book lists.** The audit log showed an admin *id* fragment
  (`f9947d9f`); it now resolves `admin_id → email` in one batched query and shows
  the local part (`shamshi`, full email on hover), falling back to the id fragment
  only when the account has been removed — the row never vanishes because the actor
  is gone. The catalog worklist (`/catalog`) gains a **Language · Type · Sort**
  filter bar that composes with search, the quality-gap worklists and `added_by`:
  a pure filter (no text query) browses via `catalog_service.browse_works` (SQL,
  300-cap applied to the right rows); a filtered search/gap list is narrowed and
  sorted in Python (bounded lists, one filter vocabulary across every mode). The
  per-entity work lists on **author and publisher detail** get a **language
  filter** (shared `_lang_filter.html`, only shown when the entity spans >1
  language) — series is deliberately left out (a single-language reading-order list
  with inline position editing, where a filter fights the page). Dropdowns
  auto-submit (`requestSubmit`, `data-no-loader` so the nav loader doesn't flash).
  Verified: filter logic against the dev DB (browse language/form, sort, the
  language post-filter), all pages render, 20 admin tests + lint green, Docker
  builds.

- **31 Aug 2026** — **Delete a work in the console — single and bulk, soft, guarded.**
  Catalog cleanup for the junk a bulk seed leaves (malformed rows, wrong-language
  dupes, test entries): a **Delete this work** button on the work page and
  **checkbox + bulk-delete** on the search/worklist (`catalog.html`, a sticky bar
  that admin.js reveals when rows are ticked). Soft delete only (rule 3 —
  `deleted_at` on the work *and* its editions, so it drops out of search, the API
  catalog and the public site; never a hard `DELETE`). The guard is the point:
  a work anyone has **shelved, rated or reviewed is refused** (`_work_footprint`
  → `_delete_work` in `routers/catalog.py`) and pointed at **merge** instead,
  which folds it into the correct row and carries those readers across — so delete
  can never yank a book out from under a reader. Editor+ only, every deletion
  audited (`work.delete`), bulk capped at 200/submit. Verified against the dev DB
  (junk deletes work+editions; shelved and rated works refused, left live) and the
  bulk UI in-browser (select-all/indeterminate, count, empty-submit blocked);
  routes gated (303 to sign-in unauthenticated); 20 admin tests + lint green,
  Docker builds. Follow-up left open: a restore/undo surface (soft delete makes it
  recoverable by an operator today, but there's no UI for it yet).

- **31 Aug 2026** — **The admin console is an installable PWA.** A manifest, a
  minimal service worker (served from `/sw.js` at the root so its scope is the
  whole origin) and full-bleed maskable icons (`admin/scripts/gen_pwa_icons.sh`,
  from `icon-maskable.svg` — oxblood to every edge, so `qlmanage`'s flatten-to-
  white can't bite and every OS mask shape is clean), wired into both `base.html`
  and the sign-in `auth_base.html`. **Installable only — deliberately not offline.**
  The console is server-authoritative: every page is a live DB query and every
  action a POST, so the worker caches *only* `/static/` assets and passes every
  page, POST and cross-origin fetch straight to the network. A cached moderation
  queue is a wrong one, and you can't act offline anyway — offline is meant to
  fail here, loudly. Verified locally: manifest parses (standalone, scope `/`,
  maskable icon), `/sw.js` serves `text/javascript` root-scoped, icons are opaque
  oxblood at 192/512/180, both templates carry the head tags, admin tests + lint
  green, Docker image ships the assets. SW *activation* is unverifiable in the
  embedded preview browser (it refuses registration pre-fetch) — needs a real
  Chrome/Android check on `admin.kitabi.in`. iOS note: an installed PWA there may
  keep its own cookie store, so the admin may need to sign in again inside the
  installed app.

- **27 Aug 2026** — **Reporting a public review is live end to end.** Apple's 2.1
  "Information Needed" reply on the iOS submission asks the review recording to show
  UGC "content reporting and blocking mechanisms" — blocking existed (connections),
  reporting was the half still `[WIRED]`: the `content_reports` table and the admin
  console's uphold/dismiss queue had waited since 24 Jul with no way for a reader to
  file into them. Now: `POST /catalog/reviews/{id}/report` (signed-in only, idempotent
  per reporter while a report is open, own-review refused, already-hidden review a
  quiet success), and a shared `ReportReviewButton` + reason sheet on all three
  surfaces that show another reader's review — book page, series card, public
  profile. Reasons cross the wire as fixed English tokens so the moderation queue
  reads one vocabulary regardless of the reporter's locale. No migration — the table
  shipped in `000031`.
- **13 Aug 2026** — **Series became a real entity, and can be rated in its own right.**
  It was a free-text box that wrote a number onto the *Edition*, which had two
  consequences: a work with two printings had two answers to "which book in the series
  is this?" (the public page picked one with `min()`), and a translation — its own Work
  here — either duplicated the whole ordering under a second series row or lost it.
  **A position in a series belongs to the story**, so membership moved to the Work
  (migration `000043`, backfilled from the editions' lowest number) and is shared by a
  translation group: linking a translation, or setting the series on any member, places
  the whole group at the same number, while a translation that belongs to a different
  *local* series keeps it. The public series page now groups by position — one entry per
  book, the original leading, other languages beside it — and counts entries, not works,
  when deciding it is thick enough to index. Series also gained what Author and Publisher
  already had: cross-script search columns (a Malayalam series name had **nothing** for a
  Latin query to match), a `merged_into_id` pointer so duplicates fold and redirect, a
  primary language and a description — so the existing merge tooling covers it and a stale
  id resolves to the survivor. Picking became possible at all: `GET /catalog/search/series`,
  `GET /catalog/browse/series` with book counts, `POST /catalog/series`, a series filter
  with reading-order sort on browse. Free text still works for the CSV import and the cover
  extractor, which only ever have a string. **The app** replaced the text field with a
  picker (a series read off a scanned cover prefills it and is offered its existing matches
  before it can become a new row) and the book page finally says *"Book 2 of Ponniyin
  Selvan"*, opening the series in reading order — the app had never shown a reader that a
  book was in a series at all. **The console** gained a Series list (the empty rows a typo
  left behind are shown, not hidden) and a detail page that is the curation surface:
  reading order with the number editable in place, add a book by searching, remove, rename,
  merge duplicates — plus the series card on a book's own page. Then, **ratings and reviews
  of a series** (migration `000044`): "the saga is worth reading" and "volume 3 drags" are
  different claims, so a series carries its own pool and the books inside it keep theirs.
  One table per *act*, not per subject — a `CHECK (num_nonnulls(work_id, series_id) = 1)`
  means a row can never mean both or neither, so all sixteen existing queries keep
  excluding series rows by construction rather than by remembering to; the two that don't
  filter got a deliberate answer (a series review counts toward the contribution score and
  appears on the reader's public profile). Drift went to **v12**, rebuilding the ratings and
  reviews tables so `work_id` can be null — the step that touches data already on readers'
  phones, so it has its own test against a real file database, seeded at the v11 shape, and
  that test was confirmed to fail with the migration disabled before being trusted.
  Verified against the running API and rendered through the real web renderer, not only
  fixtures: 5 works → 3 positions on the series page, and a series at 5.0 while a book
  inside it still shows none. Earlier the same session: the duplicate queue became a
  **cluster** review (choose the survivor, fix its name in the same action, fold N at once,
  peek any record's catalog before deciding) and a **buy-links worklist** for editions with
  no curated Amazon link.

- **9 Aug 2026** — **The catalogue knows what its books are: genres and forms, classified.**
  W5's blocker fell. A closed **33-genre vocabulary** now lives in
  `api/app/services/genre_vocab.py` — slug-unique (two names on one slug would shadow a hub),
  deliberately **orthogonal to `WORK_FORMS`** (no "Poetry" genre splitting the Type facet;
  a work is `form=Biography, genres=[History]`, never `genres=[Biography]`) — and
  `etl/08_genre_classify.py` classified all **1,405 works** against it with claude-sonnet-5
  (thinking disabled), **a human between the model and the database**: plan (DB read-only,
  resumable) → review → apply → revert. Confidence honesty is the design: the model may say
  *unknown*, only high+medium apply (637 high / 520 medium; 222 low + 26 unknown stay
  unclassified — an honest blank beats a plausible guess on an indexed page), the parser
  drops anything outside the vocabulary at the boundary (126 drops, almost all form-words
  offered as genres — the orthogonality rule working), apply never overwrites an existing
  form, and every write landed in a **receipt** (`etl/runs/2026-08-09-genres/`, committed)
  that `revert` can undo exactly. The apply-side guard refuses a non-local DATABASE_URL
  without `--production` — the alembic/env.py lesson, applied before it could bite.
  **Result on production: 1,519 genre links (from 1) and 774 forms (from 3).** Spot-checks
  held across languages: Godan → Social fiction, Kumaravyasa Mahabharata → Poetry +
  Mythological fiction, Huckleberry Finn recognised through Hindi romanization, Bhairappa's
  Āvaraṇa → Historical fiction. Genre hubs now have real mass (Literary fiction 229,
  Religion & spirituality 166, History 118, Language & linguistics 72) and the browse
  Genre/Type rows are full on web + app. Cost: ~70 Sonnet calls, well under a dollar, no new
  credential (rule 8 holds). Follow-ups now unblocked/tracked: genre hubs into the sitemap,
  duplicate-work merging (the Kannada spot-check surfaced "Avarana"/"Āvaraṇa" twins).
  Same day, owner feedback on the new browse toolbar — five facet rows ate the first screen —
  folded it behind a **native `<details>` disclosure**: one compact "Filter & sort · N" bar,
  every active facet a removable ✕ chip, zero JS (the server-rendered rule holds; panel links
  are in the DOM either way), verified at desktop + mobile widths against the live payload.
  **Superseded same day by the owner-picked redesign:** "everything is mixed" → three mockup
  directions ([docs/browse-filters-mockups.html](docs/browse-filters-mockups.html)); the pick
  was **C + A's sort** — a segmented sort control (the pick-exactly-one shape, visually distinct
  from filters) plus **one `<details name="facet"> door per facet**, each opening a small
  bar-width popover holding only that facet (rows: name left, count right), native
  one-open-at-a-time via the `name` attribute, still zero JS. An active door says its value
  ("Genre · History"), so the closed bar reads as a sentence; Clear all appears only when
  something is active. 289 edge assertions. **The app got the same doors** (owner request):
  the fab's one-big-filter-sheet is gone (two filter surfaces drift — the 19 Jul lesson) and
  the Books tab carries the bar as a two-row header sliver — segmented sort scrolling inside
  itself, then the four doors, each opening a small per-facet bottom sheet with counts. Two
  on-device catches the widget tests couldn't see: a lazy horizontal ListView never *built*
  the bar's tail (Length, Clear all) — finders, semantics and ensureVisible all blind to it —
  now an eager SingleChildScrollView+Row; and a single scrolling line hid every door behind
  the seg on a 360dp phone, so the bar wraps to two rows exactly like the web's does. Driven
  on the emulator against production signed-out: Genre door → the real 33-genre sheet
  (Literary fiction 229…), pick History → "Genre · History" door + the Thapar/Dalrymple
  shelf. 324 Flutter tests.
- **9 Aug 2026** — **Finding a book stopped being a scroll.** The browse API's facets
  (language / form / genre) existed since the site launched, and the web `/browse` page drew
  none of them — one row of language chips that *left* the page for the hubs, no sort control,
  no genre or type cut at all. Grounded in a search-trends pass first
  ([docs/discovery-trends.md](docs/discovery-trends.md)): the query families readers actually
  type map to two sorts and one facet we didn't have — **`sort=rating`** ("best malayalam
  novels"; live average over the ratings table, rated-before-unrated, ties to the bigger pool),
  **`sort=added`** ("what's new here" — catalogue arrival, distinct from publication year), and
  a **`length` facet** (`short` <200pp / `medium` / `long` ≥400pp over any live edition —
  the #ShortReads query, which none of the incumbents expose as a filter). Both browse
  endpoints (`/public/browse`, `/catalog/browse/works`) take all of it; `count_works` got its
  predicates aligned with the rows in passing (genre matching was case-sensitive on the count
  side only, so `?genre=fiction` rendered books under a "Nothing here" total). The web
  `/browse` now renders the full toolbar — Sort × Type × Genre × Language × Length as
  plain-link chips that **merge into the current query** (every view a bookmarkable URL,
  browse stays `noindex, follow`), facet counts on the chips, active chip marked, and a
  dead-end state that names each active filter and offers to drop exactly that one. The empty
  search page gained the same doors (Top rated / genres / languages / translations). The app's
  filter sheet gained the two sorts and a Length row (server-side like every other facet).
  Found along the way: every `aria-current="true"` interpolated as a template *value* had been
  entity-escaped into `aria-current=&quot;true&quot;` — present, so the `[aria-current]` CSS
  matched and it *looked* right, but assistive tech read a value of literal `"true"` quotes;
  all chip rows now emit it `raw()`, with a regression assertion, and the test harness gained
  the `URLSearchParams` shim JavaScriptCore lacks. **Data caveat, not UI:** the catalogue seed
  carries genres/forms on almost nothing (1 genre-tagged work of 1,405), so those chip rows
  stay thin until the ETL enrichment lands — the rows hide when empty by design. 577 API tests
  (+9), 318 Flutter (+2, and one brittle positional selector fixed), 269 edge assertions
  (+14), lint clean, Docker builds. **Follow-through, same day:** verifying "Top rated" live
  exposed that `Work.aggregate_rating` had **never been written by anything** — five orderings
  (more-by-author, home rails, translation-group averages) and every public WorkCard read
  permanent NULL, so the sort led with the right book and no card could say "★ 5.0".
  `review_service.refresh_aggregate_rating` now rewrites the column inside the same
  transaction as every applied rating sync op (sync is the only writer of ratings), and
  migration `000042` backfills rows rated before the writer existed (data-only, idempotent,
  rounds to 2 exactly like `rating_summary` so page and card can never visibly disagree).
  578 API tests: create → 4.0, update → 2.0, delete-last → NULL, all asserted through the
  real `/sync/push`.
- **14 Aug 2026** — **The toolchain unblocked: a generator that generated nothing was
  holding the SDK back.** `dart run build_runner` crashed on the owner's Flutter 3.47 /
  Dart 3.13 with `Missing implementation of visitDotShorthandPropertyAccess` — the kind of
  error that reads as a corrupt checkout and is really version skew: build_runner parses
  with the **`analyzer` package**, not the SDK's front end, and the resolved analyzer
  (7.6.0, language 3.9) could not parse 3.13 syntax. What held it there was
  **`riverpod_generator`, which produced no output whatsoever** — there is not a single
  `@riverpod` annotation in `lib/`; all five generated files are Drift's, and STATUS.md's
  own stack row had said "codegen not yet used" for months. Removing it (and the equally
  unused `riverpod_annotation`) floated `analyzer` 7.6 → 10.2, `build_runner` 2.5 → 2.15
  and `drift`/`drift_dev` 2.28 → 2.31, and codegen now runs on the owner's own SDK — no
  second Flutter install, no FVM, and **no Riverpod migration**: `flutter_riverpod` stays
  ^2.6.1, since only the dead codegen packages left. The newer analyzer brought one new
  lint (`unawaited_return_in_try_block`) which caught three real shapes in the image-upload
  paths — `return _upload…()` inside a `try`/`finally`, so the temp file was deleted
  *before* the upload it was meant to outlive and a failed upload escaped the local
  `catch`; all three now `return await`. 387 tests green, analyze clean, on Dart 3.13.
- **14 Aug 2026** — **The scan result is a book page now, not a strip.** The scanner
  worked and the moment after it didn't: on a hit, nothing on screen changed except a
  56px card sliding in *below* a still-lit camera, under a grey line of digits. That card
  was dead text — cover, title, author and printing all unreachable — behind a gold button
  reading **"Add"**, which on a screen titled "Add a book", whose other button adds to the
  shared *catalogue*, named neither its object nor its consequence. Three directions were
  drawn ([docs/scan-result-mockups.html](docs/scan-result-mockups.html): the Slip over a
  dimmed camera, the Bookplate, the Ledger for cataloguing a shelf) plus four ways to make
  a result *land*, a rack of labels for the primary, and the four states that aren't
  "found it". Owner picked **B, the Bookplate**: the camera has done its job, so it
  leaves, and the result takes the whole screen in the scanner's own dark palette — cover
  at a size worth looking at, title, author, type · language · year, the catalogue rating,
  the blurb, genre chips, and the translations line the lookup payload already carried.
  **The printing is named on the face of it**, with "N others ›" opening the list in
  place, the scanned one marked and every page count visible: `editions.first` is what put
  a 55-page first printing on a shelf while the reader held a 240-page reprint (13 Aug),
  and a display pick and a pick the reader will *own* are different questions. The primary
  is the book page's own leather plate, `Add to my library` — the plates moved to
  `core/widgets/action_plates.dart` so the scanner and the book page cannot drift the way
  the four progress surfaces did — with `Wishlist` beside it, which is what actually makes
  the primary unambiguous (want vs. have), a full-width **Open the full book page** door
  onto the page that already handles a book you don't own, and *Scan another book* under
  both. **Four outcomes, one object**: found; already-yours (the shelf answers back with
  status and page, and the offer becomes `Open it` instead of a snackbar claiming an add);
  nothing catalogued (M3's copy — says *why* regional printings are thinly listed, and
  carries the ISBN into the form); and couldn't-check, kept deliberately distinct because
  only a real 404 means "no such book" and an offline moment that says "you'd be the first
  to add it" invites the exact duplicate the catalogue exists to prevent — a test asserts
  that screen never says it. Form mode is the same view with one label swapped, and now
  carries the reader's printing choice back as `scanned_edition_id`, so the question is
  asked once. Five orphaned strings deleted with the old card. **Round 2, same day
  (owner request):** the result no longer wears the camera's dark palette — it renders in
  the **app's own theme**, light or dark, because by then the camera has left and what
  remains is a book page. `buildNightOverlayTheme` now wraps only the camera state; the
  private `_night*` constants left the result widgets for `AppColors`; `StatusPill`, the
  genre chips and the progress line are used as themselves rather than re-tinted copies;
  and `PaperPlate.onNight` — added that morning — was deleted with its last caller. The
  scanner had been the single screen that ignored the reader's light/dark setting. **387 app tests green (9
  new), analyze clean.** Not device-verified: `mobile_scanner` can't build on an Apple
  Silicon simulator, so the camera path still needs a real phone.
- **8 Aug 2026** — **Every book page now sends buyers somewhere — and can pay the bills.**
  The first revenue line from [docs/revenue-plan.md](docs/revenue-plan.md) (§3.1): retailer
  buy links are **generated at read time from the ISBN** (`api/app/services/buy_links.py`) and
  merged into the `buy_links` array both read surfaces already rendered, so the live web
  pages and the installed app both gained "Where to find it" content with zero client work.
  Amazon.in resolves to a direct product page — a printed book's ASIN *is* its ISBN-10, which
  `services/isbn.py` (5 Aug) already derives; 979-prefixed and ISBN-less editions degrade to
  a search link, and a checksum-invalid ISBN is never searched (a mis-keyed number finds the
  wrong product — the title at least finds the right shelf). Flipkart gets a search link.
  No API, no credential, no bill (rule 8): the affiliate ids are plain URL parameters
  (`AMAZON_ASSOCIATE_TAG` / `FLIPKART_AFFILIATE_ID`, unset today), so the feature shipped
  dormant-but-useful — links render untagged and earn nothing until the owner's Associates
  account is approved and the tag lands in Railway, with no further deploy. Three honesty
  rules hold the whole thing together: `affiliate: true` is set **only on a link that
  actually pays us** (our tag present — not a contributor's own tag, not an untagged link),
  affiliate links carry `rel="sponsored"` (Google's requirement for paid links), and both
  clients render a disclosure line **only when something pays** — a stored contributor link
  keeps its plain `rel="nofollow"` and triggers nothing. Stored links stay sovereign: they
  lead the list, suppress the generated link for the same retailer family (amzn.to and
  amazon.com short/foreign forms included), and a bare stored amazon.in link gets our tag
  appended at read time — while the JSONB column itself never changes (a write-path test
  proves a client echoing the served shape back can't smuggle `affiliate` into storage).
  567 API tests (+13), 252 edge assertions (+4), 313 app tests, lint clean, Docker builds;
  the rendered rail verified visually against the real edge template.
  **Live the same day:** the Associates India account came through (tag `kitabi0b-21`, set as
  `AMAZON_ASSOCIATE_TAG` on the `kitabi-api` Railway service) — and the first deploy shipped
  the code but served *untagged* links, because a Railway variable typed into the dashboard
  is staged until the change is applied, so it never reached the container. Worth remembering
  as a diagnosis shape: the payload proved the new code was live (the `affiliate` field was
  there) while the tag was absent, which points at config, not at the deploy — confirmed by
  listing the service's variables rather than guessing, and ruled out on `kitabi-admin` too.
  **The installed app needed no release for the links, but does for the disclosure.** The
  app's book page reads `GET /catalog/works/{id}`, which the same serializer feeds, and its
  "Where to buy" section shipped back in `1c12fcb` — so **an already-installed build renders
  the tagged Amazon link on its next fetch** (an added JSON key is backwards-compatible for a
  keyed Map read). The reader-visible disclosure, however, is in today's app commit, so it
  needs a new build; Amazon's Operating Agreement wants the disclosure wherever affiliate
  links appear, so that build must precede the public store release. No real exposure in the
  meantime — the only installs are internal testing / TestFlight. **Built the same day as
  0.1.0 (111)** for both platforms, and verified the hard way: the disclosure string is
  present in the *compiled* binaries (`libapp.so` and `App.framework/App`), not merely in the
  source, and the IPA's `Info.plist` reports `CFBundleVersion 111`.
  ⚠️ **Note the numbering trap this hit:** these three rows said "build 26" for weeks while
  `pubspec.yaml` had moved to `+110`, so a request for "build 27" would have produced an
  artifact *below* what the stores already hold, which both reject. The build number lives in
  `app/pubspec.yaml` and nowhere else — read it there, never from this file.
  **Flipkart needed a different mechanism than expected:** its direct affiliate programme is
  closed to new publishers, so there is no id to append. The reachable route is an aggregator,
  and `CUELINKS_CID` now wraps the *generated* Flipkart link in Cuelinks' Link Kit redirect
  (`linksredirect.com/?cid=…&source=linkkit&url=…`) — chosen because that form is a pure URL
  template, so it needs no snippet, no client JS and no render-time API call; their extension/
  plugin route would have broken the server-rendered and no-third-party-script rules. The
  wrapper is scoped to that one link on purpose (never Amazon, where a direct tag owes no
  middleman a cut; never a stored contributor link, whose merchant may not be in the network),
  and a direct `affid` still wins if this account ever gets one. Unset today, so Flipkart links
  render plain. 572 API tests (+5) after that addition, and the nested-encoding test asserts a
  **round trip** (the redirect must recover the destination byte-for-byte) rather than a
  hand-computed string — which is how it caught that double-encoding a `%` is correct, not a
  bug, and was itself proved non-vacuous against two broken encodings.
- **5 Aug 2026** — **New books now announce themselves (IndexNow).** The gap: a book added to the catalogue got a slug, a server-rendered page and a sitemap entry within the same request — and then nothing happened. Discovery was entirely "wait for a crawler to re-read the sitemap", which on a domain this young is days to weeks. `POST /catalog/works` now fires a single keyless POST to `api.indexnow.org`, which fans out to **Bing, Yandex, Seznam and Naver**. **Google does not consume IndexNow** — that still needs Search Console registration (still open, and it needs the owner's Google account), so a 200 back from this must not be read as "indexed". Free, no account, no new bill or credential: ownership is proved by serving `kitabi.in/<key>.txt`, and the key is **public by design**, which is why it is committed next to the code rather than hidden in a dashboard. Two rules the implementation keeps. It **only announces works that clear the content floor** — a thin work renders `noindex, follow`, and inviting a crawler to a page that tells it not to index is both pointless and a good way to lose the goodwill the protocol runs on; those get picked up later by the sitemap once someone adds a cover or a blurb, which is the same self-healing incentive the floor already creates. And it **can never fail a book create**: the submission is a background task, and Starlette does *not* swallow a background task's exceptions — a fact the tests caught, since the original wiring scheduled `submit()` and leaned on its internal try/except, leaving the guarantee hostage to any future edit above that block. The scheduled function is now `announce()`, whose whole job is to be unable to raise. The two files that must agree — `landing-page/<key>.txt` and the `KEY` constant — are asserted equal by a test, as is the key file's presence in the Pages catch-all allowlist and the deploy workflow's copy list: the catch-all serves an **allowlist**, so a file that exists in the repo and isn't listed 404s in production, and a 404 key file makes every submission fail 403 with no symptom other than nothing ever happening. Production opts in via `ENV INDEXNOW_ENABLED=1` in `api/Dockerfile` (same pattern as the migration guard — readable from a checkout, no dashboard step); off everywhere else, so a laptop never announces pages. 550 API tests (22 new) + 248 edge assertions green, lint clean, Docker builds and both ENV flags verified present inside the image; each guard confirmed by breaking it and watching the right test fail.
- **5 Aug 2026** — **ISBNs are addressable, and the two ISBN forms are finally the same book.** An ISBN is the highest-intent query the site can receive — the person typing it is holding the book — and the site could not win it. The number was on every book page, in the editions table and the "This edition" rail, and that was worth almost nothing: **no URL, title or canonical carried an ISBN**, so there was nothing for the query to rank. `/isbn/<isbn>` now 301s to the canonical `/book/<slug>`, funnelling authority into the real page rather than competing with it, and the book page's meta description ends with `· ISBN <n>` (the blurb clamped to make room). The `<title>` was considered and rejected — it belongs to the title and author, and a number there costs every reader-facing query to win one machine-facing one. `/isbn/*` stays out of the sitemap on purpose: rule 1 of `sitemap.xml` is *list final URLs, never redirects*. The backing endpoint `GET /public/isbn/{isbn}` is **DB-only and never falls through to OpenLibrary** — it is the most public thing on the site, and a crawler walking guessed ISBNs must not spend a third party's quota on our behalf. **The deeper bug was underneath it.** The same book is `8126403454` on a 2005 printing and `9788126403455` on a 2019 one, and every lookup was `isbn = <what the reader typed>` — so whichever form we happened to store decided whether the book could be found at all. Now: lookups expand to every equivalent form (`services/isbn.py`), writes canonicalise to ISBN-13 via a `NormalizedIsbn` schema type applied as a *type* so a new schema can't skip it, and migration `000041` backfills stored rows. All three are needed — normalising writes does nothing for existing rows, and a backfill can never be assumed to have reached every one. Two rules the arithmetic holds to: a **checksum-invalid ISBN is never converted** (converting a mis-keyed ISBN-10 yields a valid ISBN-13 for a *different* book, which nothing downstream could detect) and never discarded either (it is often an edition's only identifier, and `variants` still matches it literally); and **979-prefixed ISBN-13s have no ISBN-10**, so none is invented. Cover extraction now accepts the 10-digit form printed on pre-2007 covers — most of a second-hand shelf — while keeping the 978/979 gate that stops OCR of some other product's barcode prefilling an entry. Two bugs found by the new tests rather than by users: **Goodreads writes an empty cell as `=""`**, two truthy characters, so an empty `ISBN13` column silently shadowed a populated `ISBN` one and the 10-digit column was unreachable for every row that had only that; and the ISBN branch of `search_local` used `scalar_one_or_none`, which would have raised `MultipleResultsFound` the moment both forms existed on two editions. **The public search path had no ISBN test at all** — it does now, including one pinning the `MATCHER_FLOOR` interaction, because an ISBN scores zero against a title and `rank()` discards zeroes: one line stands between ISBN search working and returning nothing. **513 API tests (34 new, from 479) + 248 edge assertions (19 new)** green, lint clean, Docker builds; verified against a real uvicorn + Postgres, both directions, not just the test client, and the migration's collision guard confirmed by removing it and watching the UNIQUE index reject the write. **Production note:** migration `000041` was applied to the live database by a local `alembic upgrade head` shortly before the push, because `api/.env` points `DATABASE_URL` at the Supabase pooler rather than local Postgres. **`alembic/env.py` now refuses a non-local host** unless `ALLOW_PROD_MIGRATION=1` is set, so that exact command exits instead of migrating; the container opts in via `ENV ALLOW_PROD_MIGRATION=1` in `api/Dockerfile`, and a test asserts that line survives (deleting it would restart-loop production at the next deploy). **The deploy would have applied it a minute later regardless**: the API's Dockerfile `CMD` is `alembic upgrade head && uvicorn …`, so pushing to `main` migrates production by design. The accident was the timing, not the outcome. It is data-only — no schema change — and it **converted zero rows**: all six non-13-character ISBNs in production are checksum-invalid or not ISBNs at all (`OL23006158M` is an OpenLibrary key sitting in the `isbn` column), which is exactly the set the backfill refuses to touch. Only `alembic_version` moved, 000040 → 000041.
- **4 Aug 2026** — **Pre-submission audit: the site was not ready for Search Console, and now is.** Submitting a site with known defects only means learning about them slowly, from Google, weeks later — so the audit ran first. **`www.kitabi.in` was serving the entire site byte-identical to the apex at HTTP 200 with `index, follow`**, its own robots.txt and all: a complete duplicate host. Every page's canonical already pointed at the apex so Google would most likely have consolidated the two, but that is not how you want it settled at submission time — a duplicate host splits crawl budget, collects inbound links on the wrong hostname, and makes Search Console two properties reporting on one site. It now 301s from a Pages `_middleware.js`, which is the only thing that can do it: named routes like `/author/[key].js` never reach the `[[path]]` catch-all, so a redirect there would have covered the home page and nothing else. `/.well-known/` is excluded — Apple does not follow redirects for apple-app-site-association, and iOS only re-checks at install, so that breakage would be invisible for weeks and unfixable for anyone already installed. The **static sitemap** was also pointing at redirects (`/privacy.html` and `/terms.html` both 308) and listed **3 URLs total**, omitting every hub the ranking strategy is built on; now 22, all verified 200. Both sitemaps re-checked end to end afterwards: **1,198 URLs, zero non-200** across all 22 static and a 29-URL spread of the generated ones. 229 edge assertions green, each redirect guard verified by breaking it. **Not** treated as bugs: `/browse` and `/search` are `noindex` by design, and a 404 page canonicalising to the homepage is harmless. Genre hubs stay out of the sitemap until a work carries a genre. The submission itself needs the owner's Google account.
- **4 Aug 2026** — **The AI crawlers are unblocked; the back office is closed.** Cloudflare's "Managed robots.txt" setting had been prepending a block to kitabi.in's robots.txt that disallowed GPTBot, ClaudeBot, CCBot, Google-Extended, Bytespider, meta-externalagent, Amazonbot and Applebot-Extended, plus `Content-Signal: ai-train=no`. It could not be overridden from our own file — in robots.txt a named `User-agent` group beats `*` — so nobody here had actually chosen it. Turned **off** in AI Crawl Control → Overview and verified in the served response: no managed block, no `Disallow`, no `Content-Signal`. A reference site whose value is content nobody else has wants to be citable by answer engines. **The same dashboard turned up the opposite problem**: `admin.kitabi.in/graphql/console` was the single most-crawled path on the entire zone — a scanner probing for a GraphQL console that does not exist (it 404s correctly; nothing was exposed) — and both `admin.kitabi.in` and `api.kitabi.in` served **no robots.txt at all**, with no `noindex` on the admin sign-in page. Both now `Disallow: /` and stamp `X-Robots-Tag: noindex, nofollow, noarchive` on every response, including 404s, redirects and static assets — unconditional middleware rather than a path allowlist, which rots as routes are added. Two layers because they do different jobs: robots.txt asks crawlers not to *fetch*; the header stops *indexing* on any fetch that happens anyway, which matters because a URL can be indexed from inbound links alone and a crawler forbidden to fetch a page can never read a `noindex` inside its HTML. **The real hazard was deindexing kitabi.in itself**, since the public site is rendered from API responses — so that is what the tests guard rather than the happy path: one parses the real edge sources to prove the sitemap and cover proxies build fresh headers instead of forwarding the origin's, another proves no public page emits an `api.kitabi.in` URL. Both were confirmed by sabotaging the code and watching them fail. 486 tests green (479 API + 20 admin, 11 new), lint clean, both Docker images build. Neither layer is access control — the real controls stay the session cookie, TOTP and Cloudflare.
- **4 Aug 2026** — **The author page, planned and mocked.** The goal is a page someone looking up an Indian writer lands on and stops at: [docs/author-page-plan.md](docs/author-page-plan.md) and [docs/author-mockups.html](docs/author-mockups.html) (six states — the enriched page, the sparse page, sources disagreeing, the verified author, the sources block, and mobile). The live page already renders the four blocks we can *compute* (works, publishers, decade bar, stats); everything a reference lookup wants is missing. The unlock is measured: **1,159 of 1,162 authors carry an OpenLibrary id**, and Wikidata records OpenLibrary ids as property **P648** — so authors match **by identifier, not by name**, which removes the wrong-person risk that makes this kind of enrichment dangerous. Checked live against `Q546044` with no API key and no account: dates, birthplace, six occupations, **four awards**, a Commons portrait (74% of our authors have none), native-script labels in eight languages (the catalogue mostly lacks these), and fourteen Wikipedia sitelinks. Wikidata is **CC0** — nothing to comply with; Wikipedia prose is **CC BY-SA**, so it is quoted with attribution stored at import, never treated as text we own. Two rules the whole design turns on. **An LLM never sources a biographical fact about a real person** — not as a fallback, not with a disclaimer; this catalogue is full of living writers, several of whom will verify their own pages through the `author_claims` flow that already exists, and an invented death date or award is not a bug report. And **every fact is stored with its provenance**, which is what lets the page be honest in both directions: where sources disagree it says so (Wikidata genuinely holds *two* birth years for Thakazhi, 1912 and 1914), and where we know nothing the block disappears rather than printing "Unknown" — a page that lists what it does not know reads as a database dump, not a reference work. Phasing A0–A6; A0–A2 needs no editorial writing at all.
- **4 Aug 2026** — **Post-launch web work: search that ranks, and duplicates folded together.** Four things landed after the site went live. **Cross-type ranked search** — the old ordering was type-priority, not relevance, so a query for "dc books" put DC Books fifth behind unrelated titles; `services/search_rank.py` now scores every candidate into bands (EXACT 1.0 > PREFIX 0.80 > ALL_WORDS 0.60 > SOME_WORDS 0.35) across works, authors and publishers together. It shipped with a bug worth recording: ranking dropped rows the matcher had found ("mathrubhumi" returned nothing), so a `MATCHER_FLOOR` now guarantees **ranking can never return less than the matcher did** — a re-ranker must reorder results, never lose them. **Duplicate merging** — a `merged_into_id` pointer rather than a delete, so every old URL keeps working via 301 and a merge is reversible; an hourly exact-match auto-merge folded **28 authors and 53 publishers**, and the ambiguous remainder goes to a review queue in the admin console. Merging a row that was itself a survivor left a chain that a one-hop redirect would 404, so `merge()` repoints dependents first. **Self-hosted fonts and a cover proxy**, replacing the interim system-serif stack without adding a third-party origin. **771 of 772 hotlinked covers copied into our own Supabase `covers` bucket** — the one holdout is a persistent archive.org 503, correctly treated as transient and never deleted.
- **4 Aug 2026** — **kitabi.in is a server-rendered book site.** The measured blocker is
  fixed: a non-JS crawler on a book page received *"Opening the book…"* and zero book
  content; it now receives the whole page. Verified against production — a real book
  page serves its title (in native script), author, year, language, page count,
  breadcrumb and `Book`/`Person`/`BreadcrumbList` JSON-LD as HTML, with no JavaScript
  involved. Built in three layers:
  **(1) Slugs** (migration `000038`) — `/book/chemmeen`, not `/book/<uuid>`, romanized
  through the existing translit service so a Malayalam title yields a typeable Latin URL.
  Assigned once and never recomputed (a slug is a published URL); nullable, so a title
  that romanizes to nothing degrades to its UUID rather than failing to insert; and a
  scheduled `backfill_missing` sweeps up rows created by paths that never call
  `ensure_slug` (the ETL's bulk SQL). **(2) The `/public/*` read layer** — page-shaped,
  not resource-shaped, so a page costs exactly one upstream call instead of four
  sequential edge→Singapore round trips (~1.2 s of TTFB on their own). Reviews are
  finally public here; they were invisible on the web because the only endpoint serving
  them required a signed-in user. **(3) The edge renderer** (`landing-page/functions/_lib/`)
  — tagged template literals, no framework, no build step, no `node_modules`.
  **All fourteen mocked page types are live**: home, search, browse, book, author,
  publisher, genre hub, language hub, language+form sub-hub, series, translation group,
  editorial lists, reviews and reader profiles, plus the `/languages` `/genres` `/lists`
  `/translations` directories and the thin/404 states. Reader profiles honour **both**
  visibility flags and a private profile 404s indistinguishably from a nonexistent
  handle — "this reader exists but is private" is itself a disclosure. A profile also
  carries **the reviews that reader made public** (9 Aug 2026), on the web and in the
  app — gated on `profile_visible` plus each review's own `visible`, and pointedly not
  on `library_visible`, since a review is published on its own flag and a private shelf
  doesn't retract it. Editorial lists
  live in the renderer as content, not data (writing one is a text edit, not a
  migration), and a list whose books aren't in the catalogue yet 404s rather than
  publishing a title over nothing — it switches on by itself as the books arrive, the
  same self-healing shape as the content floor.
  `/b/`, `/a/`, `/p/` now **301** to the canonical slug URL and are kept forever;
  `/book/*`, `/author/*`, `/publisher/*` were added to `apple-app-site-association`
  **ahead of** the redirect, because iOS only re-evaluates the association at install.
  The old client-rendered shells, their `_redirects` rewrites and `_og.js` are gone.
  **Indexation is deliberately restrictive**: the content floor gates both the page's
  robots tag and the sitemap (which now emits canonical slug URLs rather than
  redirects), hubs are indexed, `/search` and `/browse` are `noindex, follow`, and every
  paginated page self-canonicals. **`AggregateRating` is emitted only when a real rating
  exists** — never zeroed, never invented. Two interim choices, both documented in code:
  CSS is inlined (the budget allows zero render-blocking requests) and fonts are a system
  serif stack rather than Fraunces + Inter, because a webfont means either a third-party
  origin or binaries to commit. Tested by `landing-page/tests/run.py` — 136 assertions
  over the real rendering code, executed with node in CI or macOS JavaScriptCore locally,
  still with no `node_modules`.
- **4 Aug 2026** — **Cloudflare edge protection, as code (`infra/cloudflare/`).**
  Written and reviewable but **not yet applied** — it needs a token that doesn't exist
  yet. The Actions `CLOUDFLARE_API_TOKEN` is scoped to *Pages: Edit* and has no
  zone/WAF permission; widening it would hand the landing-page deploy workflow the
  ability to rewrite the firewall, so a separate Zone→WAF→Edit token scoped to
  kitabi.in is required. `rate_limits.py` is dry-run by default, idempotent, refuses to
  clobber rules it didn't create, and needs no venv (stdlib only).
  The free plan allows **one** rate limiting rule, IP-only, over a short window — so it
  is a **burst shield, not an anti-scraping control**, and that one rule is deliberately
  spent on *availability*: Anthropic spend is already bounded precisely by `llm_quota`,
  and catalogue scraping is low-harm by design (the SEO plan wants that content
  crawled), while a single IP saturating the `10 + 10` DB pool has no other defence.
  Action is `block`, never a challenge — `api.kitabi.in` serves the Flutter app and the
  edge functions, neither of which can solve one. Verified bots are exempt, or crawling
  breaks and the SEO plan with it. **Ordering constraint recorded for W1:** once pages
  are edge-rendered, most API traffic stops being "one IP per reader" and becomes
  Cloudflare itself, so the edge→origin shared secret plus a `skip` rule must land
  *before* edge SSR ships or the limiter will throttle the edge.
- **4 Aug 2026** — **Spend limits on the paid endpoints, and the ISBN lookup closed.**
  `GET /recommendations` and `POST /catalog/cover-extract` are the only two endpoints
  where one request costs money, and until now neither had any ceiling: both require
  auth, but auth means "any Google account", so the cap on the Anthropic bill was the
  caller's patience. Migration `000037` adds `llm_usage` (RLS deny-by-default) behind a
  new `services/llm_quota.py`: a **per-reader daily quota** (`llm_daily_quota_recommendations`
  = 20, `llm_daily_quota_cover_extract` = 40) and a **global daily circuit breaker**
  (`llm_daily_global_cap` = 1000, the number that actually bounds the bill). Postgres,
  not Redis — rule 8 holds; any limit set to 0 is disabled. The per-reader counter is an
  `INSERT … ON CONFLICT DO UPDATE … RETURNING`, so increment-and-check is one atomic
  statement and two concurrent requests can't both read "one under the cap"; the global
  check is deliberately check-then-act (a ceiling with slack, not an exact budget — locking
  it would serialize every paid call). Quota is consumed **before** the call and **not
  refunded** on failure, or a caller who can force an upstream error gets unlimited free
  attempts. Rejections are 429 `quota_exceeded` / 503 `llm_unavailable`, both with
  `Retry-After` to the next UTC midnight. The recs meter sits in the *service*, next to
  `_generate_picks`, not in the router — every early return above it (dormant, cold-start,
  no candidates) is a free no-op, and a reader with no ratings must not burn quota
  reopening a screen that never calls Anthropic. Separately, **`GET /catalog/isbn/{isbn}`
  now requires auth** — it was the one public read that spends *OpenLibrary's* quota and
  writes to our catalog, so an anonymous caller hammering it gets Kitabi rate-limited by
  a third party and fills the catalog with junk; the app's Dio interceptor already attaches
  the bearer token to every request, so no client change was needed. **CORS narrowed to
  what the share pages actually do**: it was `allow_methods=["*"]` with
  `allow_credentials=True` and `Authorization` permitted — every method advertised to every
  browser, and cookie-bearing cross-origin reads allowed — now `["GET"]`, credentials off,
  `Accept` only. The mobile app isn't a browser and the admin console is a separate
  same-origin app, so neither is affected; the whole block disappears at W1, when the
  browser stops calling the API. 22 new tests (**342 green**), lint clean, migration
  round-trips up→down→up, Docker builds. Each new guard was verified by reverting the
  change and watching the test fail. Wider API-hardening picture (and what's still open —
  Cloudflare rate-limit rules, cache headers, app-side 429 handling) in
  [docs/web-platform-plan.md](docs/web-platform-plan.md) §11 and Phase S of
  [docs/tasks.md](docs/tasks.md).
- **4 Aug 2026** — **The public web platform, planned and mocked.** kitabi.in becomes
  a book reference site rather than a launching-soon page plus three share pages:
  [docs/web-platform-plan.md](docs/web-platform-plan.md) (architecture, URL map,
  per-page spec, performance budget, indexation strategy, phasing) and
  [docs/web-mockups.html](docs/web-mockups.html) (14 page types drawn in the Reading
  Room theme — home, search, book, author, publisher, genre + language hubs, series,
  translation group, editorial list, reviews, reader profile, mobile, and the
  thin/empty states). Nothing is built yet. The plan is grounded in production
  measurements taken the same day, two of which are blockers rather than
  improvements: a non-JS crawler on `/b/:id` receives *"Opening the book…"* and **zero
  book content** (620 ms TTFB for a shell, then a 310 ms client-side fetch to
  api.kitabi.in before anything appears), and `GET /catalog/browse/genres` returns
  `[]` — **not one seeded work has a genre**, so the genre hubs a reference site is
  built from have nothing behind them. `browse/forms` returns only `["Novel"]`.
  Live catalogue: 1,402 works / 1,189 authors / 1,066 publishers, 14 languages.
  The positioning is deliberately narrow — Indic-language literature and the
  translation graph, which is the one thing Goodreads/StoryGraph/Amazon structurally
  cannot show — and the indexation strategy is deliberately *restrictive*: a content
  floor keeps ~250–400 works indexable at launch rather than publishing 1,402 pages,
  many of them OpenLibrary transliteration noise, and teaching Google the domain is
  thin. Everything stays inside rule 8 — Cloudflare Pages Functions that already run,
  the existing FastAPI, the existing Supabase `covers` bucket; no framework, no build
  step, no new service, no new bill.
- **29 Jul 2026** — **Discover opens in the reader's own languages.** The
  catalogue's Books tab now applies a default server-side filter: the
  reader's `preferred_languages` from /me (the languages they configured at
  onboarding / on the profile). The filter sheet's language row gains a
  leading **"Your languages"** chip naming the state; All / a single language
  override it, the fab badge counts it, and an empty filtered shelf shows
  "Nothing here in your languages yet" with a **Show all books** escape
  instead of dead-ending. A late-resolving /me still applies the default —
  unless the reader has already made a choice (`_langTouched`).
  `GET /catalog/browse/works` takes a repeatable `language` param
  (`Work.language.in_`), single values still bind so older builds are
  unaffected; the app pins Dio to `ListFormat.multi` for that call because
  Dio's query default (`multiCompatible`) encodes `language[]=`, which
  FastAPI ignores. Tests: multi-language filter (API), default-applied /
  override-to-All / late-me / empty-escape (app; 52 + 293 green).
  from the live OpenLibrary API.** New `etl/07_language_seed.py` +
  `07_run_language_seed.sh` — a re-runnable seed job that needs *no* 9 GB dump:
  it asks the OL search API for the top-100 reader-interest works per language
  (`sort=readinglog`; the 13 Indic codes get `language:<code>`, English gets
  `language:eng subject:india`), fetches full work/edition/author records
  (~4.2k calls, ~4 req/s, disk-cached in `workdir/cache` so re-runs resume),
  and emits the same JSONL the dump pipeline's transform consumes. Prod now
  holds exactly **1,400 works / 1,400 editions / 1,187 authors / 1,065
  publishers, 100 works per language, 769 editions with covers (55%)** — and
  author photos where OL has them. Dedup is three-layered (cross-language
  work-key claim, per-language normalized-title match, external_id on load);
  verified 0 same-title dupes on prod. Four gotchas fixed along the way, each
  caught by validating CSVs before load: OL *orphaned editions* serve the
  edition record at their virtual `/works/OL…M` URL (force the search-index
  key, or the work↔edition link breaks); ~4% of live edition records point
  `works[]` at a *different* (merged) work than the search index said (pin
  them); bilingual editions leaked works into the wrong language bucket
  (target code now leads `languages[]`); and `to_malayalam_script` was
  converting romanized *Hindi/Tamil/etc.* titles into Malayalam script —
  `03_transform.native_script` is now gated on the row's language actually
  being Malayalam. Work titles come from the in-language edition (അനിമൽ ഫാം,
  not "Animal Farm") to match the Work-per-translation model. Verified live:
  `ikigai` → इकिगाई (Hindi, cover), one hit for "palace of illusions",
  Bengali original + English translation stay separate works.
- **29 Jul 2026** — **Production wiped of all test data; catalog reseeded clean.**
  The "test data still to be cleaned separately" debt from the 23 Jul seed-on-top
  is paid: every Layer-1/Layer-2 table truncated, all 6 test `auth.users` deleted
  (with their sessions/refresh tokens — installed apps are signed out as soon as
  their access token expires and refresh fails), the 52 test cover photos removed
  from the `covers` storage bucket, and `sync_seq` restarted at 1. The two
  `admin_users` (founder + collaborator) were deliberately kept — operational
  accounts, not test data. Catalog reseeded from the regenerated maltest CSVs
  (current `03_transform.py`, so titles land in native script with
  `title_translit` + `title_fold` populated — no post-load backfill needed):
  prod is now exactly **100 works / 100 editions / 96 authors / 57 publishers**,
  all `external_source='openlibrary'`. Verified live: `/catalog/search` resolves
  romanized queries (`arkapurnima` → അർക്കപൂർണിമ) and the sitemap serves.
  Pre-wipe safety net: `pg_dump` of `public` + auth/storage CSVs at
  `~/kitabi-backups/prewipe-2026-07-29/` (local only, not in the repo).
  Gotcha for next time: Supabase blocks SQL deletes on `storage.objects`
  (`protect_delete` trigger) — `SET session_replication_role = replica` works
  from the pooler's `postgres` role for a deliberate metadata wipe.
- **26 Jul 2026** — **Fixed: "Yes, still reading" didn't keep the sitting
  alive.** Answering the check-in re-armed the notification and the workmanager
  auto-stop but recorded nothing, so the *in-app* safety net — which measures a
  sitting's age from `startedAt` on every tick of any live surface — still
  stopped it at start + 90 minutes; opening the timer was enough to trigger it.
  The answer is now persisted and one pure deadline helper is shared by the
  in-app guard and the background task, so a confirmation moves every mechanism.
  The lock-screen card also gained a `staleDate` at the deadline: a sitting
  stopped from a background isolate can't reach the ActivityKit channel, so the
  card had been counting on past the end of a sitting that no longer existed.
- **26 Jul 2026** — **Two reading-log bugs, both from trusting a snapshot.**
  (1) The first sitting showed **"no page noted"** in the reading log while the
  progress bar showed the page: the sitting's own `pageEnd` and the entry's
  `currentPage` sat behind one "has the page changed?" guard, so ending on the
  page the entry already held wrote neither — which is the normal shape of a
  first sitting, since readers note their page before starting the clock. Two
  records, two guards now. (2) The stop sheet **kept asking for the total pages**
  on a book whose length the catalogue already had: the timer took `pageCount`
  from route `extra`, and the entry point the owner was actually using — the
  Live Activity — navigates by URL with no extra at all, so it always looked
  like an unknown length (and the screen also had no title or cover). The timer
  now resolves the book from Drift, with `extra` as a first-frame hint only;
  `quickStopSession` got the same treatment for its stale autoDispose-provider
  snapshot. Both regression tests were checked by reverting the fix.
- **26 Jul 2026** — **Fixed: the Live Activity tap hit "Page Not Found."** The
  first cut wired the tap through `DeepLinkListener` (app_links) and tested it
  there — but Flutter's engine hands an incoming deep link *straight to
  go_router*, as a whole URI including scheme and host, so
  `in.kitabi.kitabi://reading-timer/:id` reached a router with no route by that
  name and rendered a GoException error page on the phone (owner report). Every
  test passed because none of them drove the router. The rewrite now happens in
  the router's top-level `redirect`, which runs even for an unmatched location;
  the regression test drives a real `GoRouter` with the exact URI from the report
  and was checked by disabling the fix. Because that delivery is a *replace*
  rather than a push, the timer's exits also became `canPop() ? pop() : go(home)`
  — a top-level route arrived at from outside has nothing beneath it, and a bare
  pop stranded the reader on the timer.
- **26 Jul 2026** — **The live surface is a door, and the timer can finish a
  book.** Tapping the lock-screen clock now opens *that book's* timer: on iOS
  through a `widgetURL` on the Live Activity
  (`in.kitabi.kitabi://reading-timer/:id` — its own host, so the Supabase OAuth
  callback sharing that scheme is untouched), on Android through the entry id the
  ongoing notification already carried. Doing it exposed a real bug, found only by
  tapping the notification on a device: the tap pushed a **second copy** of the
  timer route, and when the top one stopped the sitting the buried copy's
  "someone else stopped this" guard popped it — so Stop & log threw the reader
  back to Home instead of asking for the page. `navigateFromExternal` now refuses
  to push the route already on top (using the match list, because go_router's
  `uri` doesn't follow an imperative push — the first version of that guard was
  dead code). Separately, both stop faces gained **"I finished the book"**: moss,
  secondary to the ordinary way out so stopping is never blocked, marking the book
  Read, stamping the finish date and settling the last page through one shared
  `markBookFinished` that the book page's status row now uses too. Verified end to
  end on the emulator: notification tap → timer → stop → finish → the book page
  showing Read, p. 724 of 724, and the finished state of the time-to-finish card.
- **26 Jul 2026** — **The reading sitting, on the lock screen.** One Dart API
  (`ReadingLiveActivity`), two deliberately different mechanisms. **iOS** gets a
  real **Live Activity**: a new `ReadingActivity` widget extension (ActivityKit +
  WidgetKit, iOS 16.2+) drawing a lock-screen card and a Dynamic Island
  presentation in the Reading Room palette, with the elapsed time as a SwiftUI
  `Text(timerInterval:)` so the system ticks it and the app is never woken to
  keep it honest. The target was added to `Runner.xcodeproj` by script (the
  `xcodeproj` gem CocoaPods already ships), mirroring the existing
  `NotificationService` extension; `ReadingActivityController.swift` drives it
  over a method channel. **Android has no Live Activities API below Android 16**,
  so its equivalent is an **ongoing notification with a chronometer** — same
  promise (the clock is readable without unlocking), different mechanism, and the
  code says so rather than pretending they're one feature. Wired to the single
  start path and the single stop path, plus a reconcile on every resume so a
  sitting stopped from a background isolate can't leave a clock running.
  **Verified on the Android emulator against a real lock screen** (00:25 → 01:47
  while locked and backgrounded, gone the moment the sitting stopped); the iOS
  side is verified as far as an archive can go — the extension compiles, signs
  and embeds in the shipped IPA — with the on-device lock-screen render still to
  be checked on a real iPhone. Two bugs found and fixed on the way, neither of
  which any test would have caught: a low-importance notification is collapsed
  into a silent *dot* on the Android lock screen (the clock invisible), and under
  the UIScene lifecycle `AppDelegate.window` is nil at launch, so registering the
  channel through it would have meant iOS silently never starting an activity at
  all. Both are now in CLAUDE.md's lessons.
- **26 Jul 2026** — **"Time to finish" — every book page answers *can I finish
  this?*** Every timed sitting already stored `duration_seconds` and a page
  range; that is now a **reading pace**, and the pace is the reader's own, never
  a crowd average (with this many readers, "readers average 8h" would be one
  person's sittings wearing a plural noun — the same rule that keeps a
  "Trending" row off the search page). Pure `computeReadingPace` /
  `estimateFinish` (`app/lib/features/insights/reading_pace.dart`, 16 unit
  tests) resolve pace most-specific-first — this book's own sittings → this
  language → the last 90 days → a *stated* typical 40 pp/h — behind a reactive
  `readingPaceProvider` (a stream, because sittings are written from four routes
  that don't own the screens showing the estimate). One `TimeToFinish` widget
  covers all nine states: hours + **sittings** + **weeks** (the gold one, because
  it knows the reader's actual weekly habit), remaining-time and a finish date
  once started, the **actual** in moss on a finished book *plus a calibration
  line* ("at your usual pace this would have been 8h 36m — you ran 12% over"),
  the grey dashed assumed-pace state with a "1 of 3 sittings" bar, and the
  page-count prompt when the catalogue doesn't know how long the book is. It
  renders on a book you don't own too (a gold strip under the frontispiece —
  the *deciding* screen), because it only needs a page count and one pace
  number. The library gains a **time-to-finish facet** (Under 3h / 3–8h / 8–15h
  / 15h+, filtering on time *remaining*), time tags on the covers while it's on,
  and an honest "N books have no page count, so they can't be estimated" count
  in both the sheet and the grid — finished books are excluded from the facet
  entirely. Mockups **P1–P9** (Area 13) in `docs/kitabi_screens.html`. Verified
  end to end on the Android emulator against seeded sittings — two real bugs the
  green tests missed (a per-book sentence quoting the *global* sitting count; a
  finished book leading "under 3h" at zero seconds) were found and fixed there.
- **24 Jul 2026** — **Admin console — global search + the email sign-in suite.**
  A global command-search in every page's top bar (focus `/`, arrow/enter),
  role-aware, recommending actions, books, authors, publishers and readers over
  the spelling-insensitive fold. In-portal password change. And the email
  sign-in trio, all behind a **dormant mail sender** (owner chose: build now,
  pick a transport later — CLAUDE.md rule 8; until SMTP env is set, the code/
  link is logged to the server and the flows work end to end): **forgot
  password** emails a 30-min OTP that is accepted as a temporary password and
  forces a real change on next load (`admin_users.must_change_password`);
  **passwordless magic link** (15-min, single-use, TOTP still required);
  **email invites** replace the hand-delivered temp password (48h setup link;
  the link is surfaced on the admins page while mail is dormant). Migration
  `000033` (`admin_auth_tokens`, `must_change_password`). All flows verified
  live end to end on the dev DB (OTP→TOTP→forced-change, magic single-use,
  invite→set-password→enrol). Real send is stdlib smtplib — no new dependency,
  no bill until SMTP creds are added. 259 API + 10 admin tests, images build.
- **24 Jul 2026** — **Admin console — the remaining screens, all wired.** The
  four "Planned" stubs are now real, verified live: **suggested-edit
  moderation** (every pending `work_revision`, decided via the API's
  `decide_revision` with a new `admin_override` for seeded/orphaned books);
  **reported content** (open `content_reports` → uphold hides the review with a
  `server_seq` bump so it re-syncs, or dismiss; [WIRED], quiet until the report
  button ships); **catalog ops** (spelling-fold search, a quality-gap worklist,
  and **duplicate merge** — `merge_preview`/`merge_works` in catalog_service,
  moving editions + ratings/reviews and folding author/genre links, soft-
  deleting the absorbed work, all in one transaction with a type-MERGE
  confirm; editor+ only); and **reader support** (search + detail showing only
  public data + contribution counts, plus **suspend/unsuspend** via new
  `profiles.suspended_at` — migration `000032` — enforced in the API's
  `get_current_user`, which now rejects a suspended reader 403 while leaving
  new/profile-less users unaffected). Hard reader deletion is deliberately not
  a button. New tests: merge (3), suspension (3) — 259 API + 8 admin, both
  images build. Reader-suspension is a change to the live reader API's hot path,
  covered by tests proving active/suspended/no-profile all behave.
- **23 Jul 2026** — **Admin console foundation + its CI/deploy plumbing**
  (`admin/`, package `console`). A server-rendered back office (FastAPI + Jinja +
  htmx) at `admin.kitabi.in`, reusing the API's models/db/services via a
  `sys.path` shim (`console/models_ref.py`). Admin identity is separate from
  readers by construction — `admin_users` (Argon2id + TOTP), recovery codes,
  DB-backed sessions, append-only `admin_audit_log`, `[WIRED]` `content_reports`
  (migration `000031`, RLS-enabled). **Built + verified live** (browser, dev DB):
  password → forced TOTP enrolment → dashboard (live counts + catalog health) →
  author-claims queue (wired to the API's `approve_claim`/`reject_claim`) →
  admin-user management (create / role / revoke, with no-self-lockout guards) →
  audit log. **Deferred as "Planned" stubs:** suggested-edit moderation,
  reported content, catalog ops, reader support; plus email invites and (now
  done) CI. **CI/deploy:** `admin-ci.yml` (ruff/black/pytest + docker build,
  also triggered by `api/app/**` since the console imports it); `admin/railway.json`
  for a second Railway service. The production image was run and serves
  `/healthz` + the auth gate. **Still owner-only:** create the Railway service +
  `admin.kitabi.in` DNS, run migration `000031` on prod, seed the founder
  (`scripts/seed_super_admin.py`). Full design: `docs/admin_mockups.html`;
  runbook: `admin/README.md`.
- **23 Jul 2026** — **Search stops caring how you spell it** (release **build 89**).
  Two romanization bugs and one structural fix. (1) ITRANS marks the long vowels
  ീ/ൂ with an uppercase I/U that lowercasing flattened to a bare i/u, so
  അപൂർണ്ണൻ was stored as "apurnnan" — "Apoornn" scored 0.27 against it and
  found nothing, while "Apoornna" scraped over pg_trgm's 0.3 similarity
  threshold, which is why one extra letter looked like magic (owner report).
  Long vowels now double; ചെമ്മീൻ romanizes to "chemmeen", *identical* to the
  Latin spelling. (2) Tamil was romanized with Sanskrit consonant values —
  "பொன்னியின் செல்வன்" stored as "bhonniyin jhelvan" (0.42 similarity to what a
  reader types) and "சிலப்பதிகாரம்" as "jhilabhbhadhigharam" (0.13, unfindable);
  the superscripted scheme fixes both. (3) **The fold** (migration `000030`,
  `*_fold` columns, GIN-trigram-indexed): a spelling skeleton collapsing long/short
  vowels, aspiration, the ch/sh/s sibilants, gemination, v/w and the m/n nasal, applied
  to the stored value *and* the query, so any romanization reaches the book.
  Measured before building — 13/20 realistic typings fold to an exact hit; 197
  titles yield 194 distinct folds (the one collision being a single word spelled
  two ways), so recall rose without costing precision. Verified live on prod:
  ചോര is found by chora/sora/chhora, പ്രണാമം by pranamam/pranaamam/branamam,
  and the reported "Apoornn" now returns അപൂർണ്ണൻ first.
- **23 Jul 2026** — **Home showed "…" for every title on a fresh install.** Not a
  font or rendering bug: `book?.title ?? '…'` is the fallback for a missing
  `cached_books` row, and that cache is device-local while `library_entries`
  are synced. `cacheMissingLibraryBooks` already existed to heal it but was
  wired only into the **library grid's** initState, so Home stayed broken until
  you visited that tab — while `cacheBorrowedBooks`, the identical gap for
  borrowed books, had been in the sync pass since July. Hydration now runs on
  the pull, where every surface benefits. (CLAUDE.md's "a feature added to one
  entry point must be added to all of them", again.)
- **23 Jul 2026** — **The catalog now stores Malayalam in native script.** The
  seed arrived in OpenLibrary's ALA-LC romanization (`Kēraḷa sthalanāmakōśaṃ`);
  `api/app/services/malayalam_script.py` converts it back via ISO 15919,
  handling the four things the library alone gets wrong (anusvara written with
  a dot *below*; ഴ/റ marked with COMBINING LOW LINE U+0332, not macron-below;
  chillu forms; and the positional `r̲` — plain ര after a consonant, റ after a
  vowel). It refuses rather than guesses on English titles and forces digits
  back to Arabic. Backfilled on prod via `etl/06_backfill_script.py`:
  **194 of 418 rows converted, 0 left romanized**, re-run is a no-op;
  `03_transform.py` converts future seeds on the way in. Verified live —
  cross-script search resolves both directions (`prashnangal` →
  കവിതയുടെ പ്രശ്നങ്ങൾ, and `രണ്ടു` → രണ്ടു മുദ്ര) and book pages serve
  Malayalam in their OG tags and JSON-LD. **Also fixed a latent search bug**
  this would have multiplied: ITRANS spells ങ/ഞ as `~N`/`~n`, and no reader
  types a tilde — doubled forms now collapse (മാങ്ങാട് → `mangat`,
  കൊഴിഞ്ഞു → `kozhinju`). **Known residual:** a homorganic nasal before a
  consonant comes out as a conjunct where native spelling often uses anusvara
  (അമ്ബികാസുതൻ vs the usual അംബികാസുതൻ) — readable, and fixable later via
  "Improve this entry" or a follow-up rule.
- **23 Jul 2026** — **First real catalog seed landed on production.** 100
  Malayalam works (+96 authors, 100 editions, 57 publishers) loaded via
  `etl/05_load_prod.sh` on top of the existing test rows (owner chose
  seed-on-top; test data still to be cleaned separately) — prod catalog went
  97→**197 works**, 54→150 authors, 14→71 publishers. Verified live: search
  finds the seeded titles by romanized query, the sitemap serves 197 works,
  and a seeded book page renders 200 with full schema.org `Book` JSON-LD.
  **Content-quality notes for the full seed:** OpenLibrary's Malayalam records
  are romanized with diacritics (`Kēraḷa sthalanāmakōśaṃ`), *not* in Malayalam
  script — search still matches (both sides romanize) but titles display
  romanized; only 2/100 editions had covers and 30/100 works a description,
  while ISBNs (37), page counts (95) and publishers (93) came through well.
- **23 Jul 2026** — **SEO layer + catalog seeding pipeline.** The public share pages are now search-engine-ready:
  `GET /catalog/sitemap/index.xml` + paged `works-N`/`authors-N`/`publishers-N`
  urlsets (10k URLs/page, soft-delete-aware — `sitemap_service`, 7 tests, 209
  total green), proxied at `kitabi.in/sitemaps/*` by a new Pages Function and
  announced in `robots.txt`; the `/b` `/a` `/p` share functions now inject
  schema.org JSON-LD (`Book` with per-edition `workExample` / `Person` /
  `Organization`) and `rel=canonical` alongside the existing OG tags. New
  top-level **`etl/`**: a streaming OpenLibrary bulk-dump pipeline
  (popularity → filter → transform → idempotent `04_load.sql`) that seeds a
  *curated* catalog — every Indic-language work + top-N popular works, ≤5
  best editions each, deterministic uuid5 ids, translit computed with the
  API's own `transliterate` (COPY bypasses the ORM hooks). Smoke-tested
  end-to-end on 32 MB dump prefixes into the local dev Postgres (5,012 works
  loaded; re-running the load inserts 0 — converges). Measured from samples:
  the full dumps are ~41M works / ~55M editions (~45–60 GB in Postgres —
  never loadable on Supabase free, hence the tiers); the recommended
  ~600k-work seed lands ~1.2–1.5 GB (needs Supabase Pro), a 100k slim cut
  sits near the free tier. Still open: Google Search Console registration,
  running the real seed, slug URLs on share links.
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
