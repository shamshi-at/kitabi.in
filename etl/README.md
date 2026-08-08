# etl/ — OpenLibrary bulk-dump → Kitabi catalog seeding

Offline, run-on-your-Mac pipeline that turns the monthly [OpenLibrary bulk
dumps](https://openlibrary.org/developers/dumps) into CSVs matching Kitabi's
Layer-1 catalog tables (`works` / `editions` / `authors` / `publishers` /
`work_authors`), then loads them idempotently with `04_load.sql`.

**Never run this against prod casually.** Iterate against the local dev
Postgres (port 55442) first; the load script is transactional and
external-id-idempotent, but a seed is still a big, deliberate operation.

## Why a curated seed, not the full dump

The full dumps are ~50M editions / ~40M works / ~14M authors — 50–100+ GB in
Postgres with our trigram GIN indexes. Supabase free tier is 500 MB (CLAUDE.md
rule 8: no new bills). So the pipeline seeds **tiers**, not everything:

- **Tier 1 — the wedge, completely:** every work with an edition in an Indic
  language (default set below). Small; this is where Kitabi can win search.
- **Tier 2 — the global head:** top-N works by OpenLibrary popularity
  (ratings + reading-log dumps), default N = 300,000.
- **Tier 3 — everything else:** stays on the existing cache-on-first-use
  OpenLibrary path. Not seeded.

Genres are deliberately **not** seeded — OL "subjects" are far too noisy for
our curated `genres` table (CLAUDE.md rule 18 energy). Series are skipped for
the same reason. Both backfill organically.

## Prerequisites

- The `api/.venv` interpreter (it has `anyascii` + `indic_transliteration`,
  which the transform uses to fill `title_translit`/`name_translit` exactly
  like the API's ORM hooks would — `COPY` bypasses SQLAlchemy, so the ETL must
  do it itself).
- ~15 GB free disk for the compressed dumps + intermediates.
- `psql` for the load step.

## 1. Download the dumps (~13 GB total, monthly refresh)

```bash
mkdir -p ~/ol-dumps && cd ~/ol-dumps
curl -LO https://openlibrary.org/data/ol_dump_works_latest.txt.gz      # ~2.9 GB
curl -LO https://openlibrary.org/data/ol_dump_editions_latest.txt.gz   # ~9.2 GB
curl -LO https://openlibrary.org/data/ol_dump_authors_latest.txt.gz    # ~0.5 GB
curl -LO https://openlibrary.org/data/ol_dump_ratings_latest.txt.gz    # small
curl -LO https://openlibrary.org/data/ol_dump_reading-log_latest.txt.gz
```

(Archive.org torrents are faster if curl crawls — see the dumps page.)

## 2. Run the pipeline

All scripts stream gzip line-by-line — nothing loads a full dump into memory.
Rough runtimes on a laptop: popularity ~10 min, filter ~1–2 h (it makes two
passes over the 9.2 GB editions dump), transform ~15–30 min.

```bash
PY=../api/.venv/bin/python   # run from etl/; adjust as needed
D=~/ol-dumps
OUT=~/ol-dumps/kitabi

# 2a. Popularity scores (work key -> count) from ratings + reading log
$PY 01_popularity.py --ratings $D/ol_dump_ratings_latest.txt.gz \
    --reading-log $D/ol_dump_reading-log_latest.txt.gz \
    --out $D/work_popularity.tsv

# 2b. Filter to the seed set (Indic-language works ∪ top-N popular works)
$PY 02_filter.py --works $D/ol_dump_works_latest.txt.gz \
    --editions $D/ol_dump_editions_latest.txt.gz \
    --authors $D/ol_dump_authors_latest.txt.gz \
    --popularity $D/work_popularity.tsv --top 300000 \
    --out-dir $OUT

# 2c. Transform to Kitabi-schema CSVs (uuid5 ids, translit, publisher
#     normalization, ≤5 best editions per work)
$PY 03_transform.py --in-dir $OUT --out-dir $OUT/csv
```

## 3. Load

```bash
cd $OUT/csv
psql "$DATABASE_URL" -f /path/to/kitabi.in/etl/04_load.sql
```

`04_load.sql` stages the CSVs into temp tables, inserts only rows whose
`external_id` (or, for publishers, case-insensitive name) isn't already
present, and resolves every FK through external-id maps — so re-running it,
or running it on a catalog that already cached some of the same books via the
app's OpenLibrary path, converges instead of duplicating. All-or-nothing
(single transaction).

After a load, `ANALYZE works; ANALYZE editions; ANALYZE authors;` is worth
running — the trigram GIN indexes benefit from fresh stats.

## Quick test run (~100 Malayalam books, ~4.6 GB download)

Validates the whole pipeline against the **local dev DB** before committing to
a real seed. The trick that makes it cheap: only the *editions* dump needs to
be big, so download a ranged prefix of it — but **works and authors must be
the full dumps**.

Why: languages live on editions, so a prefix of editions is a fine sample of
Malayalam books. But the work keys it yields are scattered across the whole
works dump, so a truncated works dump contains almost none of them — a
prefix-only run emits `works.jsonl.gz: 0 works` and silently produces nothing.
Measured rate: **~40 Malayalam works per 32 MB** of the editions dump.

```bash
cd ~/ol-dumps
# editions: first 100 MB only  (~125 Malayalam works)
curl -L -r 0-104857599 https://openlibrary.org/data/ol_dump_editions_latest.txt.gz -o ol_editions_prefix.txt.gz
# works + authors: FULL, or the join finds nothing
curl -LO https://openlibrary.org/data/ol_dump_works_latest.txt.gz     # ~4.0 GB
curl -LO https://openlibrary.org/data/ol_dump_authors_latest.txt.gz   # ~0.5 GB
```

```bash
cd /path/to/kitabi.in/etl
PY=../api/.venv/bin/python; D=~/ol-dumps; OUT=$D/maltest

$PY 02_filter.py --works $D/ol_dump_works_latest.txt.gz \
    --editions $D/ol_editions_prefix.txt.gz \
    --authors $D/ol_dump_authors_latest.txt.gz \
    --languages mal --top 0 --max-works 100 --out-dir $OUT
$PY 03_transform.py --in-dir $OUT --out-dir $OUT/csv
```

`--top 0` skips the popularity tier entirely; `--max-works 100` caps the keep
set (cut by sorted key, so re-runs give the same 100).

Load into the **local** DB — never prod for a test. There's no `psql` on the
host, so go through the compose container:

```bash
cd /path/to/kitabi.in/api && docker compose up -d db
DATABASE_URL="postgresql+asyncpg://postgres:postgres@localhost:55442/kitabi" .venv/bin/alembic upgrade head
docker cp ~/ol-dumps/maltest/csv api-db-1:/tmp/seedcsv
docker cp ../etl/04_load.sql api-db-1:/tmp/seedcsv/
docker exec -w /tmp/seedcsv api-db-1 psql -U postgres -d kitabi -f 04_load.sql
```

Check what landed, including that cross-script search will work:

```bash
docker exec api-db-1 psql -U postgres -d kitabi -c \
  "select title, title_translit, language, first_publish_year from works limit 10;"
docker exec api-db-1 psql -U postgres -d kitabi -c \
  "select count(*) works, (select count(*) from editions) eds, (select count(*) from authors) authors from works;"
```

`title_translit` must be populated on Malayalam titles (e.g. കയർ → `kayar`) —
if it's null or wrong, 03_transform.py wasn't run with `api/.venv/bin/python`
and the romanized search column is broken. Re-running `04_load.sql` inserts 0
rows, so it's safe to repeat. To start over:
`TRUNCATE work_authors, editions, publishers, authors, works CASCADE;`

## The per-language seed job (no dumps needed)

`07_run_language_seed.sh` is a one-command job that fills the catalog with the
**top ~100 reader-interest books per language** — the 13 Indic languages plus
an India-focused English list (`language:eng subject:india`) — straight from
the OpenLibrary **live API**, no 9 GB dump download:

```bash
cd etl
SEED_PROD_YES="SEED PROD" ./07_run_language_seed.sh          # ~/ol-dumps/langseed, 100/lang
./07_run_language_seed.sh ~/ol-dumps/langseed 50             # custom workdir / quota
```

How it stays sane:

- **Ranking** is OL's reading-log count (`sort=readinglog`), so each Indic
  list is a mix of native literature and in-language translations of global
  hits — both are "books an Indian audience reaches for". The stored edition
  is always one *in the target language*, and the Work's title comes from
  that edition (അനിമൽ ഫാം, not "Animal Farm") to match Kitabi's
  Work-per-translation model.
- **No duplicates, three layers:** a work key is claimed by the first
  language that selects it (Indic before English); within a language a
  second work whose *normalized title* matches one already kept is skipped —
  OL carries duplicate work records for popular books ("The palace of
  illusions" / "The Palace of Illusions"); and `04_load.sql` skips anything
  already in the catalog by external_id — re-runs converge.
- **Covers:** the edition's own cover when it has one, else the work-level
  cover; author photos come through too.
- **Politeness/resume:** ~4 requests/s aggregate, hard backoff on 429/503,
  and every record fetch is disk-cached in `workdir/cache/` — a re-run after
  a network wobble resumes instead of re-crawling (~4k requests, 20–30 min
  cold for 14×100).

`07_language_seed.py` (the fetch step) emits the same `works/editions/authors
.jsonl.gz` files as `02_filter.py`, so the transform + load stay the shared,
already-tested path.

## Genre & form classification (`08_genre_classify.py`)

Genres are deliberately *not* seeded from OL subjects (too noisy — see above).
Instead, `08_genre_classify.py` classifies the seeded works against the API's
**closed ~34-genre vocabulary** (`api/app/services/genre_vocab.py` — one
source of truth, the script imports it) plus the existing `WORK_FORMS` Type
vocabulary, LLM-assisted with a human between the model and the database
(docs/tasks.md W5):

```bash
cd etl
../api/.venv/bin/python 08_genre_classify.py plan --out genre_plan.jsonl   # DB read-only
# review: jq -c 'select(.confidence=="low")' genre_plan.jsonl
../api/.venv/bin/python 08_genre_classify.py apply --plan genre_plan.jsonl --production
../api/.venv/bin/python 08_genre_classify.py revert --receipt genre_receipt.jsonl --production
```

The guard-rails, because genre hubs are **indexed public pages**:

- Claude (`claude-sonnet-5`, thinking disabled) may answer **unknown** — an
  honest blank beats a plausible guess; only `high,medium` confidence applies
  by default, and rows outside the vocabulary are dropped at parse time.
- `apply` refuses a non-local `DATABASE_URL` without `--production` (the
  alembic/env.py rule), never overwrites an existing `works.form`, is
  idempotent, and writes a **receipt** of exactly what it changed.
- `revert --receipt` undoes exactly one receipt — links it created, forms it
  set (only if still unchanged) — so a bad batch is one command from gone.
- `plan` is resumable: works already in the plan file are skipped.

## Sizing before you commit to a tier

`sample_stats.py` estimates row counts, field coverage, language mix, and the
approximate Postgres footprint from a *partial* download, so you can size
tiers without pulling 12 GB:

```bash
curl -sL -r 0-33554431 https://openlibrary.org/data/ol_dump_works_latest.txt.gz -o works_prefix.gz
$PY sample_stats.py works_prefix.gz --full-gz-bytes 3113851289   # actual size of the full dump
```

## Design notes / gotchas

- **Deterministic ids:** every row's UUID is `uuid5` of its OpenLibrary key,
  so re-runs and partial re-loads produce identical ids. The load script still
  maps through `external_id`, because rows previously cached by the *API*
  (cache-on-first-use) carry random uuid4 ids.
- **ISBN uniqueness:** `editions.isbn` is UNIQUE. The transform nulls the ISBN
  on any edition whose ISBN was already emitted; the load skips editions whose
  ISBN exists in the live table.
- **Works have no language in OL** — a work's `language` is the majority
  language of its editions; an author's `primary_language` is the majority
  language of their works.
- **Editions per work are capped** (default 5, `--max-editions-per-work`),
  scored by has-cover / has-ISBN / wanted-language / has-page-count. Pride &
  Prejudice has 500+ editions; nobody needs them all in a seed.
- **Descriptions are clamped** to 5,000 chars in the transform (a handful of
  OL descriptions are entire pasted texts).
- Default Indic language set (`--languages`): `mal tam tel kan hin ben mar
  guj pan ori asm urd san`.
