# CLAUDE.md

Working notes for Claude Code sessions in this repo. Extend this file as decisions
land — it is the living source of truth for how to work here.

## What Kitabi is

Kitabi (kitabi.in) — "Beyond the Bookshelf" — is a mobile-first personal library app
built solo, positioned in the gap between reading trackers (Goodreads, StoryGraph)
and collection apps (Libib):

- **Wedge:** ownership tracking + free first-class lending + Edition-level
  "real bookshelf" feel, with a regional/translation angle (`.in`, Malayalam roots).
- **Hook (kept quiet):** opt-in, transparent LLM-reasoned recommendations. The 2026
  market is AI-wary, so lending/library goes on the billboard, recs are the delight.
- **Long game:** personal app now, community platform later — **without a rewrite**.

[feature-map.md](feature-map.md) is the product spec: every feature tagged `[V1]`
(build now), `[WIRED]` (build the data shape now, feature stays dormant), or
`[LATER]` (genuinely defer). Read it before making product or data-model decisions.

## Tech stack

Same architecture and technologies as the sibling project
`/Users/shamshi/development/shamshi/rupee-diary` (offline-first Flutter + FastAPI +
Supabase). Proven there; reuse its patterns and lessons rather than re-deciding.

| Part | Stack |
|---|---|
| `app/` | Flutter — Riverpod (hand-written providers; **no `@riverpod` codegen** — `riverpod_generator` was dropped 14 Aug 2026, see below), go_router, Drift (local DB, source of truth), Dio (+ interceptors: JWT attach, update-gate, retry/backoff), supabase_flutter (auth), flutter_secure_storage, connectivity_plus, workmanager (background sync drain), Firebase for FCM only |
| `api/` | FastAPI — Python 3.12+, fully async (SQLAlchemy 2.0 async, asyncpg), Pydantic v2, Alembic migrations, APScheduler jobs, Docker (must always build), ruff + black line length 100 |
| Database | Supabase Postgres — RLS deny-by-default, Data API disabled; only FastAPI (via Supavisor transaction pooler, port 6543, prepared-statement cache off) touches user data |
| Auth | Supabase Auth (Google + Apple per feature map). API verifies JWT with **PyJWT against project JWKS** (ES256, cache JWKS, handle `kid` rotation, check `iss`/`aud`/`exp`). Never python-jose |
| `landing-page/` | Dependency-free static HTML/CSS on Cloudflare (Pages today via GitHub Actions; Workers static assets like rupee-diary is fine later) |
| Hosting | Railway (API) + Supabase free tier. Core constraint: **cheap to run, cheap to maintain** — no Redis, no queues, no extra SaaS. If something seems to need Redis, do it in Postgres or in-process and leave a `# SCALE:` comment |

## Repository layout

This folder is the single root for all three parts:

| Directory | rupee-diary equivalent | What it is | Status |
|---|---|---|---|
| `landing-page/` | `landing/` | kitabi.in — the static page, the public share pages (`/b/` `/a/` `/p/`) and their Cloudflare Pages Functions | Live. Planned to grow into the full public book site — [docs/web-platform-plan.md](docs/web-platform-plan.md) |
| `api/` | `backend/` | FastAPI — catalog, personal library, auth, sync, recommendations | Scaffolded (health endpoint, JWT verify, Alembic, tests, Docker) |
| `app/` | `app/` | Flutter mobile app — the primary platform (web comes later) | Scaffolded (Riverpod + go_router + l10n, placeholder home) |
| `etl/` | — | OpenLibrary bulk-dump → curated catalog seed pipeline (offline scripts, run locally with `api/.venv`) | Scaffolded, smoke-tested |

Keep this structure: new parts get their own top-level directory; nothing app- or
api-specific lands at root. Product docs (feature-map.md) and repo docs live at root.

Internal shape (mirrors rupee-diary):

- `app/lib/` → `core/` (router, theme, constants, sync engine), `data/` (Drift DB,
  DAOs, repositories, API client), `features/<name>/{presentation,providers,widgets}`.
  Data layer stays centralized in `data/` because the sync engine owns persistence.
- `api/app/` → `api/` (routers, one file per resource), `core/` (config, security,
  deps), `models/` (SQLAlchemy), `schemas/` (Pydantic `XCreate`/`XUpdate`/`XOut`),
  `services/` (business logic — thick), `jobs/` (APScheduler). Plus `alembic/`,
  `tests/`, `Dockerfile`.

## Non-negotiable rules (adopted from rupee-diary, adapted to Kitabi)

1. **Offline-first means offline-FIRST.** UI reads/writes go to Drift, never directly
   to the API. The sync engine is the only component that talks to the backend for
   user data. Applies to **Layer 2 (personal)** data: library entries, statuses,
   notes, tags, lending records, reviews, progress.
2. **The shared catalog (Layer 1) is server-authoritative.** Books, authors,
   publishers, genres, series are fetched/searched via API and cached in Drift for
   offline reading — they are not user-synced entities. User *contributions* to the
   catalog (add/edit book) go through the API when online.
3. **Soft deletes only.** Never SQL `DELETE` for user data. Set `deleted_at`; queries
   filter `deleted_at IS NULL` by default.
4. **UUIDs client-side** for records created offline. The server never assigns IDs to
   syncable entities.
5. **Timestamps are UTC** (`timestamptz` / ISO-8601 with Z); local rendering only at
   the UI layer.
6. **Conflict rules fixed:** delete-wins, then last-write-wins by server-received
   time. Conflicts write a history row; never resolve silently.
7. **Auth is Google + Apple only in V1.** No password fields, no OTP flows.
8. **No new services, no new monthly bills.** Before adding any dependency or
   service: does it add a bill or a credential? Default answer is no.
9. **Docker must keep working** — the API Dockerfile is the escape hatch from Railway.
10. **Every syncable table** carries `id`, `user_id`, `created_at`, `updated_at`,
    `deleted_at` (+ client-side `sync_status`, `last_synced_at`).
11. **RLS deny-by-default on Supabase.** Every table: RLS enabled, zero policies,
    Data API disabled for app schemas. A new table without RLS is a security bug.
12. **Backups must keep working** once user data exists: nightly `pg_dump` →
    encrypted → Cloudflare R2 via GitHub Actions (Supabase free tier has no backups).

Kitabi's own wiring rules (from the feature map — expensive to reverse):

13. **Three-way split:** star *ratings* attach to the shared book, text *reviews*
    attach to book + user with a visibility flag, *personal notes* stay private on
    the library entry. Never merge these.
14. **Lending is a record, not a flag** — "lent to X, on date, returned ✓" as its own
    entity; borrower free text now, real user reference later.
15. **Personal activity log is the future community feed** — log the user's own
    events from day one.
16. **Visibility toggles everywhere** — profile, library, per-review — wired even
    while nothing is public.
17. **Work vs. Edition:** ratings/reviews/translations attach to the *Work*;
    ownership, cover, page count attach to the *Edition*.
18. **Personal tags ≠ global genres** — user shelves never pollute the catalog.
19. **A read is a record, not a counter** — rule 14's shape applied to reading
    itself. A book read three times has three beginnings, endings, paces and sets of
    notes; `LibraryEntries` has one `start_date`, one `finish_date`, one
    `current_page`. Each pass gets a `Reads` row, and every sitting and note is
    stamped with the pass it belongs to (`read_id`); the count is always *derived*
    from those rows, never stored. The entry's own columns stay as a mirror of the
    **current** read, so every existing reader of `current_page` — the four progress
    surfaces, the timer, the Live Activity, the public web pages — is untouched.
    Retrofitting means backfilling every sitting ever logged and guessing which pass
    it belonged to, which is the one guess nobody can make. Two behaviours move with
    it: `markBookFinished` stamps the read instead of refusing to re-stamp the entry,
    and `autoFinishIfOnLastPage` tests the current read instead of returning early on
    a book already marked read. `[WIRED]` — design in
    [docs/reread-mockups.html](docs/reread-mockups.html) (owner picked Direction A,
    29 Aug 2026).

## Commands

> Full build/run/ship guide (prerequisites, exact commands, release paths for
> API, app IPA + AAB, landing) lives in [docs/build.md](docs/build.md). The deep
> technical reference (data tiers, sync engine, cross-user layer, push, auth/RLS,
> and a file-by-file map of the whole tree) is [docs/architecture.md](docs/architecture.md).

Local ports are deliberately offset from rupee-diary so both projects run side
by side: dev Postgres on **55442**, throwaway test Postgres on **55443**
(rupee-diary uses 55432/55433).

```bash
# API (venv: api/.venv, Python 3.12 via Homebrew)
cd api
docker compose up -d db                  # local Postgres (port 55442)
.venv/bin/uvicorn app.main:app --reload  # dev server
.venv/bin/pytest                         # tests (starts kitabi-test-pg container)
.venv/bin/ruff check . && .venv/bin/black --check .   # lint
.venv/bin/alembic revision --autogenerate -m ""   # new migration
# ⚠️ api/.env's DATABASE_URL is PRODUCTION. alembic/env.py refuses a non-local
# host, so pass the dev URL explicitly (or ALLOW_PROD_MIGRATION=1 to mean it):
DATABASE_URL=postgresql+asyncpg://postgres:postgres@localhost:55442/kitabi \
  .venv/bin/alembic upgrade head         # apply migrations
docker build -t kitabi-api .             # must always build

# Flutter (SDK at ~/development/flutter — not on default PATH)
cd app
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # Drift codegen (the only generator)
flutter test
flutter analyze
cp dart_defines.env.example dart_defines.env   # once, then fill in real values (gitignored)
./scripts/run_dev.sh -d <device>               # NOT `flutter run` directly — see below
./scripts/build_ipa.sh                          # NOT `flutter build ipa` directly
```

After changing any Drift table, **always run build_runner** before assuming
compilation errors are real.

**The Flutter SDK and the codegen chain have to agree.** `build_runner` runs the
`analyzer` package, not the SDK's own front end, so an SDK *newer* than the pinned
analyzer dies on syntax it can't parse — `Missing implementation of
visitDotShorthand…` on Dart 3.13, which looks like a broken repo and is really a
version skew (the warning line above it names it: "SDK language version X is newer
than `analyzer` language version Y"). What pinned it here was **`riverpod_generator`,
which generated nothing at all** — there is not one `@riverpod` in `lib/`, and it
alone held `analyzer` at 7.x. Dropped 14 Aug 2026 along with `riverpod_annotation`;
`flutter_riverpod` (the runtime, hand-written providers) is untouched. If codegen
breaks on a new SDK again, look for a *dev* dependency capping `analyzer` before
reaching for a second SDK install.

Always build/run through `scripts/run_dev.sh` and `scripts/build_ipa.sh`, never
`flutter run`/`flutter build ipa` directly — every `--dart-define` the app reads
must be passed explicitly on every invocation (none of them carry over), and a
missing one fails silently rather than loudly. See "Lessons learned" below.

## Workflow

- **Task tracking:** `docs/tasks.md` is the living checklist, phased in build order
  (P0 foundations → P8 launch). Pick work from it; tick a box **only after** the
  definition of done below is met, in the same commit as the change. If scope
  shifts, edit the list rather than working off-list.
- **Definition of done:** code + tests pass (`pytest` / `flutter test`), lint clean,
  migration included if schema changed, Docker still builds, app features work
  offline (airplane-mode check), matches the mockup screen.
- Don't build parking-lot (v1.5) items early even if convenient — flag and skip.
- **`STATUS.md` is the project's source of truth** (architecture, tech stack,
  integrations, live URLs, deployment state, feature status). Update it in the same
  commit whenever any of those change — new integration, new deploy target, a phase
  completes, a URL changes. Don't let it drift from reality.

## Conventions

- Routers thin, services thick — sync batching, recommendation calls, CSV import
  parsing, and catalog dedupe live in `services/` with unit tests.
- Errors: `HTTPException` with structured detail `{"code": "...", "message": "..."}`;
  version enforcement returns 426 with update payload.
- **Any endpoint whose request costs money must be metered before it ships.**
  Auth is not a spend limit — it means "any Google account", so an unmetered paid
  endpoint's ceiling is the caller's patience. Route it through
  `services/llm_quota.consume` (per-reader daily quota + global circuit breaker,
  backed by `llm_usage`) and add its feature constant to `models/llm_usage.py`.
  Meter at the line the spend happens on, not in the router — every cheap early
  return above it must stay free. Same rule for a public endpoint that spends a
  *third party's* quota: `GET /catalog/isbn/{isbn}` is signed-in-only for exactly
  that reason. Wider picture: [docs/web-platform-plan.md](docs/web-platform-plan.md) §11.
- Every model change ships its Alembic migration in the same commit; never edit
  applied migrations.
- Flutter: feature-scoped Riverpod providers, no global mutable singletons; route
  names as constants; repositories wrap DAOs + enqueue sync ops — providers talk to
  repositories only; all user-facing strings through l10n arb even while
  English-only (Malayalam localisation is on the roadmap).
- Design: `docs/kitabi_screens.html` is the design source of truth ("Reading Room"
  theme — paper/ink/oxblood/gold); tokens and patterns in `docs/screen-design.md`.
  Match the mockups when building screens; update the mockups when design changes.
- Conventional commits (`feat:`, `fix:`, `chore:`, `refactor:`, `test:`); one logical
  change per commit.
- Landing page stays dependency-free static HTML/CSS — no build step, no frameworks;
  mobile-first, respects `prefers-reduced-motion`; follows the Reading Room theme.
  The **public web platform** ([docs/web-platform-plan.md](docs/web-platform-plan.md),
  mockups in [docs/web-mockups.html](docs/web-mockups.html); the author page is planned
  separately in [docs/author-page-plan.md](docs/author-page-plan.md) with
  [docs/author-mockups.html](docs/author-mockups.html)) holds that line: pages
  are rendered by the Cloudflare Pages Functions that already run there, from a
  `functions/_lib/` of plain template literals — no framework, no `node_modules`.
  Two rules it adds: **the public web is strictly read-only** (every write is a door
  into the app, so RLS deny-by-default and a zero public attack surface both hold),
  and **content is server-rendered** — a page whose body needs JS to appear is a page
  crawlers don't have.
- **Logo:** `landing-page/logo.svg` is the master mark — "The Gold Line": an open
  book with a gold ribbon bookmark and text lines on both pages, one line gold on
  the recto ("the line that stays with you"), on an oxblood tile with a gold
  hairline inset. Pure vector, no fonts. **Brand rule: no letter K in any mark**
  (owner decision, 3 Jul 2026). Chosen after five concept rounds in
  `docs/logo-concepts.html`. Rasters (`kitabi-logo.png` 512, `ico.png` 64)
  regenerate via `qlmanage -t -s 512 -o . logo.svg` + `sips`.
- Use `git mv` when relocating files so history follows.

## Sync engine (pattern from rupee-diary — reuse, don't reinvent)

- Mutations: write to Drift → insert into local `sync_queue` (op type, entity,
  payload, attempt count) → UI updates instantly from Drift.
- Drain: workmanager + connectivity listener; batch to `POST /sync/push`; pull deltas
  via `GET /sync/pull?cursor=`; apply server-wins results locally.
- Every push op carries a client-generated **op UUID**; server enforces a unique
  constraint so retried batches are idempotent. Pull cursor is server-assigned
  `server_seq` (bigserial), never a timestamp.
- Retry: max 5 attempts, exponential backoff; then `sync_status = error`, surface in UI.
- Treat the sync engine as library code: pure, heavily unit-tested, no UI imports.

## Deployment

- **Landing page:** `.github/workflows/deploy.yml` deploys `landing-page/` to
  Cloudflare Pages (project `kitabi-in`) on pushes to `main` touching
  `landing-page/**` or the workflow. Copies `index.html`, `logo.svg`,
  `kitabi-logo.png`, `ico.png` into `public/`. Requires repo secrets
  `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`.
- **api / admin: Railway auto-deploys them from `main`.** ⚠️ **A push to `main` is a
  production deploy of the API.** Not a GitHub Actions workflow — Railway's own
  GitHub integration, wired to the `shamshi-at/kitabi.in` repo, so it is invisible
  in `.github/workflows/` and `gh run list` never shows it. The two services are
  `api/railway.json` (project `kitabi-api` → `api.kitabi.in`) and
  `admin/railway.json` (→ `admin.kitabi.in`), both `DOCKERFILE`-built, Southeast
  Asia, health-checked at `/healthz`. `.github/workflows/api-ci.yml` runs the
  **tests**; it does not deploy, and it does not gate the deploy either — Railway
  builds from the push, not from a green CI run.

  **The API's Dockerfile migrates on boot**: its `CMD` is
  `alembic upgrade head && uvicorn …`, so **every deploy and every restart applies
  pending migrations to the production database**. Consequences worth holding on
  to: a migration merged to `main` reaches production within about a minute, with
  no separate release step and nothing to approve; a migration that fails takes
  the container's start command with it, so the health check fails and Railway
  restart-loops rather than serving a half-migrated API; and a migration must
  therefore be safe to run against the *previous* version of the code, which is
  what is serving traffic while the new image rolls. The admin Dockerfile
  deliberately does **not** run alembic — both services share one database, and
  one migrator is the point.

  **`alembic/env.py` refuses to migrate a non-local host** unless
  `ALLOW_PROD_MIGRATION=1` is set — because `api/.env`'s `DATABASE_URL` points at
  the Supabase pooler, so a bare `alembic upgrade head` in `api/` migrates
  production (it did, 5 Aug 2026, *despite* the hazard being written down: a note
  in a long file stops nobody, a process that exits does). The container opts in
  via `ENV ALLOW_PROD_MIGRATION=1` in `api/Dockerfile` — declared in the repo
  rather than a dashboard, so the one place production may migrate is readable
  from a checkout. **Never delete that line**: without it the boot migration is
  refused, the CMD fails, the health check fails, and Railway restart-loops
  production. `tests/test_migration_guard.py` asserts it is still there.
- **app:** no pipeline; releases are built locally (see [docs/build.md](docs/build.md)).

## Lessons imported from rupee-diary ("things that have bitten us")

- Repeated regex edits on large generated files cause cascading corruption — rebuild
  cleanly instead of patching patches.
- Drift schema changes without `build_runner` produce confusing analyzer errors.
- Supabase free tier pauses after 7 days idle — keep the project warm (scheduled
  ping job in the API's `jobs/`).

## Lessons learned in Kitabi

- **A plugin that hasn't migrated to Flutter's built-in Kotlin fails one step
  downstream, as generated Java.** Flutter 3.47 compiles plugin Kotlin itself and
  warns about plugins still applying their own Kotlin Gradle Plugin
  (`mobile_scanner`, `share_plus`, `sign_in_with_apple`, `workmanager_android` here).
  For three of them the warning is only a warning; `workmanager_android` 0.9.3's
  sources never reached the classpath, so the build died as
  `GeneratedPluginRegistrant.java:114: cannot find symbol … WorkmanagerPlugin`
  (14 Aug 2026) — which reads like a corrupt registrant and is really "that plugin
  didn't compile". `workmanager ^0.10.0` fixed it with no call-site changes. When
  generated registrant code can't find a plugin class, read *upwards* for the KGP
  warning before touching the registrant. **`app/pubspec.lock` is gitignored**, so
  plugin versions float per machine — this class of break appears on whichever
  machine resolves first, not on whoever changed something.
- **Real-time antivirus can eat Flutter's AOT compiler mid-release-build.** Three
  times on 14 Aug 2026 (twice iOS, once Android), `gen_snapshot` was SIGKILLed
  (`AOT snapshotter exited with code -9`) and then *deleted* from
  `bin/cache/artifacts/engine/…`, so the next build failed differently with
  `Failed to find …/gen_snapshot`. Recovery is `flutter precache --ios --force` /
  `--android --force` and rebuild; the durable fix is an exclusion for
  `~/flutter/flutter/bin/cache/` in the scanner (Intego on this machine). Two
  symptoms, one cause — a `-9` and a missing-binary error in consecutive builds are
  the same event, not two problems.

- **A `_inFlight ??= run()` single-flight guard silently drops triggers that arrive
  mid-run.** Bit the sync engine (7 Jul 2026): a mutation enqueued while a sync pass was
  in flight returned the in-flight future and was never pushed until the next external
  trigger — up to 15 minutes later, read as "sync is broken". Single-flight guards on
  drain-the-queue work must coalesce (mark a follow-up pass and re-run), not just dedupe.
  Same session: repositories must fire the sync trigger on every enqueue — offline-first
  still means push *immediately* when online, not on the workmanager cadence.
- **Snapshotting a SQLAlchemy row into JSONB must handle plain `date` columns, not just
  `datetime`.** `_row_to_dict` (sync conflict history) serialized `datetime`/`UUID` but
  passed `date` through raw, so the first cross-device conflict on a row with a date
  column (`lent_date`, `start_date`…) crashed the whole `/sync/push` batch with a 500
  (7 Jul 2026). Check `isinstance(value, date)` — it covers `datetime` too, subclass.
- **Supabase's direct-connection hostname (`db.<ref>.supabase.co:5432`) resolves
  IPv6-only.** On a network without a working IPv6 route it connects painfully
  slowly or times out outright (bit us during Phase 1 auth testing, 4 Jul 2026) —
  use the Supavisor transaction pooler (port 6543, IPv4 + IPv6) for literally
  everything except one-off `psql`/debugging where you know IPv6 works.
- **New Supabase OAuth redirect scheme → add it to Authentication → URL
  Configuration → Redirect URLs before testing**, or sign-in silently falls back
  to the default Site URL (`localhost:3000`) instead of returning to the app —
  looks like a dead page, not an auth error, so it's non-obvious what broke.
- **`workmanager` needs iOS 14+.** The default Flutter template targets iOS 13 —
  bump `platform :ios` in `ios/Podfile` and `IPHONEOS_DEPLOYMENT_TARGET` in
  `project.pbxproj` (all three build configs) before the first real `pod install`,
  or CocoaPods dependency resolution fails opaquely.
- **`mobile_scanner` needs iOS 15.5+** (bumped again from 14.0, same 3 pbxproj configs
  + Podfile as above) **and cannot build at all on an Apple Silicon iOS Simulator.**
  Its MLKit pods ship no arm64 simulator slice — only real devices and x86_64
  simulators. Add an `EXCLUDED_ARCHS[sdk=iphonesimulator*] = arm64` line to every
  build config in *both* `Podfile`'s `post_install` (for the Pods project) *and*
  `Runner.xcodeproj/project.pbxproj` (for the app target itself) to force a
  Rosetta-translated x86_64 simulator build — but that only helps if the installed
  iOS runtime actually still ships an x86_64 slice; the newest runtimes may not.
  Faster path when scanning code specifically: verify on an Android emulator (no such
  restriction there) or a real iPhone, not the iOS Simulator.
- **A column `server_default` (e.g. `nextval('sync_seq')`) only fires on INSERT, never
  on UPDATE.** Bit us building the sync engine (6 Jul 2026, `SyncableMixin.server_seq`):
  a naive `await db.flush(); await db.refresh(row, ["server_seq"])` after mutating a
  row left `server_seq` unchanged on updates/deletes, silently breaking the pull
  cursor's ordering. Every mutation (create/update/delete) must explicitly reassign
  `row.server_seq = text("nextval('sync_seq')")` before flushing — see
  `sync_service._bump_seq` (API) and rupee-diary's identical `_bump_seq`, which this
  was ported from; the bug was in dropping that explicit step, not in the pattern.
- **Every `--dart-define` the app reads (`API_BASE_URL`, `SUPABASE_URL`,
  `SUPABASE_PUBLISHABLE_KEY`) must be passed explicitly on every single
  `flutter build`/`flutter run` invocation — none of them carry over between
  builds, and a missing one fails silently, not loudly.** Bit us twice on
  6 Jul 2026: first `API_BASE_URL` defaulted to `http://localhost:8000` (nothing
  listens there on a real device, so every API call failed); then three IPA builds
  in a row never passed `SUPABASE_URL`/`SUPABASE_PUBLISHABLE_KEY` at all, so
  `supabaseConfigured` was false and the app silently used `UnconfiguredAuthService`
  — sign-in always threw, with no build-time warning that anything was misconfigured.
  **Fix:** use `app/scripts/build_ipa.sh` / `run_dev.sh`, which read every required
  define from `app/dart_defines.env` (gitignored — copy from `dart_defines.env.example`)
  and fail loudly before Xcode/Gradle even starts if one is missing. Don't call
  `flutter build ipa`/`flutter run` directly with hand-typed `--dart-define` flags —
  that's exactly how this kept happening.
- **"One row per key" is a sync-shaped assumption — never enforce it with
  `getSingleOrNull`.** The pull upserts by *id*, so an entry created on another
  device/install lands next to the local row for the same edition; every
  `getByEditionId` then crashed the book page's Yours tab with "Bad state: Too many
  elements" (16 Jul 2026, Aadujeevitham). Lookups must pick a deterministic winner
  (earliest `createdAt` — the row children already point at), `add()` must reuse an
  existing active entry, and a post-pull heal (`library_dedupe.dart`) merges the
  rows and enqueues the merge so the server converges too.
- **Server `Date` columns reject full ISO timestamps on `/sync/push`.** Pydantic
  only accepts a datetime string for a `date` field when the time part is zero —
  `updateProgress` sent `DateTime.now().toUtc().toIso8601String()` for
  `start_date`/`finish_date`, so every such op died as `invalid_payload` and reading
  dates never synced (16 Jul 2026). Anything mapped to a Postgres `Date` goes on the
  wire as `YYYY-MM-DD` (`.toIso8601String().split('T').first`, like `lent_date`
  always did).
- **`ref.read(someStreamProvider).valueOrNull` is null until that stream has
  emitted — never depend on it for a write.** The reading timer looked the
  book's edition id up via `ref.read(libraryEntriesProvider).valueOrNull` to
  save a reader-supplied total page count; on the timer route nothing kept that
  autoDispose stream warm, so it read empty, the edition id came back null, and
  the total was silently dropped — the book never got a page count and progress
  stayed blank (owner report, 19 Jul 2026). For a value a mutation depends on,
  await a direct query (`libraryEntriesDao.getById`) instead of reading a stream
  provider that may not have produced its first value yet. Same fix shape as the
  15 Jul dup-entry heal: don't trust "there's usually a value there."
- **A feature added to one entry point must be added to *all* of them.** The
  "type the total pages while logging" field lived only on the full timer + the
  quick-stop dialog; the manual-log sheet and the progress-editor pencil never
  got it, so logging from those paths could never set a total (same 19 Jul
  report). The four progress surfaces (timer / quick-stop / manual-log /
  pencil) must stay in lockstep — the total-save now routes through one shared
  `saveBookTotalPages(db, api, editionId, total)` so they can't drift again.
- **A one-shot `FutureProvider` that other screens mutate behind your back
  shows stale data unless every writer hand-invalidates it — prefer a reactive
  stream.** `libraryEntryProvider` was a `FutureProvider` (`getByEditionId`);
  the book page watched it, but the reading-timer face writes progress from a
  *different* route and never invalidated it, so after a timed session the page
  still showed progress "—" — only the manual-log path worked, because it alone
  called `ref.invalidate` (owner report, 19 Jul 2026, caught by on-device E2E,
  not by the green unit tests). Fixed by making it a `StreamProvider` over
  `watchByEditionId`, so a write from any path (timer, pencil, status change)
  refreshes the page live. If a provider's value can change from a screen that
  doesn't own it, make it reactive rather than trusting every caller to
  invalidate. Same shape as the 17 Jul `cachedBookProvider` and `libraryTags`
  fixes — this is a recurring class of bug here.
- **Don't use a `WidgetRef` across an `await` that can unmount the widget it
  belongs to — capture the handles you need first.** `quickStopSession(context,
  ref)` called `stop()` (clearing the session), then `showDialog`, then wrote
  the page via `ref.read(...)`. Stopping from the persistent **mini-bar** works
  differently from the home card: the mini-bar is rendered only while a session
  is live (`active == null ? SizedBox.shrink()`), so `stop()` unmounts it and
  its `ref` — the post-dialog reads silently no-op'd and the page a reader typed
  never reached the entry (the book stayed "Not started" though the session
  logged; owner report, 19 Jul 2026). The home *card* hid the bug because it
  stays mounted after stop. Fix: read the db/repos/notifier and a
  `ProviderScope.containerOf(context)` **before** `stop()`, and do every
  post-stop mutation through those captured objects, never `ref`. Regression
  test (`quick_stop_test.dart`) reproduces it with a child that unmounts on stop
  — it fails on the old code, passes on the fix.
- **`.cast<T>()` on a decoded JSON list is lazy — a shape change surfaces as a
  crash inside `build()`, not at the API call.** Adding work counts to
  `GET /catalog/browse/genres` changed its rows from `"Fiction"` to
  `{name, work_count}`; the app's `(res.data as List).cast<Map<String, dynamic>>()`
  accepted the *old* payload silently and threw `type 'String' is not a subtype
  of type 'Map<String, dynamic>'` only when the list was later iterated — in the
  add form's build, red-screening the whole form far from the cause, and sailing
  straight past the `.catchError` that was meant to make the fetch best-effort
  (21 Jul 2026). Two rules: parse API lists **eagerly**, element by element, so
  failures land at the boundary; and tolerate the *previous* payload shape,
  because an API deployed behind the app is a normal deploy-order state, not an
  edge case — the update-gate only protects the opposite direction (app too old).
  `ApiClient.parseGenreRows` is the pattern, with `genre_rows_parse_test.dart`.
- **A `BoxDecoration` with `borderRadius` plus a non-uniform `Border` (e.g. a
  thicker colored left rule) throws at paint time, not at build/analyze time —
  the widget renders as a blank box and only the device log says why.** Bit the
  translation flows (21 Jul 2026): four "left accent rule" cards copied from the
  mockups used `Border(left: BorderSide(gold, 3), top/right/bottom: line)` +
  `borderRadius` — `flutter analyze` and all 121 widget tests stayed green, and
  the cards drew as empty white rectangles on the emulator ("A borderRadius can
  only be given on borders with uniform colors"). The mockup look is built
  instead with a uniform `Border.all(line)` + `clipBehavior: Clip.antiAlias` and
  a 3px `Container` strip as the row's first child. This is exactly the
  class of bug the on-device E2E pass exists to catch — screenshots, not tests,
  found it.
- **A `SingleTickerProviderStateMixin` state may only ever create ONE Ticker —
  never dispose-and-recreate its `AnimationController` in `didUpdateWidget`.**
  `TickerText` did exactly that when text *and* startDelay changed together —
  which is every recycled grid cell and every keystroke in the add-form's live
  cover preview, since the ticker delay is derived from the title hash (21 Jul
  2026). The second controller threw "multiple tickers were created". Reuse the
  controller: stop it, reset `value`, assign a new `duration`, and rebuild the
  `TweenSequence` on it. Corollary for reading device logs: a thrown build paints
  a `RenderErrorBox` whose debug intrinsic size is 100000×100000 px, so a
  "BOTTOM OVERFLOWED BY 99873 PIXELS" banner (≈100000 − the box's height) is a
  *symptom of an exception in build*, not a real layout overflow — find the
  first thrown exception above it before chasing layout. — never use it to raster an
  asset whose alpha matters.** `assets/icon/app_icon_foreground.png` (the Android
  adaptive-icon foreground) was generated that way, so the "transparent" layer was
  really an opaque white square: Android painted the oxblood background layer and
  the foreground covered every pixel of it, leaving a white tile with a small book
  (owner report, 16 Jul 2026). iOS was unaffected — it uses the full-bleed
  `app_icon.png`, which has its own oxblood background — so the icon looked right
  on one platform and broken on the other. Check any regenerated raster with
  `Image.open(p).convert('RGBA').getpixel((5,5))`: a foreground's corner must be
  `(0,0,0,0)`, not `(255,255,255,255)`. Recovering it needs a real renderer
  (`rsvg-convert`/`cairosvg` — none are installed), or, when the same art also
  exists over a second known background, exact two-background alpha recovery:
  `Cw = A·a + W·(1−a)` and `Co = A·a + O·(1−a)` solve for `a` (that's how this was
  fixed — the result recomposited over oxblood matched `app_icon.png` to ±1/255).
- **App icon/splash source art for `flutter_launcher_icons`/`flutter_native_splash`
  should NOT reuse the in-app rounded brand tile (`logo.svg`) directly for the app
  icon** — the OS applies its own rounding mask, so the icon source must be a flat,
  full-bleed square (see `app/assets/icon/app_icon.svg`, a border-less variant of
  `landing-page/logo.svg`). The *splash* image is the opposite case: it should be the
  already-rounded `kitabi-logo.png`, since the splash background color (paper) plus a
  centered rounded tile is exactly what `SplashScreen` renders in-app — the point is
  to match, not to avoid double-masking.
- **A low-importance Android notification is *collapsed into a silent dot* on the
  lock screen** — the content is there, but nothing readable is. Bit the reading
  timer's lock-screen clock (26 Jul 2026): `Importance.low` felt right for a surface
  that must never buzz, and `dumpsys notification` happily confirmed the notification
  existed with all the right flags, but the actual lock screen showed a grey circle in
  the collapsed row and no clock at all — the one thing the feature exists for. Use
  `Importance.defaultImportance` with `playSound: false`, `enableVibration: false` and
  `silent: true` for anything that must be *readable* while quiet. Two corollaries:
  `dumpsys` is not verification (screenshot the lock screen), and **a channel's
  importance is fixed at creation** — changing the code does nothing on a device that
  already has the channel, so re-verify only after `adb uninstall`.
- **Under the UIScene lifecycle `AppDelegate.window` is nil in
  `didFinishLaunchingWithOptions`** — the scene creates the window afterwards. Any
  channel registered via `window?.rootViewController as? FlutterViewController`
  silently never registers, and every call over it no-ops with nothing in the logs
  (caught by reading `SceneDelegate.swift` before shipping, 26 Jul 2026 — no test or
  archive build would have). This app has `UIApplicationSceneManifest` +
  `FlutterSceneDelegate`, so register custom channels through the registrar instead:
  `registrar(forPlugin: "…")?.messenger()`, which needs no window.
- **go_router's `currentConfiguration.uri` does NOT follow an imperative
  `push`** — it stays on the last *declarative* location, so after
  `router.push('/reading-timer/x')` it still reads `/home`. A guard written as
  `if (currentConfiguration.uri.path == location) return;` is therefore dead code
  that silently never fires (written exactly that way here on 26 Jul 2026, and it
  "passed" an on-device check by coincidence). The top of the stack is
  `currentConfiguration.matches.last.matchedLocation`. Two corollaries: a stacked
  duplicate route is *offstage*, so `find.text` reports one widget either way and a
  widget test written against rendering passes against the bug — assert on
  `matches.length`; and after writing any guard like this, disable it and watch the
  test fail before believing it.
- **A "still doing it?" confirmation has to move the deadline for *every* stop
  mechanism, not just the ones it re-arms.** Tapping "Yes, still reading" on the
  reading check-in re-armed the notification and the workmanager auto-stop, but
  recorded nothing — and the in-app deterministic safety net measures a sitting's
  age from `startedAt` itself, on every tick of any live surface. So the sitting
  was still killed at start + 90 minutes, and merely *opening* the timer was
  enough to trigger it (owner report, 26 Jul 2026). The answer is now persisted
  (`active_session_confirmed_at`) and one pure `readingSessionDeadline` /
  `readingSessionOverdue` pair is consulted by the in-app guard *and* the
  background task. Corollary: a background isolate can stop a sitting but cannot
  reach the iOS Live Activity channel, so the lock-screen card kept counting a
  sitting that was already over — give the activity a `staleDate` at the deadline
  so iOS renders it as outdated instead of confidently wrong.
- **A `dark:`/`light:` styling flag outlives the background it was written for.**
  The timer's wax-seal face passed `dark: true` to the shared page-entry block
  with the comment "the wax-seal face sits on the night background" — it hadn't
  since the face was rebuilt on `AppColors.paper`, so every control was drawn for
  a background it no longer had: a near-black total box on the pale gold card, a
  washed-pink numeral instead of oxblood, a dark slab for the anchor line (owner
  report, 26 Jul 2026). Nothing failed; it just looked wrong, and only on the
  variant with no page count, which is why it survived. When a screen's
  background changes, grep the flags its children take.
- **A screen must not take its data from route `extra` when an OS-level entry
  point can reach it.** `extra` is a snapshot the *caller* assembles, and the
  callers that matter most can't assemble one: a tap on the iOS Live Activity or
  the Android ongoing notification navigates by URL with no extra at all. The
  reading timer took title/cover/`pageCount` that way, so a sitting opened from
  the lock screen believed the book had no page count and asked for the total on
  **every** stop — while the book page, reading the same book from Drift, showed
  it correctly (owner report, 26 Jul 2026). Route arguments are a first-frame
  hint; the database is the answer. The same applies to a pre-computed provider
  snapshot handed across an await (`quickStopSession` had the identical bug from
  an autoDispose provider that had not emitted).
- **Two different records need two different guards.** The timer's `_savePage`
  skipped writing *both* the sitting's `pageEnd` and the entry's `currentPage`
  under one "has the page changed?" check, so a sitting that ended on the page
  the entry already held wrote neither — the reading log said "no page noted"
  while the progress bar showed the page (owner report, 26 Jul 2026). That is
  the *normal* shape of a first sitting, because readers set their page before
  starting the clock. A guard that means "progress didn't move" must never also
  suppress the log entry that says where a sitting ended.
- **Flutter's engine hands an incoming deep link straight to go_router as a
  *whole URI* — scheme and host included — so a custom-scheme link needs a route
  the router can match, or it lands on "Page Not Found".** The iOS Live Activity's
  tap URL (`in.kitabi.kitabi://reading-timer/:id`) went nowhere near
  `DeepLinkListener`/app_links, which is where all its tests were pointed — they
  passed against a feature that was broken on the phone (owner report, 26 Jul 2026).
  Rewrite such a URI in the router's **top-level `redirect`** (it runs even for an
  unmatched location, so it can rescue one), not only in the app_links listener.
  Corollaries: the engine's delivery is a *replace*, not a push, so a top-level
  route reached that way has nothing beneath it — `pop()` strands the reader and
  every exit needs `canPop() ? pop() : go(home)`; and any test for a deep link must
  drive the **router** with the raw URI, because a test against the listener never
  touches the path the OS actually uses.
- **"Fixed the deep link" means fixed for every route the OS can reach, not the
  one in the bug report.** The 26 Jul lesson above — engine delivery is a
  *replace*, so `pop()` strands the reader and every exit needs
  `canPop() ? pop() : go(home)` — was applied to the reading timer and the book
  page, and the *other two share targets never got it*: a shared author or
  publisher link opened correctly and then had no way out at all (owner report,
  14 Aug 2026). The same report's second half was the mirror image: the router's
  redirect rewrote the Live Activity's custom-scheme URI but not `https://kitabi.in/{b,a,p}/…`,
  so a **cold-start** share link was swallowed by the boot gate while a warm one
  worked (the listener saw that one). One rule now — `externalRouteFor` — is
  consulted by both the redirect and `DeepLinkListener`, because two parsers for
  "what is one of our links" is what let them disagree. When fixing a deep-link
  bug, grep every route reachable from outside and check both halves: does it
  *open*, and can the reader *leave*.
- **An external navigation (notification tap, deep link) must never push a route
  that's already on top.** Tapping the live reading notification while the timer was
  open stacked a second copy; when the top one stopped the sitting, the *buried*
  copy's "someone else stopped this" guard fired and popped the top one, so
  Stop & log threw the reader out to Home instead of showing the page question
  (26 Jul 2026). The guard belongs in `navigateFromExternal`, not in each screen —
  every route those handlers reach has the same hazard.
- **A new iOS app-extension target can be added without opening Xcode** — CocoaPods
  already brings the `xcodeproj` Ruby gem (1.28), so a ~60-line script creates the
  target, its build configs, the shared source file membership (a Live Activity's
  `ActivityAttributes` has to compile into *both* app and widget), the frameworks and
  the "Embed App Extensions" entry, idempotently. Copy the settings from the
  `NotificationService` target that's already there — including
  `EXCLUDED_ARCHS[sdk=iphonesimulator*] = arm64`, or the extension's arch set won't
  match the app's Rosetta-simulator build and embedding fails.
- **An Anthropic reply's `content[0]` is not necessarily a text block, and
  `max_tokens` caps thinking *and* prose together.** `resp.json()["content"][0]["text"]`
  500'd `/catalog/cover-extract` in production with `KeyError: 'text'` (26 Jul 2026):
  `content` is a list of *typed* blocks, and a model that thinks emits
  `{"type": "thinking", "thinking", "signature"}` first — no `text` key anywhere in it.
  Thinking is on by default from Sonnet 5 / Opus 5 onward, so the bump from Haiku 4.5
  to `claude-sonnet-5` (commit ced7bd6) armed the bug without changing a line of the
  parsing. Two rules: walk the blocks and take the first one whose `type == "text"`
  (`anthropic_client.reply_text`, shared by recs + extraction) — a refusal is HTTP 200
  with an *empty* `content`, so "" must degrade to "no fields", never a 500; and a
  budget sized for prose (1024) is spent by thinking before any prose is written, so a
  transcription-style call should send `thinking: {"type": "disabled"}` explicitly
  rather than inherit the model's default. Reproduced live before fixing — a thinking
  reply really does come back as `blocks=['thinking']`, `stop_reason=max_tokens`.
- **A renderer that needs *both* ends of a range erases the end it actually has.**
  Third report in the same family, and the first one that was purely a display bug:
  a book with no page count, the page and the total typed on the very first sitting —
  progress showed p. 120, the reading log said "Page not noted" (owner report,
  31 Jul 2026). The write path was correct all along (an E2E test through the real
  timer screen passed on the unfixed code); `SessionLogRow` simply gated its whole
  page line on `pageStart != null && pageEnd != null`, and a first sitting on a book
  with no recorded progress has no start page — nothing knows where the reader began.
  Same guard also blanked a sitting that ended where it began, whose page the 26 Jul
  fix had just made sure to record. The end page is what the *reader* supplies; the
  start is context the app happens to have. Render the half you hold ("Ended on
  p. 120") and drop only the figure that genuinely can't be derived (the +N gain).
  Corollary for diagnosis: "it's in the progress bar but not the log" points at the
  *reader*, not the writer — prove which half is broken with a test through the real
  screen before changing either.
- **A test fixture written from the renderer instead of from the schema tests
  nothing — it just makes the code agree with itself.** Every public review ever
  written was invisible on the web: `PublicReviewOut` sends `body`, and
  `book.js`, `more.js` and `jsonld.js` all read `r.text`, so a review rendered as
  a card with the reviewer's name, avatar, date and stars and *nothing under
  them* — and the JSON-LD shipped a `Review` with a rating but no `reviewBody`,
  so Google never had the text either (owner report, 9 Aug 2026,
  /book/avalkkoppam). `cases.js` had an assertion literally named "the review
  text is in the HTML" that passed the whole time, because its fixtures said
  `text:` too. A fixture is a claim about what the API sends; write it from
  `api/app/schemas/`, never by copying the field the renderer happens to read.
  Corollary: the app was fine (`review['body']`), which is the tell — one client
  right and one wrong on the same endpoint means a client-side name, not a
  server bug. Verify a renderer fix by feeding it the **real** payload
  (`curl api.kitabi.in/public/...` → `renderBook`), not only a fixture.
- **An HTML attribute interpolated as a template *value* ships entity-escaped —
  and can pass every visual check anyway.** Every chip row on the web platform
  wrote `${active ? ' aria-current="true"' : ''}`, so production served
  `aria-current=&quot;true&quot;` (9 Aug 2026). It *looked* correct because the
  stylesheet matches on presence (`[aria-current]`), and an unquoted-attribute
  parse keeps the attribute present with garbage in its value — only assistive
  tech saw the difference. Attributes must go through `raw()`
  (`_lib/pages/discover.js` `mark()` is the pattern); `cases.js` now asserts
  `aria-current=&quot;` never appears. Corollary: the JSC test harness shims
  Workers globals — `URL`, and now `URLSearchParams` — so a renderer using a
  Web API that JavaScriptCore lacks fails the harness, not production; extend
  the shim in `tests/run.py` rather than avoiding the API.
- **`editions[0]` is a *representative*, never an answer.** Three of six add-book
  reports in one session were the same bug wearing different clothes (13 Aug 2026):
  scanning a 240-page reprint shelved the 55-page first edition, "I own this one"
  shelved whichever printing was catalogued first, and adding an edition left the
  reader on the parent so the next "Add to library" shelved that. `cover_edition`
  exists precisely because a *display* pick must be deterministic — but a pick the
  reader will own has to be the reader's, and page count is what makes it visible
  (every progress figure is a lie against the wrong printing). Two rules: an
  endpoint that resolved a specific row must **say which** — `GET /catalog/isbn/{isbn}`
  had the matched Edition in hand and returned the whole Work without naming it, so
  the app could only guess; and any "put this on my shelf" path must ask when the
  work has more than one printing (`chooseEdition`).
- **A client-side `allowCreate: false` can quietly repeal a server-side product
  decision, and nothing fails.** `WORK_FORMS` is documented in
  `api/app/schemas/catalog.py` as *suggested, not closed* — "a reader whose book is a
  form we didn't think of must be able to say so" — and `normalize_form` folds free
  values instead of rejecting them. The Type picker sheet shipped closed anyway, so
  a reader holding the തിരക്കഥ of a novel had nowhere to put it (13 Aug 2026). The
  tells were all there and all passive: orphaned `formTypeOther*` l10n strings from
  the affordance the sheet replaced, and a widget test named "the type sheet is a
  **closed vocabulary**" that pinned the regression in place. A test asserting an
  absence is only as good as the decision behind it — when a comment on one side
  says "open" and the code on the other says "closed", the code is not the spec.
- **"The app ignores its own event" is not available to a *visible* push — the OS
  draws it before any app code runs.** The cross-device reading sitting fanned its
  "…is being timed on your other device" notification to every token on the account
  and echoed `device_id` for the originating install to filter on; that install got
  the banner anyway, about itself (owner report, 14 Aug 2026). Client-side filtering
  only ever reaches the *foreground* `onMessage` path. Anything a self-fan-out must
  not show has to be excluded server-side, which means the server has to know which
  device each token belongs to (`device_tokens.device_id`, nullable → treated as
  "some other device", and matched with `IS DISTINCT FROM` so a NULL row isn't
  dropped from every fan-out by `!=`). Exclude by *device*, never by token: one
  install holds several tokens over its life.
- **Adding a network round trip inside `stop()` turned a local state change into a
  window several frames wide — and a guard that reads state as an event fired in
  it.** Publishing the stop to the reader's other devices put an awaited HTTP call
  between "session cleared" and "wax-seal face shown", so the timer screen's "this
  sitting was stopped somewhere else" check saw the empty session, popped the route,
  and Stop & log returned the reader to the book page with no page question (owner
  report, 14 Aug 2026 — the third time this screen has lost that question, after the
  16 Jul back-gesture and the 26 Jul stacked-route cases). Any guard that infers an
  *event* ("someone else did this") from *state* ("nothing is running") needs an
  explicit "…and it wasn't me" flag, set synchronously before the first await —
  never via `setState`. Two testing corollaries, both cost a cycle here: a popped
  route stays in the widget tree while its transition plays, so `find.byType` still
  finds the screen for several frames — assert on
  `router.routerDelegate.currentConfiguration.matches.last.matchedLocation`; and a
  test for a pop guard proves nothing unless the screen is *pushed onto something*,
  since `canPop()` is false at the root and the bug cannot fire.
- **A tap handler's `else` branch is a routing decision, and it will outlive the
  two cases it was written for.** Notification taps sent lending pushes to the
  ledger and *everything else* to the connections inbox — so tapping "your sitting
  is running" opened a list of connection requests (owner report, 14 Aug 2026). Map
  every type explicitly and default to Home; a type with no home of its own must not
  inherit an unrelated feature's screen. The rule now lives in a pure `pushTapRoute`
  (`push_service.dart`) for the same reason `readingTimerRouteFor` does: the whole
  feature is the rule, and it can't be tested through the plugin. Related: a tap is
  the one path where this device has *not* seen the event yet — a background push
  runs no app code — so a screen that renders from local state needs the pull to
  land before it opens, or it will bounce the reader straight back out.
- **"Offline" has to be a *distinguishable* outcome, or every retry budget in the
  app quietly spends itself on a phone with no signal.** Four separate failures,
  one missing distinction (15 Aug 2026). The sync queue counted a push that never
  left the device as a failed attempt, so five mutations in airplane mode burned an
  op's five retries and marked it `error` for good — a day's reading arriving as a
  red banner instead of a sync. `POST /auth/bootstrap` failing offline put a
  signed-in reader on the splash screen *permanently*, locked out of a library
  sitting on the device, because the gate that holds an unproven account (13 Aug)
  cannot tell "the row may not exist" from "we couldn't ask". A token refresh that
  failed on a dropped connection was read as a dead refresh token and **signed the
  reader out**, unsynced queue and all. And `Dio` had no timeouts at all, so a
  network that is joined but goes nowhere (hotel wifi, captive portal) stalled every
  awaited call for the OS socket default — minutes — including ones on the Stop &
  log path. `isOfflineError` (`api_client.dart`) is the one classifier now: no
  response object and a connection/timeout error means *nobody has said anything*,
  which is never grounds to conclude, punish or lock out. Corollary for gates: when
  a check exists to prove a fact, record the proof (`bootstrapped_user_id`) so being
  offline later can't unprove it.
- **A running sitting is device-local by design — so anything the wire says about
  it is a *claim*, and anything pointing at it is a reference to a row the server
  doesn't have.** Both halves bit on the same day (15 Aug 2026). Stopping a sitting
  while offline never reached `DELETE /active-session`, so the account still showed
  it running and the next `pullAndApply` dutifully **adopted it back**: clock
  restarted from the original start, lock-screen notification returned over a
  sitting the reader had finished, and stopping it again wrote a second row for one
  sitting (background auto-stops never published at all, so they did it every time).
  A stop now leaves `active_session_pending_stop`, which the pull reads as "already
  over here" and retries until the delete lands. The mirror image: a note written
  *during* a sitting names a `reading_sessions` id that only becomes a row on stop,
  so `/sync/push` rejected it `invalid_reference` and the client dropped it — every
  note taken while a timer ran stayed on that phone forever. The link is now
  withheld from the wire until `logSession` creates the row, then sent as an update
  behind it. `test_sync.py` had a passing test for the mid-sitting note that pushed
  the session op *first* — an order no client can produce; a fixture agreeing with
  the server instead of with the app (same shape as the 9 Aug review-body fixture).
- **A field the client deliberately withholds comes back as a null that overwrites
  the thing it was withholding.** The fix immediately above sends a mid-sitting note
  without its `session_id`; the server applies it and the *same sync pass* pulls the
  row back carrying that null, which `insertOnConflictUpdate` wrote straight through
  — severing the note from its sitting on the device that wrote it, emptying the
  timer's own "notes of this sitting" list while the reader watched, and leaving
  `logSession` nothing to link. A green unit suite had already blessed the deferral;
  **the emulator found this within ten minutes of the first real sitting**, which is
  the whole argument for the on-device pass. Rule: whenever a push omits a field on
  purpose, ask what the next *pull* does with it. If no code path can legitimately
  clear a column, an incoming null means "not told yet" — `Value.absent()`, never
  `Value(null)`.
- **A guard that says "never throw away what we started" needs to know when the
  account has heard of it — otherwise it only works in one direction.** The shared
  timer marked a sitting with `active_session_mirrored_id` **only on adopt**, so the
  device that *started* one never recorded that its publish had succeeded. When the
  other device stopped it, the empty server read as "we haven't published ours yet"
  and the starting device kept counting: clock running, lock-screen notification up,
  over a sitting already logged — and already pulled back onto that very device,
  which is the tell. `publishStart` now records the id on success (and only on
  success: an offline start must stay unpublished, because that is exactly the
  sitting the pull must never delete). **Found with two emulators on one account,
  15 Aug 2026** — a second device is the only thing that can find this class of bug,
  and the single-device pass had gone green over it an hour earlier.
- **Which device performs an action is not the same as which device holds the data
  the action needs.** Linking a mid-sitting note to its sitting was done where the
  sitting is *logged* — but the reader's other device can be the one that stops it
  (that is the point of a shared timer), and it runs the stop against its own
  database, where the note had arrived carrying no link at all. So the note stayed
  attached on the phone that wrote it and detached everywhere else, permanently.
  The work now belongs to the device that *wrote* the note, driven by a remembered
  `{noteId: sessionId}` map in `key_values` (`note_session_links.dart`) that the
  pull can't clobber, replayed after every pull — so it lands whenever the sitting
  reaches that device, no matter who ended it.
- **A publish that happens once, at the moment of the action, is a publish that
  never happens offline.** The running sitting is announced to the account by a
  single `PUT /active-session` inside `start()`; with no network it fails
  silently and *nothing retried it*, so a sitting begun offline stayed local
  for good. The reader's other device showed the book as "reading" — that rides
  the sync queue, which does retry — with no timer beside it (owner report,
  15 Aug 2026). The stop half had already been given a retry note; the start
  half had none, and the asymmetry was invisible because both look like
  fire-and-forget at the call site. `pullAndApply` now publishes an unpublished
  local sitting when it finds the account reachable and empty, which is exactly
  the moment that fact is known. Corollary, and the reason the fix alone was not
  enough: **regaining signal is not a lifecycle event.** Reconciliation ran on
  foreground-resume and on push, so coming back online with the app already open
  was neither — the connectivity listener drained the queue and nothing else.
  Anything that reconciles with the server needs a hook there too.
- **One key answering two questions gives a wrong answer to the newer one.**
  `active_session_mirrored_id` began as "this sitting came from another device";
  the 15 Aug fix made a successful publish set it too, so it came to mean "the
  account knows about this sitting". Both readings were right for the code that
  existed. When two sittings could collide and the loser had to be *logged*
  rather than dropped, "is this ours?" was asked of that same key — and a
  sitting we started and published reads identically to one we adopted, so the
  reader's own reading would have been discarded unlogged. Split into
  `active_session_adopted_id`. When a flag's meaning widens, check every
  existing reader of it before adding one more.
- **A conflict rule is only finished when it converges.** "The older start wins"
  is easy to implement on one device and easy to get wrong across two: a rule
  that merely *prefers* the older sitting can have both devices trade it back
  and forth forever. The test that matters runs both devices against one shared
  server row and pulls repeatedly, asserting they settle on the same sitting and
  that the loser is logged exactly once — not once per pull.
- **Drift's `TableMigration` copies every current-shape column it isn't told is
  new — it never inspects what the old table actually has.** The v12
  ratings/reviews rebuild shipped without `newColumns: [seriesId]`, emitting
  `SELECT "series_id" FROM ratings` against pre-v12 tables. On macOS the system
  sqlite that `flutter test` links has double-quoted-string literals enabled, so
  the unknown identifier silently became the *string* `'series_id'` and every
  host test passed; the sqlite compiled into devices has DQS off, so every real
  upgrade from ≤v11 errored at open — and because migration steps were also not
  idempotent (a re-run `addColumn` is fatal) and two engines (app + workmanager)
  migrate the same file concurrently without serialization, the failure left the
  on-device DB half-migrated with a stale `user_version` and the app permanently
  wedged on the splash screen (caught on-emulator 25 Aug 2026, before any store
  update shipped it). The rules now enforced in `database.dart` +
  `migration_wedge_test.dart`: steps run oldest-first and every step is
  guarded/idempotent, the step list re-runs after a backoff when a concurrent
  migrator interferes, and migration tests set
  `doubleQuotedStringLiterals = false` so the host harness matches device
  sqlite. Corollary: green `flutter test` on a Mac is not evidence about the
  sqlite your readers actually run.
- **Three best-effort cleanups in one `try` is one cleanup with two decoys.**
  `stopAndLogActiveSession` cancelled the check-in, cancelled the enforcement task
  and ended the lock-screen clock inside a single `try {} catch (_) {}` — so the
  first that threw silently cancelled the two after it, and the clock (last in line,
  and the only one the reader can see) was the one left counting a stopped sitting.
  Its early `return null` skipped all three, which is exactly the path a second stop
  takes after a background isolate already logged the sitting. Independent cleanups
  get independent failures, and a teardown that a *later* code path may need must
  not be last behind things that can throw.
- **The GoTrue SDK's own session-refresh reports "couldn't tell" as a *stream
  error*, not a data event — and every `await ref.watch(authStateProvider.future)`
  downstream reads that literally.** Recovering an expired cached session at cold
  start, or the periodic background auto-refresh, calls Supabase's own
  `notifyException` on failure, which pushes the raw exception onto
  `onAuthStateChange` — a real sign-out, by contrast, always arrives as a
  `signedOut` *data* event. The router's own `valueOrNull` check (CLAUDE.md, the
  bootstrap gate) tolerates this fine for an already-signed-in reader, but
  `sessionContextProvider`, `bootstrapProvider`, `meProvider` and everything
  chained off them — which is most of Home — all do
  `await ref.watch(authStateProvider.future)`, and `.future` throws whenever the
  *current* AsyncValue is sitting in error, previous value or not. A reader
  already happily on Home whose phone lost signal right as a background token
  refresh ticked watched the library list die into a "connection error" card
  (owner report, 20 Aug 2026) — nothing about their library ever needed the
  network; Drift had it the whole time, and only auth's own stream was the
  problem. Fix: `SupabaseAuthService.authStateChanges` now swallows exactly this
  class of error (`isRetryableAuthError` — `AuthRetryableFetchException` or
  `SocketException`, the same two types `api_client.dart`'s `_isUnreachable`
  already treats as "couldn't ask, not a real answer") before it reaches
  `authStateProvider` at all, so every `.future` awaiter downstream keeps resting
  on its last known value instead of throwing raw "offline" as its own frame.
  This turned out to close the cold-start case too, not only "already on
  Home" — no separate local-fallback code needed. Reading `supabase_flutter`'s
  own `SupabaseAuth.initialize()` (awaited by `Supabase.initialize()`, so this
  always finishes before the app's first widget subscribes to anything) shows
  it *always* calls `setInitialSession` on the persisted session first —
  synchronous, from local storage, no expiry check, no network — and only
  *after* that completes does it separately (un-awaited) kick off
  `recoverSession()`, which is what actually checks expiry and attempts the
  network refresh. So a device that has ever signed in gets its
  stale-but-real cached user as `authStateProvider`'s very first value
  unconditionally, offline or not; the network-dependent refresh's possible
  failure structurally can only land *after* that, as a second event — which
  is exactly the "data, then a swallowed retryable error" sequence the fix
  above already handles. Pinned by the "cold start" test in
  `auth_stream_retryable_error_test.dart`, alongside the "mid-session" one.
- **A reconciliation wired only to `didChangeAppLifecycleState` never runs at
  launch** — that callback is not called for the state the app *starts* in. The
  lock-screen reading clock had two takedown paths: every stop calls
  `end()` (best-effort, and an iOS background isolate has no channel to call it
  on at all), and `reconcile()` on foreground resume. On a cold start neither
  fires: `ActiveSessionController._hydrate()` found no sitting and simply
  `return`ed, so a clock left behind by a stop that couldn't reach the channel
  survived every relaunch (owner report, 29 Aug 2026 — the notification stayed
  after finishing a book from the timer). Hydration now reads storage as the
  truth in *both* directions: nothing stored means state null and the surface
  ends. Corollary for anything else built this way — resume is not launch, and
  a surface only ever taken down by an event needs a takedown on the read that
  discovers it shouldn't be there.
- **A guard that gives up on a screen has to leave the same way the screen's own
  exit does.** The timer's "no sitting for this book — nothing to show here"
  check popped via `if (context.canPop()) context.pop()`, so on the one entry
  point that matters most it did *nothing*: a notification tap on a cold start
  is delivered as a replace, `canPop()` is false, and the reader sat on the
  running face with no session behind it — a sweeping hand over a clock frozen
  at 0:00, with no way off the screen. Same report; same rule as 14 Aug
  (`canPop() ? pop() : go(home)`), which `_leave()` had and this guard hadn't.
  Two things that fell out of fixing it: the guard was only *safe* before
  because `canPop()` was false — it fires on frame one, when `state == null`
  still means "storage hasn't answered yet", so giving it real teeth also meant
  giving it `ActiveSessionController.hydrated` to wait on; and a screen reached
  from a stale surface should take that surface down on its way out, since
  arriving at a sitting that doesn't exist is proof the thing that invited you
  is wrong. Pinned by `reading_timer_dead_session_test.dart`, whose second case
  makes the timer route the *whole* stack — with anything beneath it the bug
  cannot appear.
- **Read your own note before the network call it is being compared against.**
  `pullAndApply` fetched the account's running sitting and only *then* read
  `active_session_pending_stop`. A stop fires its DELETE unawaited and clears
  that note the moment it lands, so a GET issued just before the DELETE and
  answered just after came back holding the stopped sitting with no note left
  to recognise it by — and it was adopted straight back onto the device that
  had already logged it, lock-screen clock and all. State read after an await
  is state from a different moment than the answer it is judging.
- **A bottom-nav tab cannot be `push`ed — it is a `StatefulShellRoute` branch,
  and pushing one moves the page without moving the shell.** go_router renders
  the branch's screen, but `currentConfiguration.uri` and
  `navigationShell.currentIndex` both stay where they were, so the nav bar goes
  on highlighting the old tab and every later resolution — the duplicate guard
  in `navigateFromExternal`, the redirect, `goBranch` — reasons from a location
  the reader has left. `pushTapRoute` returns `/lending` for all three lending
  pushes, the one tab root an external tap can reach, so "A lent you a book"
  landed the borrower under a nav bar that said Home at a URL that said `/home`
  (owner report, 29 Aug 2026). `navigateFromExternal` now `go`es to anything in
  `shellTabRoutes` and pushes everything else — push stays right for the
  top-level routes, which have to be poppable. A probe settles which kind of
  route you are looking at faster than reading the route table: print `uri`,
  `matches.last.matchedLocation` and `currentIndex` after the navigation, and a
  branch root shows all three disagreeing with the screen on display.
- **Read the notification that launched the app before doing anything that can
  block.** `PushService.start` awaited permission, then the token — which on
  iOS polls up to twenty seconds for APNs and then makes a network call to
  register — and only then called `getInitialMessage()`. So the message that
  *opened the app* was read long after the router had booted, the splash gate
  had already given up on `pendingExternalTarget` and sent the reader to Home,
  and the notification's own screen arrived seconds later or not at all. The
  park-and-honour design was sound; nothing ever reached it in time.
  `getInitialMessage()` and `onMessageOpenedApp` need neither permission nor a
  token — the notification has already been delivered and tapped — so they go
  first, and registration follows behind them.
- **An optional payload is a payload nobody passes.** A local notification
  carries one opaque `payload` string, and it was an *unqualified* library
  entry id — so the tap handler had exactly one destination it could name, the
  reading timer, and any other family of notification had nothing to say. Both
  lending due-date reminders were therefore scheduled with no payload at all,
  and `scheduleReminder` simply had no parameter for one: tapping a reminder
  read null, returned, and left the app wherever it had been (owner report,
  29 Aug 2026). The scheme is now `<target>:<id>`
  (`core/notifications/notification_payload.dart`, with `localNotificationRoute`
  as the one route rule — pure and top-level for the same reason `pushTapRoute`
  and `readingTimerRouteFor` are), and `payload` is **required** on
  `scheduleReminder` so a new caller has to decide rather than default to
  silence. Two things it forces you to get right: an unqualified payload must
  still parse as the reading timer, because check-ins scheduled before the
  change are sitting in the OS's own queue on real devices and may be delivered
  days later; and a notification that genuinely can't name a screen (the
  auto-stop notice when the book isn't cached) must return null and stay put,
  never fall back to an unrelated one — the same rule `pushTapRoute` learned on
  14 Aug. Note which screen each family wants: the "stopped while you were
  away" notice is *about* a sitting that has ended, so the timer is the one
  place it must not open.
- **A short CSS class name on a site with one global stylesheet is a land grab.**
  The cover viewer's overlay was written as `.lb` (lightbox) with a bare
  `.lb{display:none}` — and `lb` was already the ratings histogram's row label
  (`<span class="lb">5 ★</span>` in `book.js` and `more.js`), so that one rule
  would have hidden every "5 ★ / 4 ★ / …" label on every book page and every
  reviews page (1 Sep 2026). The stylesheet is inlined into every page, so
  *every* selector here is global; the tell was a renderer test asserting that
  a typeset-cover page carries no viewer, which failed by finding the
  histogram's own markup. Prefix a component's classes (`cvv/cvt/cvs/cvx/cvn`)
  and grep the two-letter name before taking it. Same session, same file, a
  second CSS trap worth remembering: **`scroll-behavior:smooth` and
  `scroll-snap-type: … mandatory` fight each other** — a fragment jump to a
  slide animates and is then snapped straight back where it started, so the
  arrows silently did nothing while the URL changed correctly. Drop the smooth
  scroll; the snap does the animation.
- **The association files and the app's own link rule are one decision written
  in two places — and only one of them was updated when the site's URLs
  changed.** `.well-known/apple-app-site-association` claims `/book/*`,
  `/author/*` and `/publisher/*` (the canonical slug URLs the web platform
  serves today) alongside the original `/b|a|p/<uuid>` share links, while
  `shareRouteFor` in the app recognised only the short spelling. So iOS handed
  the app a URL it had no rule for: the first tap on Safari's "Open in the
  Kitabi app" banner raised Kitabi on **Home** (the redirect found no external
  route, fell through to the boot gates and landed on the default), and the
  second — app already warm, gates all passing — let the whole URI reach
  go_router, which showed *"GoException: no routes for location:
  https://kitabi.in/book/murder-on-the-orient-express"* (owner report,
  1 Sep 2026). Claiming a URL pattern is a promise the app has to keep; the
  Android manifest, the AASA and `shareRouteFor` must be edited together, and
  the manifest was the third copy — it had never claimed the slug URLs at all,
  so the same link opened Chrome on Android. Second half, and the reason it
  isn't a one-line fix: the canonical URL names a row by **slug**, and every
  in-app screen and catalog endpoint addresses it by UUID. Only the server
  knows which row a slug names, so `GET /public/id/{kind}/{key}` resolves both
  key forms with the same rule the public pages use, and `CatalogLinkResolver`
  sits in front of the three link routes — passing a UUID straight through, so
  a `/b/<uuid>` link still costs no round trip. Corollary for anything else
  reachable from outside: a *display* URL that changes shape is a deep-link
  change, even when no app code was touched in the same commit.
- **A `flutter run` debug build cannot test a cold start on a physical iPhone —
  and the failure mimics a wedge in our own boot gate.** Killing the app kills
  the tool, and reopening the debug build from the home screen sticks on the
  splash forever: iOS 26 won't let Dart JIT without a debugger attached, so not
  one line of app code runs. Every cold-start check begins "fully kill the app",
  so on-device verification of the launch path needs `--release`, which survives
  the tooling being killed and relaunches from the home screen and from
  notification taps (no VM Service then, so those results are observational —
  say so rather than dressing them up). Two things that cost a session on
  29 Aug 2026: **`flutter run` will not attach while Xcode is open** (it
  installs and launches, then never discovers the Dart VM Service — quitting
  Xcode fixed it outright), and **"stuck on the splash" is visually ambiguous
  by design**, because `flutter_native_splash` is deliberately configured to
  match what `SplashScreen` renders. A *static* logo means Dart never started;
  the in-app one animates (logo scales in, the name rises, the gold line draws
  across, ~1.6s). Ask which one before debugging the boot gate.
- **A surface the reader is watching must never be updated at the end of a
  chain of Drift writes — the sync engine's pull holds an exclusive
  `db.transaction`, and drift queues every query issued after it.** Two
  complaints, one mechanism, both random because the variable is whether a sync
  pass happened to be mid-pull (owner report, 3 Sep 2026: "the live
  notification bar is not getting removed for a few seconds after stopping",
  and "sometimes when I start the timer, the clock is not moving").
  `stopAndLogActiveSession` took the lock-screen clock down *last*, behind
  `logSession`, `publishPendingNoteLinks`, seven key_values writes and two
  plugin cancels — and `logSession`'s own `enqueue` fires the sync trigger, so
  the tail of the stop waited on a pull the stop itself had started. `start()`
  was the mirror: it published `state` — the thing every clock surface renders
  from — only after five sequential key_values writes, so a start landing
  during a pull left the mini-bar, Home's live card and the timer face reading
  a session of null: a sweeping hand over a frozen 0:00. `stop()` already had
  the rule written on it ("cleared synchronously, before the first await — the
  clock stops when the reader says it stops, everything after this is filing")
  and `start()` simply never got it. Two things fall out of applying it: the
  in-memory state and key_values now legitimately disagree for the length of
  those writes, which is exactly what the safety net reads as "stopped
  elsewhere", so starting needs the same `isSettling` guard stopping has had
  since 16 Jul; and a teardown moved to the front still wants a repeat at the
  back, because a `reconcile()` on resume can put the surface back while the
  rows are still being cleared. Proof, not inference: a 400ms
  `db.transaction` delays an unrelated `getValue` on the same database by
  365ms.
- **The 29 Aug "state read after an await is from a different moment than the
  answer it is judging" fix was applied to one of the two values it compares.**
  `pullAndApply` snapshots `pendingStopId` before its GET and reads `localId`
  *after* it — so a sitting started while the request was in the air was judged
  against an answer that predates it. With `publishStart` landing in the same
  window, `mirrored == localId` held and an empty answer read as "stopped on
  the other device": the timer the reader had just started was cleared,
  unlogged. The mirror case is worse — a GET that comes back holding the
  sitting they stopped a moment earlier makes the older-start rule *log* their
  seconds-old new sitting and adopt the dead row over it. When a rule compares
  a remote answer with local state, every local value in the comparison has to
  be as old as the answer; re-read the anchor afterwards and bail if it moved,
  rather than snapshotting one field at a time as each bug arrives.
- **`ActivityKit`'s `Activity.end` is async, so `Task { for a in
  Activity.activities { await a.end(…) } }` ends whatever is running *when the
  task gets around to it*.** `ReadingActivityController.start` called `end()`
  to clear a stale card and then synchronously requested the new one — and when
  the detached task ran second, its enumeration included the activity just
  created and dismissed the live clock moments after starting it. Capture the
  list of activities to dismiss synchronously, before the `request`, and end
  only those.
- **A prompt written as a private method on the screen that happens to trigger
  it is a prompt with one door, and the feature has several.** The
  finished-reading review nudge lived on the book page's reading card, keyed on
  its own status row picking "Read" — so every other way a book becomes
  finished passed in silence: the timer's "I finished the book", the quick-stop
  sheet's tick, and above all simply typing the last page, which
  `autoFinishIfOnLastPage` has treated as finishing a book since it was written
  (owner report, 3 Sep 2026). Same shape as the 19 Jul total-pages field and
  the four progress surfaces: the rule went in one place, the moment it belongs
  to has five. It is `maybePromptForReview` now, beside `markBookFinished` —
  which had to grow a `justFinished` so callers can tell "the reader has just
  finished a book" (a one-time event) from "this idempotent call ran again on a
  book already Read". Two things the extraction forces: the shared prompt takes
  a `ProviderContainer` and a root-navigator context rather than a `WidgetRef`,
  because most of the surfaces that finish a book are surfaces that *vanish*
  when they do; and it resolves the Work id from the catalog mirror while
  letting a caller that already knows it pass it in — the book page's own route
  carries it, and a nudge that needed the mirror to be warm would silently skip
  the very screen it used to work on.
- **Two endpoints beside each other with different rules is not a design; it is
  the older one never being revisited.** `PATCH /catalog/works/{id}` has queued a
  stranger's blurb change for the book's contributor since 8 Jul 2026;
  `PATCH /catalog/editions/{id}`, twenty lines further down the same router,
  called `update_edition` directly — so any signed-in reader could rewrite any
  printing's ISBN, page count, format, publisher and cover URLs live, with no
  approval and no record (5 Sep 2026). The gate was written when the Work was
  the interesting row, and the fields that migrated to the Edition (rule 17)
  never took it with them; the asymmetry is what made the add-book fork's
  "improve this entry" path write a reader's captured cover onto a stranger's
  edition. Three things the fix pins down. A permission question gets **one**
  predicate — `_may_edit` now answers "whose row is this?" for the work edit,
  the edition edit and the reader-facing merge, and `_may_absorb`'s own comment
  had been claiming that was already true. A shared queue beats a second table
  when the *approver* is the same person: an Edition has no
  `created_by_user_id`, so the approver was always the Work's contributor, and
  a nullable `edition_id` on `work_revisions` left the inbox, the admin
  escalation and `decide_revision` unchanged. And a gate must not turn a
  *refusal* into a promise: an ISBN that already names another book is still an
  immediate 409, because the app answers a conflict by offering that book, and
  queuing it instead would swap that offer for a "sent for approval" about an
  edit that could never apply — while a *genuinely wrong* ISBN still queues,
  since that judgement belongs to the contributor, not to a hard block.
  Corollary for the client: a response shape that grows a wrapper needs the
  *old* shape tolerated on the way in (`ApiClient.editionFrom` /
  `appliedLive`), and every caller re-read — three call sites shared this
  endpoint and only one of them was in the bug report.
- **A merge is a decision, and it only holds on the paths that ask about it.**
  Folding "ഡി സി ബുക്സ്" into "DC Books" in the console repointed the editions
  and gave the loser's URL its 301 — and the very next photographed Malayalam
  cover was offered "ഡി സി ബുക്സ്" all over again (owner report, 4 Sep 2026).
  `publisher_by_name`, the lookup behind that suggestion, filtered
  `deleted_at IS NULL`, and a merge soft-deletes the loser: the one row that
  knew the two spellings are one house was invisible to exactly the code that
  needed it. Nothing else can know — the names share neither letters nor
  script, so no fold, transliteration or trigram will ever bridge them; the
  pointer a human set is the whole of the evidence. The rule is one function
  now (`merge_service.canonical`) and every path that turns a name or a
  remembered id back into a row goes through it: the extractor's suggestions
  (publisher, authors *and* series), the three pickers' typeaheads, the "add
  new" endpoints, and the id paths on save — an id can be older than the merge,
  in a form left open or an install that hasn't searched since. Two things it
  clarified. Filtering the losers out of a typeahead is only *half* a decision:
  it stops the dead row being shown, and leaves the reader who spells the house
  the way their cover does with an empty list whose one obvious next move is to
  create it again — a merged row should answer *as* its survivor, not go quiet.
  And a fixture pair like "ഡി സി ബുക്സ്"/"DC Books" proves nothing about any of
  this, because the fuzzy search bridges it unaided ("di si buks" ≈ "DC Books");
  a test that the *pointer* is honoured needs names no matcher could reach — an
  initialism ("എൻ ബി എസ്" → National Book Stall) or a pen name (Beypore Sultan →
  Vaikom Muhammad Basheer). Two of the new tests passed against the unfixed code
  until they were rewritten that way.
- **A question the code can answer must not be put to the reader as a label.**
  The duplicate fork asked "so what are you adding?" and offered "This is it —
  add my covers and details" beside "Mine's a different printing". Both read
  true of a book the catalogue already has, and the reader picked the first —
  but every field that fork carries is *edition*-level (cover, page count,
  ISBN, format, publisher), so on a different printing it lands on somebody
  else's row: the edit form resolved its edition as `editions.first`, the
  representative that 13 Aug already established is never an answer. The
  scanned ISBN settled it the whole time and nothing read it. `isbnStandingIn`
  (`work_editions.dart`) now judges the form's number against every printing
  the entry holds, and on a number the entry doesn't carry the improve door is
  *removed*, not merely demoted — an option that cannot be right should not be
  on the sheet. Deliberately conservative: "new printing" needs a positive
  signal (some catalogued printing carrying a *different* number), because a
  stub whose editions have no ISBNs may well be this very printing, and
  improving that stub in place is the case the fork was built for. Two
  corollaries. The similar panel's rows are `WorkSummaryOut` — one
  representative edition — so the sheet has to resolve the full Work before it
  can ask an honest question; a sheet built from a summary is a sheet built
  from a guess. And a *pick* must name what it picked: `_forkImproveEntry` now
  carries an `editionId` through the route, and the form falls back to the
  first edition only when the entry has one.
- **"Fills only empty fields" is a good rule and a bad silence.** The same
  report's second half (5 Sep 2026): the reader's covers said one title, the
  catalogue said another *with a typo in it*, and the seed's empty-only rule
  dropped the captured title and author with no trace — clearing both fields
  and re-running the cover extraction was the only way to see what their own
  book said. The rule is right (the shared catalogue's existing answer beats
  one copy's) and it was enforced by *discarding the evidence*, which is what
  made it unarguable. `_applySeed` now collects every value the entry already
  answers differently into a "From your copy" panel — what your copy says, what
  the entry says, and a tap to take it. Nothing is applied without that tap, so
  the catalogue still wins by default; the reader can just see the choice they
  were previously making blind. Genres are the one row that *adds* rather than
  replaces, because a genre set is not an answer.

- **A suppression rule has to be checked against the thing it suppresses.**
  The finished-reading nudge went silent once "a rating or review" existed —
  written when the sheet's whole job was the stars, and never revisited when
  "Write a review" became its primary button. A reader who rates a book halfway
  through (the common case for anyone who rates at all) then finished it in
  silence from every door at once, and the report read as "the timer doesn't
  ask" (owner, 6 Sep 2026) — the 3 Sep fix that wired every door was correct
  and invisible. Two things to do when a prompt "doesn't show": prove the door
  with a test through the real screen *before* touching it (the timer test
  passed unchanged, which is what pointed at the rule), and read the silence
  rule as a claim — "has the reader already said their piece?" — and ask
  whether the evidence it checks actually says that. A rating is not a review.

- **`debug*` getters on render objects are debug-mode contracts — in a release
  build some of them *throw* rather than answer.** `RenderObject.debugNeedsPaint`
  is `late bool result; assert(() { result = _needsPaint; return true; }());
  return result;` — the assert body never runs in release, so the getter dies
  with `LateInitializationError` on every call. `captureAndShareCard` used it as
  a readiness check, inside a `try` whose fallback shared the caption as text,
  so every share card on every reader's phone left as words while every debug
  run and the whole widget suite rasterised fine (owner report, 6 Sep 2026 —
  the *second* "only the text is getting shared", after the 26 Aug fix had
  correctly stopped passing text alongside the image). Two rules: nothing on a
  production code path reads a `debug*` member (`share_card_capture_test.dart`
  greps the capture file for exactly that, because a debug-mode test cannot
  fail the way the phone does), and a fallback must be *visible* — report the
  error through `FlutterError` and tell the reader what happened, or the
  fallback becomes the feature and nobody knows.

## Open decisions

- ~~Metadata source~~ — **resolved 5 Jul 2026: OpenLibrary.** Zero API key/credential
  (rule 8), free, decent global + regional ISBN coverage. Google Books would need a
  managed key; paid adds a bill. `Edition`/`Work`/`Author`/`Publisher` all carry
  `external_source`/`external_id` so a second source can be added later without
  re-architecting.
- ~~ISBN barcode scanning package~~ — **resolved 5 Jul 2026: `mobile_scanner`** (same
  choice rupee-diary made for QR) — see the Simulator gotcha above before testing it.
- ~~No user-photo cover upload endpoint~~ — **resolved: there is one, and has been
  since Phase 2.** Catalog images live in the **public Supabase Storage `covers`
  bucket**: `app/lib/features/catalog/catalog_image_upload.dart` uploads book covers,
  author portraits (`authors/…`) and publisher logos (`publishers/…`), and
  `extraction_service` only accepts cover URLs from that bucket. The admin console
  writes to the same bucket (`admin/console/assets.py`, `campaigns/…` for promo
  artwork) with a service-role key. **Use this bucket for any new image feature** —
  a second store means a second credential and a second thing to reason about
  (this stale line is what sent the promotions work briefly down an R2 path,
  31 Jul 2026). R2 stays what it is: the encrypted-backup target.

(Resolved: design tokens & mockups — `docs/kitabi_screens.html` + `docs/screen-design.md`,
2 Jul 2026. `app/lib/core/theme/app_theme.dart` still carries the old landing-page
dark seed and must be updated to the Reading Room tokens when the first real screen
is built.)
