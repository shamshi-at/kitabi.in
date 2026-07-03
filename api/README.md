# Kitabi API

FastAPI backend for Kitabi (see root [CLAUDE.md](../CLAUDE.md)): Python 3.12+
fully async, SQLAlchemy 2.0 + asyncpg, Pydantic v2, Alembic, Supabase Postgres
(RLS deny-by-default, Supavisor pooler), APScheduler jobs, Docker, hosted on
Railway. Mirrors the architecture of the sibling project `rupee-diary/backend`.

Quick start:

```bash
python3.12 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt
docker compose up -d db                  # local Postgres on port 55442
.venv/bin/alembic upgrade head
.venv/bin/uvicorn app.main:app --reload  # http://localhost:8000/healthz
.venv/bin/pytest                         # tests (throwaway Postgres container)
```

Scope (see [feature-map.md](../feature-map.md) for the full v1 slice):

- Auth: Supabase JWT verification (Google + Apple sign-in)
- Shared catalog: books, authors, publishers, genres, series (Work vs. Edition model)
- Personal layer sync: library entries, statuses, notes, personal tags, ratings,
  reviews, lending records — offline-first push/pull, visibility flags wired
- CSV import (Goodreads / Google Sheets export)
- Search, filters, stats, LLM-reasoned recommendations
