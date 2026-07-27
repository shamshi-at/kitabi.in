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
| `app/` | Flutter — Riverpod (codegen `@riverpod`), go_router, Drift (local DB, source of truth), Dio (+ interceptors: JWT attach, update-gate, retry/backoff), supabase_flutter (auth), flutter_secure_storage, connectivity_plus, workmanager (background sync drain), Firebase for FCM only |
| `api/` | FastAPI — Python 3.12+, fully async (SQLAlchemy 2.0 async, asyncpg), Pydantic v2, Alembic migrations, APScheduler jobs, Docker (must always build), ruff + black line length 100 |
| Database | Supabase Postgres — RLS deny-by-default, Data API disabled; only FastAPI (via Supavisor transaction pooler, port 6543, prepared-statement cache off) touches user data |
| Auth | Supabase Auth (Google + Apple per feature map). API verifies JWT with **PyJWT against project JWKS** (ES256, cache JWKS, handle `kid` rotation, check `iss`/`aud`/`exp`). Never python-jose |
| `landing-page/` | Dependency-free static HTML/CSS on Cloudflare (Pages today via GitHub Actions; Workers static assets like rupee-diary is fine later) |
| Hosting | Railway (API) + Supabase free tier. Core constraint: **cheap to run, cheap to maintain** — no Redis, no queues, no extra SaaS. If something seems to need Redis, do it in Postgres or in-process and leave a `# SCALE:` comment |

## Repository layout

This folder is the single root for all three parts:

| Directory | rupee-diary equivalent | What it is | Status |
|---|---|---|---|
| `landing-page/` | `landing/` | Static "launching soon" page at kitabi.in | Live |
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
.venv/bin/alembic upgrade head           # apply migrations
docker build -t kitabi-api .             # must always build

# Flutter (SDK at ~/development/flutter — not on default PATH)
cd app
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # Drift/Riverpod codegen
flutter test
flutter analyze
cp dart_defines.env.example dart_defines.env   # once, then fill in real values (gitignored)
./scripts/run_dev.sh -d <device>               # NOT `flutter run` directly — see below
./scripts/build_ipa.sh                          # NOT `flutter build ipa` directly
```

After changing any Drift table or Riverpod codegen-annotated file, **always run
build_runner** before assuming compilation errors are real.

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
- **api / app:** no pipelines yet; add per-directory workflows with `paths:` filters
  matching the pattern above (rupee-diary's `ci.yml` and `backup.yml` are the
  reference).

## Lessons imported from rupee-diary ("things that have bitten us")

- Repeated regex edits on large generated files cause cascading corruption — rebuild
  cleanly instead of patching patches.
- Drift schema changes without `build_runner` produce confusing analyzer errors.
- Supabase free tier pauses after 7 days idle — keep the project warm (scheduled
  ping job in the API's `jobs/`).

## Lessons learned in Kitabi

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

## Open decisions

- ~~Metadata source~~ — **resolved 5 Jul 2026: OpenLibrary.** Zero API key/credential
  (rule 8), free, decent global + regional ISBN coverage. Google Books would need a
  managed key; paid adds a bill. `Edition`/`Work`/`Author`/`Publisher` all carry
  `external_source`/`external_id` so a second source can be added later without
  re-architecting.
- ~~ISBN barcode scanning package~~ — **resolved 5 Jul 2026: `mobile_scanner`** (same
  choice rupee-diary made for QR) — see the Simulator gotcha above before testing it.
- **No user-photo cover upload endpoint yet.** `Edition.cover_url` holds any image URL
  (OpenLibrary's own covers already populate it on ISBN lookup), but there's no
  Supabase storage bucket or upload flow for a user's own photo — new infrastructure,
  deliberately deferred past Phase 2.

(Resolved: design tokens & mockups — `docs/kitabi_screens.html` + `docs/screen-design.md`,
2 Jul 2026. `app/lib/core/theme/app_theme.dart` still carries the old landing-page
dark seed and must be updated to the Reading Room tokens when the first real screen
is built.)
