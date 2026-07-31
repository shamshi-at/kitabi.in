# Environments — prod + dev on one Railway project and one Supabase project

> **Status:** plan, not yet implemented (30 Jul 2026). Build and release mechanics for
> the current single-environment setup are in [build.md](build.md); this document
> describes the two-environment target and how to get there. Update
> [../STATUS.md](../STATUS.md) when it lands.
>
> RupeeDiary has the identical plan at `rupee-diary/docs/environments.md`. Do both the
> same way — same schema name, same role convention, same branch names — so the muscle
> memory transfers. Everything below is Kitabi-specific where it differs; §8 (the
> catalog) has no RupeeDiary equivalent and is the part most likely to bite.

---

## 0. The constraint that decides the design

Two platform facts set the shape of everything below. Both were checked, not assumed:

**Supabase's free plan caps you at 2 active free projects, and the quota follows the
person, not the org.** The billing FAQ words it as 2 per organization but then counts the
limit "from all members that are either Owner or Admin", so a solo owner gets 2 in total
however many orgs they create. Kitabi and RupeeDiary already use both. The next project
means a Pro org at $25/mo. Paused projects don't count against the limit, but a dev
database that pauses on you is not a dev database. Supabase's own preview *branching* is
Pro-only (≈$0.0134/branch/hour, ~$9.70/mo if left running).

> Worth a two-minute check in the dashboard: try to create a third free project. If it
> lets you, the isolation option in §2 gets cheaper — but the design below doesn't
> change, and you can promote `dev` to its own project later without touching anything
> except two environment variables.

→ **Dev must live inside the existing Supabase project.**

**Railway bills usage, not environments.** Hobby is a $5/mo minimum that includes $5 of
usage; beyond that it's roughly $10/GB-month of RAM and $20/vCPU-month, billed per second
of actual runtime. A second environment costs nothing by itself — you pay for the
container while it runs. Railway's **Serverless** (formerly app-sleeping) sleeps a service
after ~10 minutes with no outbound traffic and wakes it on the next request.

→ **Dev can be a second Railway environment that sleeps, and cost near nothing** — but
only if nothing inside it produces a heartbeat. An idle-but-open DB pool, the APScheduler
`keep_warm` job, or an uptime pinger will hold it awake and billing 24/7. This is the
single most important cost detail on the Railway side.

The resulting design:

> **One Supabase project, two Postgres schemas. One Railway project, two environments.
> Dev sleeps when you're not using it. Dev gets a *slice* of the catalog, not a copy.**

---

## 1. Target shape

```
                    ┌─────────────────────────────────────────┐
   main branch ───► │ Railway env: production                 │
                    │  api    (always on)                     │──┐
                    │  admin  (always on)                     │  │
                    │  ENV=prod  DB_SCHEMA=public             │  │
                    └─────────────────────────────────────────┘  │ Supavisor 6543
                       api.kitabi.in / admin.kitabi.in           │ (one project)
                                                                 │
                    ┌─────────────────────────────────────────┐  │  ┌──────────────────┐
   dev branch  ───► │ Railway env: dev                        │  │  │ Supabase project │
                    │  api only (Serverless: on)              │──┼─►│ schema public ← prod
                    │  ENV=dev   DB_SCHEMA=dev                │  │  │ schema dev    ← dev
                    └─────────────────────────────────────────┘  │  │ auth.*  (shared)
                            dev-api.kitabi.in                    │  │ storage (2 buckets)
                                                                 │  └──────────────────┘
   Flutter: --dart-define-from-file=env/prod.json | env/dev.json
```

| | **production** | **dev** |
|---|---|---|
| Railway environment | `production` | `dev` |
| Services | `api`, `admin` | **`api` only** (§6) |
| Deploys from branch | `main` | `dev` |
| Railway Serverless | off | **on** |
| API host | `api.kitabi.in` | `dev-api.kitabi.in` |
| `ENV` | `prod` | `dev` |
| Postgres schema | `public` | `dev` |
| Postgres role | `postgres` | `kitabi_dev` (no rights on `public`) |
| Connection pool | warm (10+10, recycle 280) | `NullPool` — so the service can sleep |
| `SCHEDULER_ENABLED` | `true` | `false` (this also disables `keep_warm`) |
| Covers bucket | `covers` | `covers-dev` |
| Layer-1 catalog | full ETL seed | **bounded slice, ~2k works** (§8) |
| `MIN_APP_VERSION` | real store version | `0.0.1` — never gate yourself out mid-test |
| `ANTHROPIC_API_KEY` | set | set (recs/extraction are pennies) or unset to test the dormant path |
| Nightly R2 backup | yes | no — dev is disposable by definition |
| `CORS_ORIGINS` | `https://kitabi.in`, `https://www.kitabi.in` | add `http://localhost:*` as needed |

**Deliberately shared, because one project means one of each.** Know these and work
around them rather than being surprised:

| Shared thing | Consequence | How we live with it |
|---|---|---|
| `auth.users` (one GoTrue per project) | Dev Google/Apple sign-ins create real rows in the same auth table as prod readers | Use **one dedicated Google account for dev testing**, written down. Never bulk-delete auth users without filtering it out. |
| 500 MB database quota — **org-wide, not per project** | On the Free plan the quota covers the whole `shamshi` organisation, so Kitabi prod, RupeeDiary prod and both dev schemas all draw on the same 500 MB (39 MB used as of 30 Jul 2026). Kitabi's catalog is the biggest single consumer in that budget | §8 — dev's catalog is a slice, never a copy. Reset the dev schema whenever it gets fat, and check Supabase → Usage after every seed. |
| 1 GB file storage, 5 GB/mo egress, 50k MAU | Also org-wide across both apps | Cover images are the consumer; `covers-dev` stays small. |
| Supabase URL, JWKS, anon key | Both environments verify tokens against the same issuer | Fine — a dev JWT and a prod JWT are indistinguishable to the API, which is why **schema isolation, not token isolation, is the security boundary**. |
| `pg_trgm` and other extensions (in the `extensions` schema) | Shared | Grant the dev role `usage` on it (§3); the `SET LOCAL pg_trgm.word_similarity_threshold` in `catalog_service.py` is per-transaction and unaffected. |
| The `keep_warm` job (prod only) | Prod's daily ping keeps the *project* awake | Bonus of sharing: dev never needs its own keep-warm, and the dev schema can't be paused out from under you. |

Not shared, and not an issue: Kitabi has **no Realtime usage yet**. When it lands, namespace
the topic per environment from day one (`{env}:...`) the way RupeeDiary does — cheap then,
annoying to retrofit.

---

## 2. Why schema-per-environment (and not the alternatives)

| Option | Verdict |
|---|---|
| Second Supabase project | **Not available free** (§0). $25/mo. Best isolation if you ever go Pro. |
| Supabase branching | Pro-only, ~$9.70/mo per always-on branch. |
| Second *database* in the same Postgres | Supavisor's tenant points at the `postgres` database; `auth`, `storage` and Realtime all live there. Not supported, don't try. |
| **Second schema in the same database** | **Chosen.** Free, isolates every app table, and can be made hard-walled with a dedicated role (§3). |
| Dev = local Postgres only (today's setup, port 55442) | Keep it for the inner loop, but it never exercises Supavisor pooling, Supabase Auth JWTs, or Storage — which is exactly where RupeeDiary's production bugs came from (`DuplicatePreparedStatementError`, Jun 2026 — the reason `db.py` carries the pooler-safety `connect_args`). Local stays; the dev *environment* is additional, not a replacement. |

---

## 3. The safety story — a role that physically cannot see prod

Sharing a database with production is only acceptable if a misconfigured dev deploy is
*unable* to touch prod data, rather than merely unlikely to. App-level config is not
enough — a typo'd env var must fail loudly, not silently write into `public`.

So the boundary is a Postgres role, granted on the dev schema only:

```sql
-- Run once in Supabase → SQL Editor. Choose a strong password and store it in the
-- password manager; it goes into the Railway dev environment only.

create schema if not exists dev;

create role kitabi_dev with login password '<STRONG-PASSWORD>';

-- Dev owns its schema outright: it must be able to run migrations (CREATE TABLE etc).
grant usage, create on schema dev to kitabi_dev;
alter schema dev owner to kitabi_dev;

-- ...and has nothing at all on production's schema.
revoke all on schema public from kitabi_dev;
revoke all on all tables in schema public from kitabi_dev;
revoke all on all sequences in schema public from kitabi_dev;
revoke all on all functions in schema public from kitabi_dev;
alter default privileges in schema public revoke all on tables from kitabi_dev;

-- The belt-and-braces bit: even if the app forgets to set search_path, this role
-- resolves unqualified names to `dev`. Applied at connection start, so it survives
-- Supavisor transaction pooling (a per-session `SET` would not).
alter role kitabi_dev set search_path = dev, extensions;

-- pg_trgm / uuid-ossp live in `extensions`, not public — catalog search needs them.
grant usage on schema extensions to kitabi_dev;
```

Connect through Supavisor as that role by putting the role name before the project ref in
the username — the pooler's username format is `<role>.<project-ref>`:

```
postgresql+asyncpg://kitabi_dev.lwyifccwirfmgdvemgkz:<PASSWORD>@aws-1-ap-south-1.pooler.supabase.com:6543/postgres
```

**Verify the wall before trusting it.** Connect as `kitabi_dev` and run:

```sql
select current_user, current_schemas(true);   -- expect kitabi_dev, {dev, extensions, ...}
select count(*) from public.works;            -- expect: permission denied
create table probe(id int); drop table probe; -- expect: created in dev, then gone
```

If the second query returns a number, stop and fix the grants before deploying anything.

RLS is still non-negotiable (CLAUDE.md rule 11) — after the first dev migration, enable it
across the schema:

```sql
do $$ declare t record; begin
  for t in select tablename from pg_tables where schemaname = 'dev' loop
    execute format('alter table dev.%I enable row level security', t.tablename);
  end loop;
end $$;
```

And confirm in Supabase → Settings → API that `dev` is **not** in the exposed-schemas
list (it isn't by default, and the Data API stays disabled for app schemas regardless).

---

## 4. Code and config changes

Small, and every one of them is worth having on its own. Diffs are sketches — write them
in the house style.

### 4.1 `api/app/core/config.py` — a schema knob and a fail-fast assertion

```python
    env: str = "dev"                    # "prod" | "dev" | "local"
    db_schema: str = "public"           # "public" in prod, "dev" in the dev env
    covers_bucket: str = "covers"       # "covers-dev" in the dev env

    @property
    def is_prod(self) -> bool:
        return self.env == "prod"
```

`covers_bucket` also replaces the hardcoded bucket path in
`services/extraction_service.py` (`.../object/public/covers/`), which currently pins the
"only images we host may be sent to the vision model" check to one bucket name.

Then, at startup in `api/app/main.py` (before the app serves anything), refuse the
combination that would be a disaster:

```python
settings = get_settings()
if settings.is_prod and settings.db_schema != "public":
    raise RuntimeError("prod must use the public schema")
if not settings.is_prod and settings.db_schema == "public":
    raise RuntimeError(f"ENV={settings.env} refuses to run against the public schema")
```

Two lines that turn the worst possible misconfiguration into a failed deploy.

### 4.2 `api/app/core/db.py` — let the dev service actually sleep

The current pool is tuned for a warm cross-region prod service: `pool_size=10`,
`pool_pre_ping`, `pool_recycle=280`. Those open connections and periodic checkouts are
exactly the outbound traffic that stops Railway Serverless from ever sleeping. In dev,
correctness beats latency:

```python
from sqlalchemy.pool import NullPool

def _engine_kwargs(url: str, *, warm: bool) -> dict:
    if not url.startswith("postgresql+asyncpg"):
        return {}
    connect_args = {
        "statement_cache_size": 0,
        "prepared_statement_cache_size": 0,
        "prepared_statement_name_func": lambda: f"__asyncpg_{uuid.uuid4()}__",
    }
    if not warm:
        # Dev on Railway Serverless: hold no idle connections, so the service
        # goes quiet after a request and Railway can sleep it. A cold first
        # request costs a connect; that is the point.
        return {"poolclass": NullPool, "connect_args": connect_args}
    return {
        "pool_size": 10, "max_overflow": 10, "pool_pre_ping": True,
        "pool_recycle": 280, "connect_args": connect_args,
    }

engine = create_async_engine(_url, **_engine_kwargs(_url, warm=settings.is_prod))
```

### 4.3 `api/alembic/env.py` — migrate into the configured schema

Note what we are *not* doing: no `schema=` on the models, no `include_schemas=True`.
Tables stay unqualified in `Base.metadata`, and the connection's `search_path` decides
where they land. That keeps the raw `nextval('sync_seq')` in `models/base.py`,
`services/sync_service.py`, `services/lend_mirror_service.py` and
`services/catalog_service.py` working untouched, and it keeps autogenerate from
reflecting `auth.*` / `storage.*` and proposing to drop them.

```python
def run_migrations_online() -> None:
    schema = get_settings().db_schema
    connectable = create_engine(_sync_url(), poolclass=pool.NullPool)
    with connectable.connect() as connection:
        connection.execute(text(f'create schema if not exists "{schema}"'))
        connection.execute(text(f'set search_path to "{schema}", extensions'))
        connection.commit()
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            version_table_schema=schema,   # dev.alembic_version, never public's
        )
        with context.begin_transaction():
            context.run_migrations()
    connectable.dispose()
```

`version_table_schema` is the important one: each environment keeps its own migration
head, so a half-applied dev migration can never make prod look up-to-date.

The `sync_seq` sequence is created by a migration, so each schema gets its own — which is
correct: `server_seq` is a per-environment pull cursor and the two must not share a
counter.

### 4.4 Storage bucket

Create a **`covers-dev`** bucket in Supabase with the same public-read policy as `covers`,
and set `COVERS_BUCKET=covers-dev` in the dev environment.

### 4.5 Flutter — two define files, and a dev build you can't confuse with prod

`app/dart_defines.env` becomes two files. The Supabase anon key is a public key by
design, so these can be committed (unlike today's gitignored single file — decide
deliberately, but committing removes a whole class of "the build silently ran
unconfigured" failures that CLAUDE.md already calls out):

`app/env/prod.json`
```json
{
  "ENV": "prod",
  "API_BASE_URL": "https://api.kitabi.in",
  "SUPABASE_URL": "https://lwyifccwirfmgdvemgkz.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "..."
}
```

`app/env/dev.json` — same Supabase URL and anon key (same project!), different API:
```json
{
  "ENV": "dev",
  "API_BASE_URL": "https://dev-api.kitabi.in",
  "SUPABASE_URL": "https://lwyifccwirfmgdvemgkz.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "..."
}
```

```bash
flutter run   --dart-define-from-file=env/dev.json
flutter build appbundle --release --dart-define-from-file=env/prod.json
```

Three more things make the dev build unmistakable and safe to have installed alongside prod:

1. **`applicationIdSuffix ".dev"`** on Android (a `dev` build type in
   `android/app/build.gradle.kts`) → separate app, separate icon, separate sandbox.
   Register the `.dev` package as a second Android app in the same Firebase project and
   re-download the merged `google-services.json` so FCM keeps working.
2. **Suffix the Drift database file with the env** (`kitabi_dev.sqlite`). This is what
   actually prevents dev and prod data mixing on device — and it matters most on iOS,
   where we are *not* taking a second bundle ID (a second App ID, provisioning profile and
   Firebase iOS app is real ongoing cost for a solo dev). On iOS you install one or the
   other; the distinct Drift file means switching never corrupts local data.
3. **A banner rendered whenever `ENV != prod`**, showing the environment and API host.
   Cheap, and it ends the entire class of "which environment was I testing against?"

### 4.6 CI and backups

- `.github/workflows/api-ci.yml`, `app-ci.yml`, `admin-ci.yml`: `branches: [main]` →
  `branches: [main, dev]`. Same jobs; the point is that `dev` never receives an unbuilt
  commit. The throwaway test Postgres on 55443 is unaffected.
- `.github/workflows/backup.yml`: exclude the dev schema so backups stay small and a
  restore never resurrects dev junk:
  ```diff
  - pg_dump --no-owner --no-privileges "$BACKUP_DATABASE_URL" \
  + pg_dump --no-owner --no-privileges -N dev "$BACKUP_DATABASE_URL" \
  ```

---

## 5. One-time provisioning

Do these in order. Roughly an hour, plus §8's catalog seed.

**Supabase**
1. Run the SQL in §3 (schema, role, grants, `search_path`, `extensions` usage).
2. Run the three verification queries. Do not continue until `select … from public.works`
   is denied.
3. Create the `covers-dev` storage bucket, policies copied from `covers`.
4. Create the dev Google test account and note it in the runbook.

**Repo**
5. `git checkout -b dev main && git push -u origin dev`. Protect `main`: PRs only, CI
   required. `dev` stays unprotected — it's the integration branch.
6. Land the §4 code changes on `dev` first (they're all backwards-compatible; prod keeps
   `ENV=prod`, `DB_SCHEMA=public` and behaves exactly as today).

**Railway**
7. Project → Environments → **New environment** → *Duplicate* `production`, name it `dev`.
8. **Delete the `admin` service from the `dev` environment** (§6). One service to keep
   awake-free, one URL to remember.
9. On the `api` service in `dev`: Settings → Source → deploy branch **`dev`**.
10. Settings → **Serverless / App sleeping: ON**. (The `healthcheckPath: /healthz` in
    `api/railway.json` only runs at deploy time, so it does not keep the service awake.)
11. Override the variables that differ (full list in §1): `ENV=dev`, `DB_SCHEMA=dev`,
    `DATABASE_URL` with the `kitabi_dev.<ref>` pooler URL, `SCHEDULER_ENABLED=false`,
    `COVERS_BUCKET=covers-dev`, `MIN_APP_VERSION=0.0.1`, `CORS_ORIGINS`.
    `SUPABASE_URL` and `FIREBASE_CREDENTIALS` are the same as prod.
12. Generate a domain, then Cloudflare → DNS → `dev-api` CNAME to it. **DNS-only (grey
    cloud)** — the dev API has no reason to sit behind the WAF, and it keeps TLS
    troubleshooting to one layer.
13. Deploy. First deploy creates the `dev` schema and runs every migration into it.
14. Run the RLS loop from §3, and re-check that `dev` is not an exposed schema.

**Data**
15. Seed the dev catalog — §8. Nothing in the app works without it.

**App**
16. Add `env/prod.json` + `env/dev.json`, the Android `.dev` build type, the Firebase
    second Android app, the env-suffixed Drift filename and the dev banner.

---

## 6. What about the admin console?

`admin/` is a second Railway service in the same project, sharing the API's SQLAlchemy
models via `console/bootstrap.py`. It picks up `DB_SCHEMA` for free through the same
settings object, so a dev admin console would just work.

**Don't run it in the dev environment by default.** It doubles the dev footprint, it is
a second thing that can hold the environment awake, and the console is operational
tooling — the risky changes in it are about *what it shows*, which you can exercise
locally against the local Postgres on 55442.

When you do need it (a moderation flow, an audit-log change, anything touching
`admin_users` / `admin_sessions`): add the service to the `dev` environment temporarily,
Serverless on, and remember dev has its own `admin_users` table — you'll need to seed an
admin there with the existing bootstrap script. Remove the service afterwards.

---

## 7. Day-to-day workflow

```
feature/xyz ──PR──► dev ──(auto-deploy)──► dev-api.kitabi.in  ← test here
                     │
                     └──PR──► main ──(auto-deploy)──► api.kitabi.in
```

- **Inner loop stays local.** `docker compose up -d db` (55442) + `uvicorn --reload` +
  `flutter run --dart-define-from-file=env/dev.json` pointed at `localhost`. Fastest,
  free, unchanged from today.
- **Push to `dev` when you need the real thing:** Supabase Auth against a real Google
  sign-in, Supavisor pooling behaviour, cover uploads to Storage, FCM to a physical
  device, the Claude recs/extraction path against real latency, or a migration you want
  to see run on Supabase's Postgres 17 rather than your local container.
- **Feature branches PR into `dev`.** CI must be green. `dev` may be force-reset from
  `main` any time it gets tangled — nothing on it is precious.
- **Migrations are written locally, applied to dev by the deploy, and only then merged to
  `main`.** By the time a migration reaches prod it has run twice already.
- Expect a **cold start** on the first request to the dev API after idle (Serverless).
  Ten seconds of 502 or slowness is the price of the near-zero bill; hit `/healthz` once
  to wake it before starting a test session.

---

## 8. The catalog — Kitabi's one genuinely hard bit

The Layer-1 catalog (`works` / `editions` / `authors` / `publishers`) is
server-authoritative, shared by all users, and by far the largest thing in the database.
[etl/README.md](../etl/README.md) is explicit that the full OpenLibrary dumps would be
50–100+ GB in Postgres against a 500 MB free tier, which is why prod carries a curated
seed in the first place. Tighter than it sounds: on the Free plan that 500 MB is an
**organisation-wide** quota, so the catalog is sharing it with RupeeDiary's production
database as well as both dev schemas.

**A second full copy in the `dev` schema is not affordable.** Dev gets a bounded slice.

Two ways to produce it; pick per situation:

**A. Copy a slice from prod (fast, realistic data).** Run as `postgres` in the Supabase
SQL editor — *not* as `kitabi_dev`, so the wall in §3 stays intact. This is a deliberate
operator action, not a standing grant. Insert in FK order (check the current
`api/app/models/` before running — this is the shape, not a verbatim script):

```sql
-- ~2k works and everything they reference. Adjust the ORDER BY to whatever
-- popularity/score column the ETL populates.
create temp table _w as
  select id from public.works where deleted_at is null
  order by popularity desc nulls last limit 2000;

insert into dev.authors     select * from public.authors     where id in (
  select author_id from public.work_authors where work_id in (select id from _w));
insert into dev.publishers  select * from public.publishers  where id in (
  select publisher_id from public.editions where work_id in (select id from _w));
insert into dev.works       select * from public.works       where id in (select id from _w);
insert into dev.work_authors select * from public.work_authors where work_id in (select id from _w);
insert into dev.editions    select * from public.editions    where work_id in (select id from _w);

analyze dev.works; analyze dev.editions; analyze dev.authors;
```

Include a deliberate spread: some Malayalam/Indic works, some English head titles, at
least one translation group, at least one work with multiple editions — those are the
shapes the Work-vs-Edition rules (CLAUDE.md 17) actually get wrong.

**B. Run the ETL quick-test path into dev (tests the pipeline itself).** The README's
`--top 0 --max-works 100` recipe with `DATABASE_URL` pointed at the `kitabi_dev` role.
Use this when the *change under test is the ETL* — it's the only way to exercise
`04_load.sql`'s staging/insert logic for real.

**Rejected:** granting the dev role `SELECT` on the prod catalog tables (or exposing them
as views in `dev`) to avoid duplication. It saves maybe 50 MB, punches a permanent hole in
the isolation wall, and confuses Alembic autogenerate — which would see a view where it
expects a table. Not worth it.

**Budget it.** Check Supabase → Usage after seeding. If prod + dev is above ~350 MB, cut
the dev slice down rather than trimming prod.

---

## 9. Publishing to production

The release procedure, in order. Nothing here is optional — it's the same list every time.

**Gate — before you open the PR to `main`:**

- [ ] The change has been exercised on `dev-api.kitabi.in` from a real device build, not
      just locally.
- [ ] Definition of Done per CLAUDE.md: `pytest`, `flutter test`, `ruff`/`black`,
      `docker build`, migration included, offline behaviour checked in airplane mode.
- [ ] The migration ran cleanly on the dev schema **and** is backwards-compatible with
      the currently deployed prod code (§10) — prod runs migrations before the new image
      takes over, so old code briefly runs against the new schema.
- [ ] Catalog-affecting changes checked against a *Work with multiple Editions* and a
      translation group, not just a single-edition English book.
- [ ] [tasks.md](tasks.md) ticked; [../STATUS.md](../STATUS.md) updated in the same commit
      if architecture, integrations, URLs or deploy targets moved.
- [ ] If the API contract changed for existing clients: `MIN_APP_VERSION` decided — bump
      it only when old clients genuinely cannot work, since it hard-locks users out
      behind the 426 update gate.

**Release:**

1. Open `dev` → `main` PR. CI green.
2. Merge. Railway's `production` environment auto-deploys `api` (and `admin`) on push to
   `main`.
3. Migrations run at container start (`alembic upgrade head` in the Dockerfile CMD).
   Watch the deploy log for it explicitly — a failed migration should abort the deploy,
   not leave a running container on a half-migrated database.
4. Smoke test within a couple of minutes: `curl https://api.kitabi.in/healthz` → app sign-in
   → catalog search (the `pg_trgm` path) → add a book to the library offline → go online
   and confirm it syncs → a lending record round-trip.
5. Check `admin.kitabi.in` loads and the audit log is writing.
6. Watch Railway logs and Supabase → Usage for ~15 minutes.
7. **The nightly backup runs on its cron.** If the release materially changes data shape,
   trigger `backup.yml` manually (`workflow_dispatch`) *before* the release.
8. Tag the release. Mobile store releases follow their own path in
   [build.md](build.md) — the API can ship ahead of the store build, never behind it.
9. Merge `main` back into `dev` (or reset `dev` to `main`) so the branches don't drift.

**Rollback:** Railway → Deployments → Redeploy the previous build. This rolls back *code
only* — the database keeps the new schema, which is exactly why §10's rule exists. If a
migration itself is the problem, roll forward with a corrective migration; never
hand-edit an applied one.

### The app half — one store listing, four rungs

**We do not publish a dev app to either store.** One App Store record and one Play
listing per product, for the production bundle ID / applicationId. Non-production builds
are distributed off-store.

The reframe that matters: **TestFlight is not the dev environment — it is the
release-candidate channel.** A build you put on TestFlight should be the exact binary you
intend to ship. If you TestFlight a dev-API build and then rebuild for production, you
shipped something nobody ever tested.

| Rung | Build | Points at | Distribution | Store record |
|---|---|---|---|---|
| Inner loop | debug | `localhost` | `flutter run` | — |
| Dev verify | `env/dev.json`, `.dev` applicationId | `dev-api.kitabi.in` | sideload / **Firebase App Distribution** (free, and Firebase is already in the stack for FCM) | none |
| Release candidate | `env/prod.json`, real app id | `api.kitabi.in` | TestFlight **internal** (≤100 testers, no Beta App Review, instant) + Play **internal testing** track | the real one |
| Beta | *the same binary* | prod | TestFlight external (Beta App Review per version) / Play **closed testing** | the real one |
| Live | *the same binary, promoted* | prod | App Store / Play **production** | the real one |

**Promote the artifact, never rebuild it.** Play Console promotes a release between
tracks with the same AAB; App Store review is submitted from a TestFlight build. The
binary that 12 testers used is the binary that ships.

A second store record for a dev app is a real pattern, but it exists for organisations
with external QA who cannot sideload. It costs a second bundle ID with its own signing
and provisioning, a second Firebase iOS app, separate store metadata, and Beta App Review
on every external version — for a solo developer testing on their own devices it buys
nothing that Firebase App Distribution doesn't.

**Play gotcha, worth checking now rather than at launch:** personal developer accounts
created after 13 Nov 2023 must run a *closed* test with **12 testers opted in
continuously for 14 days** before they can apply for production access. Internal testing
does not count toward it. That is a two-week lead time on the launch plan — confirm
whether the Play account is personal or organisation before [tasks.md](tasks.md) assumes
otherwise.

---

## 10. Migration discipline (the rule that makes rollback survivable)

Every migration must be safe for the *previous* version of the code to run against — one
version of backwards compatibility, minimum. In practice, expand → migrate → contract:

| Want to | Do it as |
|---|---|
| Add a required column | Release 1: add nullable + backfill. Release 2: add the NOT NULL. |
| Rename a column | Release 1: add new, write both, read old. Release 2: read new. Release 3: drop old. |
| Drop a column/table | Ship the code that stops using it first; drop it a release later. |
| Change a type | New column + backfill + swap reads, then drop. Never `ALTER TYPE` in place on a live table. |
| Add an index to a big catalog table | `CREATE INDEX CONCURRENTLY` in its own migration with `autocommit_block()` — a plain `CREATE INDEX` on `editions` will lock writes. |

Because each environment has its own `alembic_version` row (in its own schema), `dev`
being several migrations ahead of `public` is normal and harmless.

---

## 11. Cost

| Line item | Now | With dev | Note |
|---|---|---|---|
| Supabase | $0 | **$0** | Same project. Shares the 500 MB / 1 GB storage / 5 GB egress quota — §8 is the thing that keeps this true. |
| Railway `api` (prod) | usage | unchanged | ~$10/GB-month RAM + ~$20/vCPU-month, billed per second. |
| Railway `admin` (prod) | usage | unchanged | Not duplicated in dev (§6). |
| Railway `api` (dev) | — | **≈ $0–1/mo** | Only bills while awake. With Serverless on, `SCHEDULER_ENABLED=false` and `NullPool`, a few hours of testing per week is cents. Get any one of those three wrong and it's a full always-on service (~$2.50–5/mo for 256–512 MB). |
| Cloudflare DNS + Pages | $0 | $0 | |
| GitHub Actions | $0 | $0 | |

When the dev schema gets fat, reset it — it is disposable:

```sql
drop schema dev cascade;
create schema dev; alter schema dev owner to kitabi_dev;
```
then redeploy the dev environment to re-run every migration, and re-seed the catalog
slice (§8). Do this routinely; a dev schema that nobody dares delete has stopped being a
dev schema.

### Should we just pay for Supabase Pro and get a real separate dev database?

Eventually yes — and for Kitabi that day probably comes sooner than for RupeeDiary. But
the reason won't be dev isolation.

Pro is **$25/mo per organisation**, including $10 of compute credit that covers one Micro
instance. Every project beyond the first pays its own compute (Micro $10/mo, Small $15).
So:

| Shape | Monthly |
|---|---|
| Today — both apps free, dev as a schema | **$0** |
| One Pro org, Kitabi prod + dev projects | $25 + $10 = **$35** |
| One Pro org holding all four projects (both apps, both envs) | $25 + $10×3 = **$55** |
| Persistent Supabase *branch* instead of a second project | ~$9.80/mo per branch, on top of Pro |

Against ~$5/mo of Railway today that is a 7–11× jump in running cost, and the thing it
buys (dev isolation) is what the `kitabi_dev` role in §3 already gives us for free.

**The real reason to go Pro is the catalog.** Pro raises the database from 500 MB to
**8 GB**, and [etl/README.md](../etl/README.md) is one long argument with the 500 MB
ceiling — the curation tiers, the popularity cutoff, the "quick test run" recipe all
exist because of it. 8 GB is the difference between a curated seed and a catalog that
can actually grow with the reader base. Pro also brings daily backups with 7-day
retention (retiring `backup.yml` and CLAUDE.md rule 12's hand-rolled pipeline), no
7-day idle pausing (retiring `keep_warm`), 100 GB storage for covers and 250 GB egress.

So: **upgrade when the catalog needs the room, and take dev isolation as the $10 side
effect.** Trigger: the database passes ~400 MB, or the next catalog expansion is being
shaped by the ceiling rather than by what readers need.

Two notes for when that day comes:

1. **Use a second project, not Supabase branching.** Branching is designed for exactly
   this, but its automated migration flow runs `supabase/migrations` SQL files via the
   Supabase CLI — we use Alembic. We'd get the isolated instance and fight the tooling,
   for the same ~$10/mo.
2. **The move is cheap because of how this plan is built.** Going from `dev` schema to a
   separate dev project is a handful of environment variables — `DATABASE_URL`,
   `DB_SCHEMA=public`, `SUPABASE_URL` — plus `SUPABASE_URL`/anon key in
   `app/env/dev.json`. No code changes; the shared-`auth.users` wart in §1 disappears on
   its own; and §8's catalog-slice problem goes away entirely, because dev gets its own
   8 GB. Nothing here is a decision we get locked into.

---

## 12. Risks, honestly

| Risk | Severity | Mitigation |
|---|---|---|
| A dev deploy writes into `public` | **Catastrophic** | The `kitabi_dev` role has zero privileges on `public` (§3) — it fails with `permission denied`, not silent corruption. Plus the startup assertion in §4.1. Verify the wall on day one and after any Supabase role change. |
| Dev catalog slice grows into a full copy | **High** | §8. Check Supabase → Usage after every seed; the 500 MB ceiling is shared with prod. |
| An ETL run points at prod by accident | High | ETL scripts read `DATABASE_URL` from the environment. Keep the prod URL out of `api/.env`; pass it explicitly per invocation, and prefer `05_load_prod.sh` for prod so the intent is in the filename. |
| Dev test users pollute `auth.users` | Medium | One dedicated dev Google account, documented. Filter it out of any auth cleanup. |
| Dev service never sleeps → surprise bill | Medium | `SCHEDULER_ENABLED=false` + `NullPool` + no uptime pinger on the dev URL + admin not deployed to dev. Check Railway's usage graph a week after enabling; a flat line means it never slept. |
| Cold-start 502s mistaken for real bugs | Low | Documented here; hit `/healthz` first. |
| Supabase changes free-project rules | Low | Doesn't affect this design — we use one project either way. If you go Pro later, promote dev to a real second project and drop the `dev` schema; nothing else changes. |

---

## 13. Implementation checklist

- [ ] §3 SQL: `dev` schema, `kitabi_dev` role, grants, `search_path`, revokes, `extensions`
- [ ] §3 verification queries pass (`public` access denied)
- [ ] `covers-dev` storage bucket
- [ ] Dev Google test account created and recorded
- [ ] `dev` branch created; `main` protected
- [ ] `config.py`: `db_schema`, `covers_bucket`, `is_prod` + startup assertion
- [ ] `extraction_service.py`: bucket prefix reads `covers_bucket`
- [ ] `db.py`: `NullPool` when not prod
- [ ] `alembic/env.py`: schema creation, `search_path`, `version_table_schema`
- [ ] `api-ci.yml` / `app-ci.yml` / `admin-ci.yml`: add `dev` to push branches
- [ ] `backup.yml`: `-N dev`
- [ ] Railway `dev` environment: duplicated, `admin` removed, branch `dev`, Serverless on,
      variables set
- [ ] `dev-api.kitabi.in` CNAME (DNS-only)
- [ ] First dev deploy green; RLS loop run; `dev` not an exposed schema
- [ ] Catalog slice seeded (§8) and usage checked
- [ ] `app/env/{prod,dev}.json`, Android `.dev` build type, Firebase second Android app,
      env-suffixed Drift filename, dev banner
- [ ] STATUS.md and build.md updated to describe two environments
