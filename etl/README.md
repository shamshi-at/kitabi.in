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
