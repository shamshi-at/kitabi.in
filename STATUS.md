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

**Last updated:** 5 Jul 2026

---

## Snapshot

Solo-built personal library app, pre-launch. **Phases 1–2 (auth & profile, shared
catalog) are complete** — real Google + Apple sign-in, a real Supabase project, a real
Railway deployment at a real custom domain, and now a full shared-catalog backend
(works/editions/authors/publishers/genres/series) backed by OpenLibrary with
cache-on-first-use, plus app screens for catalog search, ISBN scan, add/edit, and
author/publisher browse. Phases 3–8 (personal library, lending, sync engine, insights,
recommendations, launch plumbing) are not started. The landing page is live and public;
the mobile app is not yet store-submitted (no personal-library feature exists yet — a
user can browse/add to the shared catalog but can't yet mark a book as owned).

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
│     Sync Engine         │  ← queue, retries, conflict rules (not yet built)
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
  (queue + push/pull, not yet implemented — Phase 3).

The `Profile` row (this session's Phase 1 work) is neither — it's the user's own
identity row, keyed directly by the Supabase auth user id, updated via direct online
`GET/PATCH/DELETE /me` calls, no sync queue involved.

---

## Tech stack

| Part | Stack | Version notes |
|---|---|---|
| `app/` | Flutter — Riverpod (`flutter_riverpod` ^2.6.1, codegen not yet used), go_router ^14.6.2, Drift ^2.22.1 (schema not yet defined — Layer 1 catalog is fetched via API, not stored in Drift yet), Dio ^5.7.0, supabase_flutter ^2.8.0, sign_in_with_apple ^6.1.0, flutter_secure_storage ^9.2.2, google_fonts ^6.2.1, flutter_svg ^2.0.0, workmanager ^0.9.0, mobile_scanner ^6.0.2 (ISBN scan) | iOS deployment target **15.5** (bumped from 14.0 — `mobile_scanner`'s MLKit requirement); SDK `^3.12.2` |
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
| `app/` | Flutter mobile app | Auth flow + catalog screens working (search, ISBN scan, add/edit form, author/publisher browse); no personal-library UI yet |
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
| Landing page | https://kitabi.in | Cloudflare Pages, git-deploy from `landing-page/` on push to `main` | Live, public |
| API | https://api.kitabi.in | Railway service `kitabi-api`, proxied CNAME via Cloudflare (Full strict) | Live; auth/profile + catalog endpoints |
| API (origin, fallback) | https://kitabi-api-production.up.railway.app | Direct Railway domain | Keep working in case the custom domain ever breaks |
| Mobile app | — | Not store-submitted | Auth verified on iOS Simulator (Phase 1); catalog screens verified on an Android emulator against a local API (Phase 2) — `mobile_scanner`'s MLKit dependency can't build on an Apple Silicon iOS simulator (no arm64 simulator slice), so the scan screen specifically needs a real iOS device or an older x86_64-capable simulator runtime to verify there |

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
- **`app-ci.yml`** (paths: `app/**`) — `flutter pub get`, `build_runner` (codegen — currently
  a no-op since no `@riverpod`/Drift schema exists yet, ready for Phase 3), `flutter analyze`, `flutter test`.
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
| 2 — Shared catalog | Books/authors/publishers/series, ISBN scan, Work vs Edition | **✅ Done** — OpenLibrary-backed, cache-on-first-use, migration `000003`, `GET /catalog/search`, `GET /catalog/isbn/{isbn}`, `POST/PATCH /catalog/works`, `PATCH /catalog/editions/{id}`, author/publisher browse; app has search, ISBN scan, add/edit form, author/publisher browse screens |
| 3 — Personal library + sync engine | Drift schema, sync queue, push/pull, status/notes/tags/ratings/reviews | Not started — next up |
| 4 — Lending | Lend/borrow records, linked vs self-logged, due reminders | Not started (fully designed in mockups S8/S8b/S8c/S9) |
| 5 — Import | Goodreads/CSV import | Not started |
| 6 — Insights & search | Dashboard, stats, filters, author/publisher browse | Not started (designed in mockups S3/S4/S4b/S4c/S4d/S10) |
| 7 — Recommendations & share | LLM recs, per-book + personal share cards | Not started (designed in mockups S6c/S11/S13) |
| 8 — Launch plumbing | Version gate, backups, app icons, store listings, privacy policy | Not started (Railway deploy + custom domain items already done ✅) |

All 19 v1 screen mockups exist in [docs/kitabi_screens.html](docs/kitabi_screens.html),
audited against feature-map.md so every `[V1]` feature has a designed home before it's built.

---

## Recent milestones

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
- **No user-photo cover upload endpoint** — `Edition.cover_url` can hold any image URL
  (OpenLibrary's own covers already populate it), but there's no Supabase storage
  bucket or upload flow for a user's own photo yet; would be new infrastructure, out
  of Phase 2's scope.
