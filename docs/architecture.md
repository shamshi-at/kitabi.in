# Kitabi — Architecture & Technical Reference

> **Purpose.** The deep technical picture: how the system is structured, why it's
> structured that way, the invariants that must not be broken, and a **file-by-file
> map** of the whole tree. Read this before making a structural or data-model change.
>
> Companion docs: [build.md](build.md) (how to build/run/ship), [../STATUS.md](../STATUS.md)
> (what's live), [../CLAUDE.md](../CLAUDE.md) (rules), [../feature-map.md](../feature-map.md)
> (product spec).

---

## 1. System overview

Kitabi is an **offline-first Flutter app** talking to a **stateless FastAPI backend**
over HTTPS (JWT auth), backed by **Supabase Postgres**. A dependency-free static
**landing page** on Cloudflare rounds it out.

```
┌────────────────────────────────────────┐
│  Flutter app (iOS / Android)            │
│                                         │
│  UI (Riverpod) ──▶ Repositories ──▶ Drift (SQLite)   ← Layer-2 source of truth
│                          │                            │
│                          └─▶ sync_queue               │
│                                  │                    │
│                          Sync engine ◀────────────────┘
│                          (push/pull, idempotent)      │
└──────────────────────────┬──────────────────────────┘
                           │ HTTPS + JWT (X-App-Version)
┌──────────────────────────▼──────────────────────────┐
│  FastAPI (Railway, Singapore — co-located with DB)   │
│  routers ──▶ services (thick) ──▶ SQLAlchemy 2.0 async│
│  · JWT verify vs Supabase JWKS (PyJWT, ES256)         │
│  · version gate (426)   · APScheduler jobs            │
│  · FCM HTTP v1 sender   · OpenLibrary client          │
└──────────────────────────┬──────────────────────────┘
                           │ asyncpg via Supavisor pooler (6543)
┌──────────────────────────▼──────────────────────────┐
│  Supabase Postgres (RLS deny-by-default, Data API off)│
│  · Auth (Google + Apple)   · canonical catalog + user data│
└──────────────────────────────────────────────────────┘
```

**Guiding constraint (CLAUDE.md rule 8):** cheap to run, cheap to maintain — no Redis,
no queues, no extra SaaS. Anything that looks like it needs Redis is done in Postgres
or in-process with a `# SCALE:` note.

---

## 2. The two data tiers (the core mental model)

Every piece of data is exactly one of two tiers, **never conflated**:

### Layer 1 — Shared catalog (server-authoritative)
Books, authors, publishers, genres, series. Fetched/searched via the API and **cached**
in Drift for offline *reading*; **not** user-synced. Sourced from **OpenLibrary** with
**cache-on-first-use** (a book fetched once lives in our own Postgres forever after).

- **Work vs Edition** (rule 17): ratings, reviews, translations attach to the **Work**;
  ownership, cover, ISBN, page count, format, buy links attach to the **Edition**.
- **A translation is its own Work**, linked to the original by a shared
  `translation_group_id` — its own authors/editions and its own rating pool. A
  read-time-only aggregate averages across the group for display without merging pools.
- User *contributions* (add/edit a book) go through the API when online; `created_by_user_id`
  on works/authors feeds the reputation score.

### Layer 2 — Personal (offline-first, Drift is the source of truth)
Library entries, reading statuses, progress, private notes, personal tags, ratings,
reviews, lending records, activity log. **The UI reads/writes Drift, never the API
directly.** The sync engine is the only component that talks to the backend for this
data. Ported from rupee-diary's proven pattern.

**Every syncable table carries** (rule 10): `id` (client-generated UUID), `user_id`,
`created_at`, `updated_at`, `deleted_at` (soft-delete — rule 3), plus client-side
`sync_status`/`last_synced_at` and a server-side `server_seq`.

### Neither tier
- **`Profile`** — the user's identity row, keyed by the Supabase auth user id. Direct
  online `GET/PATCH/DELETE /me`; no sync queue.
- **`Connection`** and **`device_tokens`** — cross-user / transport state, online-only.

---

## 3. The sync engine (Layer 2)

Pure, heavily unit-tested, **no UI imports** — treated as library code.

**Write path:** UI → repository → (1) write to Drift, (2) insert a row into the local
`sync_queue` (op type, entity, JSON payload, attempt count, client-generated **op UUID**).
UI updates instantly from Drift's reactive streams.

**Drain:** `workmanager` (15-min cadence) + a connectivity-regained listener →
`POST /sync/push` (a batch of ops) → `GET /sync/pull?cursor=` (deltas). Server-wins
results applied locally.

**Invariants:**
- **Idempotency** — every push op carries an op UUID; the server's `sync_ops` ledger
  has a unique constraint, so a retried batch is a no-op the second time.
- **Cursor** — pull uses a server-assigned `server_seq` (bigserial), **never a
  timestamp**. Because a column `server_default nextval(...)` fires only on INSERT,
  **every mutation (create/update/delete) must explicitly re-assign
  `server_seq = nextval('sync_seq')`** before flushing (see `sync_service._bump_seq`;
  dropping this silently breaks pull ordering — a documented past bug).
- **Conflicts (rule 6)** — delete-wins, then last-write-wins by server-received time;
  a losing write records a `conflict_history` row (never resolved silently). Kitabi has
  no cross-user sharing in V1, so the conflict signal is "a different one of *my*
  devices" (`device_id`, generated once per install), not "a different user."
- **Retry** — max 5 attempts, exponential backoff, then `sync_status = error` surfaced
  in the UI (the sync banner shows on *error* only; routine sync is silent).

---

## 4. Cross-user features (the social layer)

The first pull-forward of the `[LATER]` community platform, kept online-only so the
per-user sync engine stays simple.

- **Connections (consent).** A single deduped `connections` row per pair
  (requester/addressee, status pending/accepted/denied, `blocked_by`). `POST /connections`
  requests (or auto-accepts a mutual request); accept/decline/block/unblock; a declined
  request is **re-sendable** until blocked (terminal). RLS-enabled, auth required.
- **Loan mirroring.** When you lend to an **accepted connection**, `lend_mirror_service`
  creates a correlated `direction='borrowed'` record on the borrower's account
  (`linked_loan_id`), gated on `are_connected`, run **after** the lender's sync op
  commits so a mirror failure never rejects the loan. It pulls to the borrower via the
  normal cursor and appears on their Borrowed shelf; `GET /catalog/editions/{id}`
  hydrates a borrowed book they never added.
- **Rejected-loan handling.** The ledger's Rejected tab shows still-out loans whose
  borrower declined — the lender re-sends, or "makes a private contact"
  (`updateBorrower` clears `borrower_user_id` via a sync op).
- **Reputation.** `scoring_service` computes a StackOverflow-style score at read time
  from countable rows the user owns (books/authors added, reviews, tracked/finished,
  lends) — no ledger to keep in sync.

---

## 5. Push notifications (FCM) — opt-in

First push pipeline, dormant unless configured (rule 8).

- **Sender.** `fcm_client` implements **FCM HTTP v1 with only PyJWT + httpx** — mints a
  service-account JWT, caches the OAuth access token, POSTs `messages:send`. **No
  `firebase-admin` dependency.** Dead tokens are auto-pruned on `UNREGISTERED`.
- **Gating.** No-op unless `FIREBASE_CREDENTIALS` (service-account JSON) is set. All
  `notify_*` open their own DB session, so they're safe to hand to FastAPI
  `BackgroundTasks` (which run after the request session closes) — **off the response
  path**, so a push failure never affects the API response.
- **Events.** Connection request/accepted; book lent/returned; return reminder. The app
  registers its token via `/devices` on sign-in (cleared on sign-out) and routes taps
  by `message.data['type']`.

---

## 6. Auth & security

- **Sign-in** — Supabase Auth, **Google + Apple only** (rule 7). No passwords/OTP.
  Google via browser-redirect `signInWithOAuth`; Apple via native `signInWithIdToken`.
- **API verification** — every protected route verifies the Supabase JWT with **PyJWT
  against the project JWKS** (ES256), caching JWKS and handling `kid` rotation, checking
  `iss`/`aud`/`exp`. **Never python-jose.**
- **RLS deny-by-default (rule 11)** — every Supabase table has RLS enabled with **zero
  policies**, Data API disabled; only FastAPI (via the Supavisor transaction pooler,
  port 6543, prepared-statement cache off) touches user data. A new table without RLS
  is a security bug.
- **Storage exception** — user-photo covers/portraits go to the Supabase Storage
  `covers` bucket directly from the app (user JWT), the one place the app talks to
  Supabase outside FastAPI; separate from the deny-by-default Postgres tables.
- **Version gate** — `VersionGateMiddleware` reads `X-App-Version` and returns **426**
  with an update payload for builds below `min_app_version`; the app shows a blocking
  update screen.

---

## 7. Conventions that shape the code

- **Routers thin, services thick** — sync batching, catalog dedupe, CSV parsing,
  recommendation calls live in `services/` with unit tests.
- **Errors** — `HTTPException` with structured `{"code","message"}` detail.
- **App** — feature-scoped Riverpod providers (codegen `@riverpod`), route names as
  constants, repositories wrap DAOs + enqueue sync ops (providers talk to repositories
  only), all user-facing strings through l10n `.arb` (English template; Malayalam on the
  roadmap).
- **Migrations** — every model change ships its Alembic migration in the same commit;
  never edit an applied migration; verify up+down before deploy.
- **Three-way review split (rule 13)** — star *ratings* on the Work, text *reviews* on
  Work+user with a visibility flag, private *notes* on the library entry. Never merged.

---

## 8. File-by-file map

Every non-generated source file and its responsibility. Generated files
(`*.g.dart`, `*.freezed.dart`, `app_localizations*`) and empty `__init__.py`/package
markers are omitted.

### API — `api/app/`

**Entry & core**
- `main.py` — FastAPI app factory: mounts routers, the version-gate + CORS middleware, structured error handling, and the APScheduler lifespan.
- `core/db.py` — Async SQLAlchemy engine/session factory tuned for the Supavisor transaction pooler; exposes the request-scoped `get_db` dependency.
- `core/config.py` — pydantic-settings config: DB URL, Supabase JWKS/JWT verification, CORS, version gate, and opt-in recs/push credentials.
- `core/security.py` — Supabase JWT verification via PyJWT against the project JWKS (ES256); yields the current user.
- `core/version_gate.py` — Middleware that 426s app builds older than `min_app_version` from the `X-App-Version` header.

**Routers — `api/`**
- `api/deps.py` — Shared FastAPI dependency aliases: current user (verified JWT claims) and the async DB session.
- `api/catalog.py` — Layer-1 catalog router: search, ISBN lookup, browse/add/edit of works, editions, authors, publishers.
- `api/sync.py` — Offline-first push/pull sync protocol for Layer-2 data (idempotent op push, `server_seq`-cursored delta pull).
- `api/auth.py` — Idempotent profile bootstrap on first login, keyed off the verified JWT.
- `api/me.py` — Current-user router: read/update own profile, username availability, score.
- `api/users.py` — Search other users' public profiles for connections/lending.
- `api/health.py` — Liveness + DB-reachability probe for deploy health checks.
- `api/connections.py` — Request/accept/list user connections and send lending reminders (optional FCM push).
- `api/recommendations.py` — Opt-in LLM-reasoned recommendations, dormant unless an Anthropic key is set.
- `api/import_.py` — Preview and commit CSV library imports matched against the catalog.
- `api/devices.py` — Register/unregister an install's FCM push token for the signed-in user.

**Schemas — `schemas/`** (Pydantic v2, `XCreate`/`XUpdate`/`XOut`)
- `schemas/catalog.py` — Works, editions, authors, publishers, ISBN lookup, import rows, recommendations.
- `schemas/sync.py` — Sync push/pull protocol: op payloads, results, cursored deltas.
- `schemas/device.py` — FCM device-token registration.
- `schemas/profile.py` — Profile read/update, username validation, public user search, scoring.
- `schemas/connection.py` — User-to-user connections and lending reminders.

**Models — `models/`** (SQLAlchemy 2.0)
- `models/base.py` — Declarative base + `SyncableMixin` (Layer-2) and `CatalogMixin` (Layer-1) column mixins.
- `models/work.py` — The abstract creative Work + work_authors/work_genres joins; ratings/reviews/translation links attach here.
- `models/edition.py` — A specific printing/ISBN of a Work: cover, page count, format, buy links.
- `models/author.py` — Layer-1 catalog author, linkable to Works.
- `models/publisher.py` — Layer-1 catalog publisher referenced by Editions.
- `models/genre.py` — Global catalog genre label, distinct from a user's PersonalTag.
- `models/series.py` — A named ordering of Works; per-book sequence lives on Edition.
- `models/library_entry.py` — A user's syncable copy of an Edition: ownership, status, progress, favorite, private notes.
- `models/rating.py` — Syncable 1–5 star rating attached to a Work.
- `models/review.py` — Syncable text review on Work+user with its own visibility flag.
- `models/personal_tag.py` — A user's own syncable shelf/tag, distinct from Genre.
- `models/library_entry_tag.py` — Syncable tag-to-entry assignment as its own row (independent conflict handling).
- `models/lending_record.py` — Syncable lend/borrow ledger entry, running both directions.
- `models/connection.py` — Directed, consented lending link between two users; online-only (not syncable).
- `models/device_token.py` — An FCM registration token for one install; online-only transport state.
- `models/activity_log_entry.py` — Syncable, pull-only log of the user's own events; the future community feed.
- `models/sync_op.py` — Idempotency ledger keyed by client `op_id` so replayed batches aren't reapplied.
- `models/conflict_history.py` — One row per detected sync conflict (winning/discarded payloads, 30-day retention).
- `models/profile.py` — One row per Supabase auth user (identity), keyed by `auth.users.id`; online-only.

**Services — `services/`** (thick business logic)
- `services/catalog_service.py` — Layer-1 catalog logic: works/editions/authors/publishers/genres/series with dedupe, ISBN+OpenLibrary lookup, tuned eager-loading.
- `services/openlibrary_client.py` — Thin, mockable OpenLibrary metadata client — the V1 zero-credential metadata source.
- `services/sync_service.py` — Push/pull for Layer-2: idempotent op application, delete-wins/LWW conflicts, `server_seq` cursor.
- `services/connection_service.py` — Reader-to-reader requests, accept/block, and directional status over one deduped row per pair.
- `services/lend_mirror_service.py` — Mirrors an outgoing loan onto a linked borrower's Borrowed shelf, committed independently after the lender's sync op.
- `services/profile_service.py` — Profile bootstrap-on-first-login and update; visibility toggles; case-insensitive username uniqueness.
- `services/scoring_service.py` — Read-time reputation score from countable contribution/activity rows a user owns.
- `services/device_service.py` — Device FCM token registry: upsert/rebind on sign-in, unregister on sign-out.
- `services/fcm_client.py` — Minimal FCM HTTP v1 sender (PyJWT-minted token, httpx POST); dormant unless push is configured.
- `services/push_service.py` — High-level `notify_*` bridge between app events and FCM; each opens its own session (BackgroundTasks-safe), no-op unless configured.
- `services/import_service.py` — CSV import parsing (Goodreads/generic) into normalized rows for catalog matching.
- `services/recommendation_service.py` — Opt-in LLM-reasoned recommendations with a plain-words "why"; dormant unless an Anthropic key is set.

**Jobs — `jobs/`**
- `jobs/scheduler.py` — APScheduler setup with per-job Postgres advisory locks so a second replica never double-runs.
- `jobs/keep_warm.py` — Periodic Supabase keep-warm query (advisory-locked) to dodge the free-tier 7-day idle pause.

### App — `app/lib/`

**Core — `core/`**
- `main.dart` — App entry point: bootstraps Firebase/Supabase, the ProviderScope, and the router.
- `core/auth/auth_providers.dart` — Auth wiring: selects real vs stub auth service, exposes the current-user stream, resets local data on account switch.
- `core/auth/auth_service.dart` — Abstract auth interface + offline `KitabiAuthUser`/`UnconfiguredAuthService` so the app never touches Supabase directly.
- `core/auth/supabase_auth_service.dart` — Concrete Supabase-backed auth: Google/Apple sign-in via the OAuth deep-link callback.
- `core/deep_links.dart` — Listens for incoming kitabi.in universal/app links and routes them to the matching detail screen.
- `core/haptics.dart` — Small shared haptic-feedback vocabulary for taps, selections, confirmations.
- `core/image_crop.dart` — Fixed crop grids (2:3 covers, 1:1 squares) and the pick-then-crop flow for uploads.
- `core/languages.dart` — The canonical Malayalam-led language list offered for profiles and book tagging.
- `core/notifications/notification_service.dart` — On-device local notifications for lending due-date reminders (no server/push).
- `core/notifications/push_service.dart` — Registers the FCM token with the API, keeps it fresh, routes notification taps.
- `core/router/app_router.dart` — go_router route-name constants + the route table with auth-guard redirects.
- `core/router/shell_scaffold.dart` — The persistent bottom-nav shell (Home/Library/+/Lending/Insights) wrapping the tab branches.
- `core/share_links.dart` — Builds public kitabi.in share URLs (books/authors/publishers) that double as in-app deep-link routes.
- `core/theme/app_theme.dart` — Kitabi "Reading Room" design tokens + light/dark theme construction.
- `core/theme/brand_mark.dart` — Reusable Gold Line brand-logo widget at a consistent size/shape.
- `core/widgets/async_states.dart` — Shared shimmer/skeleton and async loading-state widgets.
- `core/widgets/image_source_sheet.dart` — Bottom sheet asking camera vs gallery before any image pick.
- `core/widgets/language_chips.dart` — Toggleable language-chip wrap over `kLanguages`, shared by onboarding and profile.
- `core/widgets/status_pill.dart` — The single tinted uppercase reading-status pill style used throughout.
- `core/widgets/sync_status_bar.dart` — Global banner shown only when sync has actually failed.
- `core/widgets/typeset_cover.dart` — Uniform cover frame that renders a derived "typeset" cover when no image exists.

**Data — `data/`**
- `data/api/api_client.dart` — Thin Dio wrapper attaching JWT + app version and surfacing the 426 update-gate.
- `data/db/database.dart` — The local Drift database (offline source of truth) wiring all syncable tables, the catalog cache, and their DAOs.
- `data/db/tables.dart` — Drift table + shared sync-column mixin definitions for all local tables.
- `data/db/catalog_cache.dart` — Writes fetched Work/Edition catalog fields into the local read-only offline cache.
- `data/db/daos/cached_books_dao.dart` — DAO for the read-only catalog cache backing offline library-grid rendering.
- `data/db/daos/library_daos.dart` — DAOs for Layer-2 personal data (entries, ratings, reviews, tags, lending, activity) + join result types.
- `data/db/daos/sync_daos.dart` — DAOs for the sync queue, pull cursor, conflict history, and key-value store.
- `data/repositories/repositories.dart` — Repository classes wrapping DAOs + enqueuing sync ops — the only write path for Layer-2 data.
- `data/repositories/repository_providers.dart` — Riverpod providers exposing each repository bound to the session + database.
- `data/sync/sync_engine.dart` — Pure, UI-free push-then-pull sync engine with op-id idempotency (ported from rupee-diary).
- `data/sync/sync_providers.dart` — Riverpod wiring for the sync layer: database, session context, engine, sync-trigger callback.
- `data/sync/background_sync.dart` — workmanager background-isolate entry point that drains the queue on the OS cadence.
- `data/sync/connectivity_sync.dart` — Provider triggering an immediate drain when connectivity is regained.
- `data/sync/device_id.dart` — Generates/persists a per-install device ID used as the multi-device conflict signal.

**Features — `features/<name>/`** (feature-first UI: `presentation/` + `providers/`)

- `features/activity/presentation/activity_screen.dart` — Surfaces the private personal activity log (seed of the future community feed).
- `features/auth/presentation/sign_in_screen.dart` — S1 sign-in: brand mark, tagline, rotating quote, Google/Apple buttons.
- `features/catalog/catalog_image_upload.dart` — Uploads author portraits + publisher logos to the shared `covers` bucket.
- `features/catalog/presentation/add_edit_book_screen.dart` — S4d form to add/edit a Work + its first Edition.
- `features/catalog/presentation/add_edition_screen.dart` — Adds another Edition (printing/ISBN) to an existing Work.
- `features/catalog/presentation/author_browse_screen.dart` — S4c list of every catalog work by one author.
- `features/catalog/presentation/author_picker_screen.dart` — S7b search/add a catalog author from the add-book form.
- `features/catalog/presentation/book_link_resolver_screen.dart` — Resolves the `/b/:workId` share/deep-link path to book detail.
- `features/catalog/presentation/browse_screen.dart` — Discover/browse paging the whole catalog (books, authors, publishers).
- `features/catalog/presentation/catalog_entity_tiles.dart` — Shared author/publisher row tiles for search + browse.
- `features/catalog/presentation/catalog_result_tile.dart` — One catalog-work row with tappable author/publisher + quick add-to-library.
- `features/catalog/presentation/catalog_search_screen.dart` — S4 global search across library + catalog books/authors/publishers.
- `features/catalog/presentation/isbn_scan_screen.dart` — S7 barcode scanner resolving an ISBN via catalog/OpenLibrary.
- `features/catalog/presentation/picker_widgets.dart` — Fixed catalog-language list + shared picker helpers.
- `features/catalog/presentation/publisher_browse_screen.dart` — S4d list of every catalog work from one publisher.
- `features/catalog/presentation/publisher_picker_screen.dart` — S7b search/add a catalog publisher.
- `features/catalog/presentation/work_picker_screen.dart` — Search-and-pick a Work when linking a translation.
- `features/catalog/providers/catalog_providers.dart` — Providers for catalog-only + global search results.
- `features/connections/connections_providers.dart` — Connection identity model + providers for the peer-to-peer layer.
- `features/connections/presentation/connection_loans_screen.dart` — Loans (lent + borrowed) shared with one connection.
- `features/connections/presentation/connections_screen.dart` — S8b connections inbox: the consent layer for lending.
- `features/home/presentation/home_screen.dart` — S3 home dashboard: currently reading, lending summary, entry points.
- `features/import_books/csv_export.dart` — Builds a Goodreads-friendly CSV of the library (pure/unit-testable).
- `features/import_books/presentation/import_screen.dart` — S2 CSV import matched to the catalog into local entries.
- `features/insights/insights_stats.dart` — Pure, unit-testable reading stats derived from the library.
- `features/insights/presentation/insights_screen.dart` — S10 insights: goal ring, year selector, headline stats, per-month chart.
- `features/insights/providers/insights_providers.dart` — Providers feeding insights (library-with-books + reading goal).
- `features/lending/lending_format.dart` — Short date formatting shared across the ledger + sheets.
- `features/lending/presentation/borrower_field.dart` — "Lent to / borrowed from" field that matches Kitabi users.
- `features/lending/presentation/lend_pick_book_sheet.dart` — Pick which owned book to lend, then hand off to the lend sheet.
- `features/lending/presentation/lend_sheet.dart` — S9 lend flow bottom sheet (to whom, dates, note, reminder).
- `features/lending/presentation/lending_ledger_screen.dart` — S8 lending ledger: Lent-out / Rejected / Borrowed tabs, reminders.
- `features/lending/presentation/log_borrowed_sheet.dart` — S8c sheet to log a book you've borrowed.
- `features/lending/presentation/sheet_fields.dart` — Shared form-field building blocks for the lend/log-borrowed sheets.
- `features/lending/reminder.dart` — Pure helpers for lending due-date reminder ids + fire times.
- `features/library/cover_upload.dart` — Pick/crop a user cover photo, upload to the `covers` bucket.
- `features/library/presentation/book_detail_screen.dart` — S6 book detail combining Work-level + Edition-level data.
- `features/library/presentation/library_filter_sheet.dart` — S4b library-grid filter model + sheet UI.
- `features/library/presentation/library_grid_screen.dart` — S5 covers-first library grid with status pills + filters.
- `features/library/providers/library_providers.dart` — Providers for the offline-first personal library (entries, ratings, derived lists).
- `features/library/reading_status.dart` — The 5 reading states with labels/colors matching the design source.
- `features/onboarding/onboarding_providers.dart` — Device-local "onboarding seen" flag + setter.
- `features/onboarding/presentation/language_picker_screen.dart` — Post-sign-in step capturing preferred languages (router-gated).
- `features/onboarding/presentation/welcome_screen.dart` — First-run welcome cards shown once.
- `features/profile/presentation/profile_screen.dart` — S12 profile/visibility switchboard (community toggles default off).
- `features/profile/providers/profile_providers.dart` — Own-profile (`/me`) provider fetched after sign-in bootstrap.
- `features/recommendations/presentation/recommendations_screen.dart` — S11 opt-in reasoned recommendations with a "why".
- `features/recommendations/providers/recommendations_providers.dart` — Device-local recs opt-in + related providers.
- `features/settings/theme_mode_provider.dart` — Device-local dark-mode preference driving the theme.
- `features/share/presentation/book_share_card.dart` — S6c/S13 shareable book card (cover, title, author, rating, mark).
- `features/share/presentation/entity_share_card.dart` — Shareable author/publisher card mirroring the book card.
- `features/share/presentation/entity_share_sheet.dart` — Share sheet for an author/publisher (copy-link / share-card).
- `features/share/presentation/share_book_sheet.dart` — S6c book share sheet with optional personal rating/note toggle.
- `features/share/presentation/share_capture.dart` — Rasterises a share card to PNG + hands it to the OS share sheet (link fallback).
- `features/splash/presentation/splash_screen.dart` — Animated splash while auth/profile bootstrap resolves.
- `features/update_gate/presentation/update_screen.dart` — Non-dismissible screen when the API rejects the build (HTTP 426).

### Landing page — `landing-page/`
- Dependency-free static `index.html` + `logo.svg` + rasters; `book.html`/`author.html`/`publisher.html` public entity pages (clean-routed via `_redirects` as `/b/:id` `/a/:id` `/p/:id`); `functions/` are Cloudflare Pages Functions that inject Open Graph tags server-side for rich link previews; `.well-known/` holds the Apple App Site Association + Android assetlinks for universal/app links; `privacy.html`/`terms.html`.
