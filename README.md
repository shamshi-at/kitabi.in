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
| [`landing-page/`](landing-page/) | Static "launching soon" page at [kitabi.in](https://kitabi.in) | Live |
| [`api/`](api/) | FastAPI backend — catalog, personal library, auth, sync, recommendations | Scaffolded |
| [`app/`](app/) | Flutter mobile app (the primary platform) | Scaffolded |

**Stack:** offline-first Flutter + FastAPI + Supabase Postgres, same architecture as
the sibling project `rupee-diary` — see [CLAUDE.md](CLAUDE.md) for the full picture.

## Deployment

- **Landing page** — auto-deployed to Cloudflare Pages on pushes to `main` that touch
  `landing-page/`, via [.github/workflows/deploy.yml](.github/workflows/deploy.yml).
  Requires `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` repository secrets.
- **API / app** — not yet set up.
