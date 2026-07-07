# Kitabi — Beyond the Bookshelf

A personal library app with a community future: track what you **own** and what you
**read** — statuses, notes, personal shelves, ratings, reviews — with first-class
**lending records**, CSV import (Goodreads / Google Sheets), stats dashboards, and
transparent LLM-reasoned recommendations. Mobile-first, built solo, designed so the
personal app can become a community platform later without a rewrite.

The product thinking lives in [feature-map.md](feature-map.md): a four-layer feature
map (Shared Catalog → Personal Layer → Intelligence → dormant Community), the
"wire it now or pay later" data decisions, the v1 thin slice, and 2026 competitive
positioning.

## Repository layout

This repo is the single root for all three parts of the project:

| Directory | What it is | Status |
|---|---|---|
| [`landing-page/`](landing-page/) | Static "launching soon" page at [kitabi.in](https://kitabi.in) | **Live** |
| [`api/`](api/) | FastAPI backend — catalog, personal library, auth, sync, recommendations, push | **Live** at [api.kitabi.in](https://api.kitabi.in) |
| [`app/`](app/) | Flutter mobile app (the primary platform) | Release builds; **Play internal testing** + TestFlight |

**Stack:** offline-first Flutter + FastAPI + Supabase Postgres, same architecture as
the sibling project `rupee-diary` — see [CLAUDE.md](CLAUDE.md) for the full picture.

## Documentation

| Doc | What it covers |
|---|---|
| [STATUS.md](STATUS.md) | **Source of truth** — architecture, tech stack, integrations, live URLs, deploy state, feature status |
| [docs/build.md](docs/build.md) | **Build & run** — prerequisites and exact commands to build/test/ship API, app (IPA + AAB), landing page |
| [docs/architecture.md](docs/architecture.md) | **Deep technical reference** — data tiers, sync engine, cross-user layer, push, auth/RLS, and a file-by-file map |
| [CLAUDE.md](CLAUDE.md) | Dev conventions + non-negotiable rules |
| [feature-map.md](feature-map.md) | Full product spec (four-layer feature map) |
| [docs/tasks.md](docs/tasks.md) | Phase-by-phase build checklist |
| [docs/screen-design.md](docs/screen-design.md) | Design tokens; [docs/kitabi_screens.html](docs/kitabi_screens.html) is the mockup source of truth |

## Deployment

- **Landing page** — auto-deployed to Cloudflare Pages on pushes to `main` that touch
  `landing-page/`, via [.github/workflows/deploy.yml](.github/workflows/deploy.yml).
  Requires `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` repository secrets.
- **API** — Railway auto-deploys on push to `main` (Root Directory `api`); the
  container runs `alembic upgrade head` then uvicorn. See [docs/build.md](docs/build.md).
- **App** — release builds via `app/scripts/build_ipa.sh` (iOS) and
  `app/scripts/build_aab.sh` (Android); see [docs/build.md](docs/build.md) for signing,
  build-number, and store-upload steps.
