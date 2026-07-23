-- 04_load.sql — idempotent load of the transform's CSVs into the live catalog.
--
-- Run from the directory holding the CSVs (03_transform.py's --out-dir):
--     cd <out-dir> && psql "$DATABASE_URL" -f /path/to/kitabi.in/etl/04_load.sql
--
-- Everything runs in ONE transaction: stage the CSVs into temp tables, insert
-- only rows not already present (matched by openlibrary external_id; for
-- publishers by case-insensitive name), and resolve every FK through a
-- stage-id -> live-id map — necessary because the API's cache-on-first-use
-- path may have already created some of these rows under random uuid4 ids.
-- Re-running converges to the same state (CLAUDE.md: seeds must be boring).

\set ON_ERROR_STOP on

BEGIN;

-- ---------------------------------------------------------------- staging
CREATE TEMP TABLE stage_works (
    id uuid PRIMARY KEY,
    created_at timestamptz, updated_at timestamptz, deleted_at timestamptz,
    title text, title_translit text, subtitle text, description text,
    language text, first_publish_year int, form text, aggregate_rating float8,
    translation_group_id uuid, original_work_id uuid,
    external_source text, external_id text, created_by_user_id uuid
) ON COMMIT DROP;

CREATE TEMP TABLE stage_authors (
    id uuid PRIMARY KEY,
    created_at timestamptz, updated_at timestamptz, deleted_at timestamptz,
    name text, name_translit text, pen_name text, image_url text,
    primary_language text, bio text,
    external_source text, external_id text,
    created_by_user_id uuid, linked_user_id uuid
) ON COMMIT DROP;

CREATE TEMP TABLE stage_publishers (
    id uuid PRIMARY KEY,
    created_at timestamptz, updated_at timestamptz, deleted_at timestamptz,
    name text, name_translit text, logo_url text, primary_language text,
    external_source text, external_id text
) ON COMMIT DROP;

CREATE TEMP TABLE stage_editions (
    id uuid PRIMARY KEY,
    created_at timestamptz, updated_at timestamptz, deleted_at timestamptz,
    work_id uuid, publisher_id uuid, series_id uuid, series_number int,
    isbn text, language text, page_count int, pub_date date, format text,
    cover_url text, back_cover_url text, buy_links jsonb,
    external_source text, external_id text
) ON COMMIT DROP;

CREATE TEMP TABLE stage_work_authors (
    work_id uuid, author_id uuid
) ON COMMIT DROP;

\copy stage_works FROM 'works.csv' WITH (FORMAT csv, HEADER true, NULL '')
\copy stage_authors FROM 'authors.csv' WITH (FORMAT csv, HEADER true, NULL '')
\copy stage_publishers FROM 'publishers.csv' WITH (FORMAT csv, HEADER true, NULL '')
\copy stage_editions FROM 'editions.csv' WITH (FORMAT csv, HEADER true, NULL '')
\copy stage_work_authors FROM 'work_authors.csv' WITH (FORMAT csv, HEADER true, NULL '')

-- ------------------------------------------------------- works + author rows
INSERT INTO works (id, created_at, updated_at, deleted_at, title, title_translit,
                   subtitle, description, language, first_publish_year, form,
                   aggregate_rating, translation_group_id, original_work_id,
                   external_source, external_id, created_by_user_id)
SELECT s.id, s.created_at, s.updated_at, s.deleted_at, s.title, s.title_translit,
       s.subtitle, s.description, s.language, s.first_publish_year, s.form,
       s.aggregate_rating, s.translation_group_id, s.original_work_id,
       s.external_source, s.external_id, s.created_by_user_id
FROM stage_works s
WHERE NOT EXISTS (SELECT 1 FROM works w
                  WHERE w.external_source = 'openlibrary'
                    AND w.external_id = s.external_id);

INSERT INTO authors (id, created_at, updated_at, deleted_at, name, name_translit,
                     pen_name, image_url, primary_language, bio,
                     external_source, external_id, created_by_user_id, linked_user_id)
SELECT s.id, s.created_at, s.updated_at, s.deleted_at, s.name, s.name_translit,
       s.pen_name, s.image_url, s.primary_language, s.bio,
       s.external_source, s.external_id, s.created_by_user_id, s.linked_user_id
FROM stage_authors s
WHERE NOT EXISTS (SELECT 1 FROM authors a
                  WHERE a.external_source = 'openlibrary'
                    AND a.external_id = s.external_id);

INSERT INTO publishers (id, created_at, updated_at, deleted_at, name, name_translit,
                        logo_url, primary_language, external_source, external_id)
SELECT s.id, s.created_at, s.updated_at, s.deleted_at, s.name, s.name_translit,
       s.logo_url, s.primary_language, s.external_source, s.external_id
FROM stage_publishers s
WHERE NOT EXISTS (SELECT 1 FROM publishers p
                  WHERE lower(p.name) = lower(s.name) AND p.deleted_at IS NULL);

-- ------------------------------------------- stage-id -> live-id resolution
CREATE TEMP TABLE work_map ON COMMIT DROP AS
SELECT DISTINCT ON (s.id) s.id AS stage_id, w.id AS real_id
FROM stage_works s
JOIN works w ON w.external_source = 'openlibrary' AND w.external_id = s.external_id
ORDER BY s.id, w.created_at;

CREATE TEMP TABLE author_map ON COMMIT DROP AS
SELECT DISTINCT ON (s.id) s.id AS stage_id, a.id AS real_id
FROM stage_authors s
JOIN authors a ON a.external_source = 'openlibrary' AND a.external_id = s.external_id
ORDER BY s.id, a.created_at;

CREATE TEMP TABLE publisher_map ON COMMIT DROP AS
SELECT DISTINCT ON (s.id) s.id AS stage_id, p.id AS real_id
FROM stage_publishers s
JOIN publishers p ON lower(p.name) = lower(s.name) AND p.deleted_at IS NULL
ORDER BY s.id, p.created_at;

-- ------------------------------------------------------ editions + joins
INSERT INTO editions (id, created_at, updated_at, deleted_at, work_id, publisher_id,
                      series_id, series_number, isbn, language, page_count, pub_date,
                      format, cover_url, back_cover_url, buy_links,
                      external_source, external_id)
SELECT s.id, s.created_at, s.updated_at, s.deleted_at, wm.real_id, pm.real_id,
       s.series_id, s.series_number,
       -- editions.isbn is UNIQUE: yield to any live row that already owns it
       CASE WHEN s.isbn IS NOT NULL
                 AND NOT EXISTS (SELECT 1 FROM editions e WHERE e.isbn = s.isbn)
            THEN s.isbn END,
       s.language, s.page_count, s.pub_date, s.format, s.cover_url,
       s.back_cover_url, s.buy_links, s.external_source, s.external_id
FROM stage_editions s
JOIN work_map wm ON wm.stage_id = s.work_id
LEFT JOIN publisher_map pm ON pm.stage_id = s.publisher_id
WHERE NOT EXISTS (SELECT 1 FROM editions e
                  WHERE e.external_source = 'openlibrary'
                    AND e.external_id = s.external_id);

INSERT INTO work_authors (work_id, author_id)
SELECT DISTINCT wm.real_id, am.real_id
FROM stage_work_authors s
JOIN work_map wm ON wm.stage_id = s.work_id
JOIN author_map am ON am.stage_id = s.author_id
WHERE NOT EXISTS (SELECT 1 FROM work_authors wa
                  WHERE wa.work_id = wm.real_id AND wa.author_id = am.real_id);

-- ------------------------------------------------------------- summary
SELECT (SELECT count(*) FROM works)      AS works_total,
       (SELECT count(*) FROM editions)   AS editions_total,
       (SELECT count(*) FROM authors)    AS authors_total,
       (SELECT count(*) FROM publishers) AS publishers_total;

COMMIT;

-- Worth running after a big load (fresh stats for the trigram GIN indexes):
--   ANALYZE works; ANALYZE editions; ANALYZE authors; ANALYZE publishers;
