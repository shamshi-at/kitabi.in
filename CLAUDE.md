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
flutter run -d <device>
```

After changing any Drift table or Riverpod codegen-annotated file, **always run
build_runner** before assuming compilation errors are real.

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
