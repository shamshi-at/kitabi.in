"""Transform filtered OL JSONL (from 02_filter.py) into Kitabi-schema CSVs.

Emits, in out-dir:
    works.csv  authors.csv  publishers.csv  editions.csv  work_authors.csv
ready for `04_load.sql` (\\copy + idempotent insert).

What happens here (see README for rationale):
- Deterministic uuid5 ids from OL keys, so re-runs produce identical rows.
- `title_translit`/`name_translit` computed with the API's own
  `app.services.translit.transliterate` (COPY bypasses the ORM hooks that
  normally maintain these) — run this with `api/.venv/bin/python`.
- A work's `language` = majority language of its editions (OL works carry no
  language); an author's `primary_language` = majority language of their works.
- Editions capped per work (default 5), best-scored first (cover/ISBN/wanted
  language/page count); duplicate ISBNs nulled (editions.isbn is UNIQUE).
- Publishers normalized from free-text edition strings, deduped case-insensitively.
"""

from __future__ import annotations

import argparse
import csv
import gzip
import json
import re
import sys
import uuid
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

from ol_stream import (
    INDIC_LANG_CODES,
    LANG_NAMES,
    cover_url_of,
    edition_lang_codes,
    edition_work_keys,
    first_year,
    isbn_of,
    ol_text,
    work_author_keys,
)

# The API's transliterate (anyascii + indic_transliteration) — the same
# function the ORM hooks run, so seeded rows search identically to app-written
# ones. Falls back to a plain-ASCII lowering if the import fails, with a loud
# warning, because a wrong translit silently breaks cross-script search.
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "api"))
try:
    from app.services.malayalam_script import to_malayalam_script
    from app.services.translit import fold, transliterate
except ImportError:  # pragma: no cover — wrong interpreter
    print(
        "WARNING: could not import app.services.translit — run with api/.venv/bin/python.\n"
        "Falling back to ASCII lowercasing; Indic titles will get WRONG translit values.",
        file=sys.stderr,
    )

    def transliterate(text):  # type: ignore[misc]
        return text.strip().lower() or None if isinstance(text, str) else None

    def to_malayalam_script(text):  # type: ignore[misc]
        return None

    def fold(text):  # type: ignore[misc]
        return None


def native_script(text: str | None) -> str | None:
    """OpenLibrary romanizes Malayalam (`Kēraḷa sthalanāmakōśaṃ`); store the
    native script instead. Returns [text] unchanged when there's nothing to
    convert — an English title, or one already in script."""
    return to_malayalam_script(text) or text


NS = uuid.uuid5(uuid.NAMESPACE_URL, "https://openlibrary.org")
NOW = datetime.now(timezone.utc).isoformat()
DESC_MAX = 5000
_WS = re.compile(r"\s+")

WORK_COLS = [
    "id", "created_at", "updated_at", "deleted_at", "title", "title_translit", "title_fold", "subtitle",
    "description", "language", "first_publish_year", "form", "aggregate_rating",
    "translation_group_id", "original_work_id", "external_source", "external_id",
    "created_by_user_id",
]
AUTHOR_COLS = [
    "id", "created_at", "updated_at", "deleted_at", "name", "name_translit", "name_fold", "pen_name",
    "image_url", "primary_language", "bio", "external_source", "external_id",
    "created_by_user_id", "linked_user_id",
]
PUBLISHER_COLS = [
    "id", "created_at", "updated_at", "deleted_at", "name", "name_translit", "name_fold", "logo_url",
    "primary_language", "external_source", "external_id",
]
EDITION_COLS = [
    "id", "created_at", "updated_at", "deleted_at", "work_id", "publisher_id", "series_id",
    "series_number", "isbn", "language", "page_count", "pub_date", "format", "cover_url",
    "back_cover_url", "buy_links", "external_source", "external_id",
]


def ol_id(key: str) -> str:
    return str(uuid.uuid5(NS, key))


def jsonl(path: Path):
    with gzip.open(path, "rt", encoding="utf-8") as f:
        for line in f:
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue


def writer(path: Path, cols: list[str]):
    f = open(path, "w", newline="", encoding="utf-8")
    w = csv.writer(f)
    w.writerow(cols)
    return f, w


def row(cols_values: dict) -> list:
    return ["" if v is None else v for v in cols_values.values()]


def edition_score(ed: dict, wanted_langs: set[str]) -> int:
    score = 0
    if cover_url_of(ed):
        score += 2
    if isbn_of(ed):
        score += 2
    if wanted_langs.intersection(edition_lang_codes(ed)):
        score += 1
    if ed.get("number_of_pages"):
        score += 1
    return score


def norm_format(ed: dict) -> str | None:
    raw = ed.get("physical_format")
    if not isinstance(raw, str) or not raw.strip():
        return None
    low = raw.strip().lower()
    if "paper" in low:
        return "paperback"
    if "hard" in low or "cloth" in low:
        return "hardcover"
    if "ebook" in low or "electronic" in low or "kindle" in low:
        return "ebook"
    return low[:40]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--in-dir", required=True, help="dir with works/editions/authors .jsonl.gz")
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--max-editions-per-work", type=int, default=5)
    ap.add_argument("--languages", default=",".join(sorted(INDIC_LANG_CODES)),
                    help="langs that boost an edition's keep-score")
    args = ap.parse_args()

    in_dir, out_dir = Path(args.in_dir), Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    wanted_langs = {c.strip() for c in args.languages.split(",") if c.strip()}

    # ---- Pass 1 over editions: per-work language mix, min year, best-K edition keys.
    work_langs: dict[str, Counter] = {}
    work_min_year: dict[str, int] = {}
    candidates: dict[str, list[tuple[int, str]]] = {}
    for ed in jsonl(in_dir / "editions.jsonl.gz"):
        wks = edition_work_keys(ed)
        if not wks:
            continue
        wk = wks[0]
        for code in edition_lang_codes(ed):
            work_langs.setdefault(wk, Counter())[code] += 1
        year = first_year(ed.get("publish_date"))
        if year and (wk not in work_min_year or year < work_min_year[wk]):
            work_min_year[wk] = year
        bucket = candidates.setdefault(wk, [])
        bucket.append((edition_score(ed, wanted_langs), ed.get("key", "")))
        if len(bucket) > args.max_editions_per_work * 3:  # keep buckets small as we go
            bucket.sort(reverse=True)
            del bucket[args.max_editions_per_work:]
    chosen: set[str] = set()
    for bucket in candidates.values():
        bucket.sort(reverse=True)
        chosen.update(key for _s, key in bucket[: args.max_editions_per_work] if key)
    print(f"editions pass 1: {len(candidates):,} works, {len(chosen):,} editions chosen")

    def majority_lang(counter: Counter | None) -> str | None:
        if not counter:
            return None
        return LANG_NAMES.get(counter.most_common(1)[0][0])

    # ---- Works.
    fw, works_csv = writer(out_dir / "works.csv", WORK_COLS)
    work_author_pairs: list[tuple[str, str]] = []  # (work_id, author_key)
    author_langs: dict[str, Counter] = {}
    kept_work_ids: set[str] = set()
    n_works = 0
    for work in jsonl(in_dir / "works.jsonl.gz"):
        key, title = work.get("key"), (work.get("title") or "").strip()
        if not key or not title:
            continue
        wid = ol_id(key)
        kept_work_ids.add(wid)
        lang = majority_lang(work_langs.get(key))
        desc = ol_text(work.get("description"))
        native = native_script(title)
        works_csv.writerow(row({
            "id": wid, "created_at": NOW, "updated_at": NOW, "deleted_at": None,
            "title": native, "title_translit": transliterate(native),
            "title_fold": fold(native),
            "subtitle": ol_text(work.get("subtitle")),
            "description": desc[:DESC_MAX] if desc else None,
            "language": lang,
            "first_publish_year": first_year(work.get("first_publish_date"))
            or work_min_year.get(key),
            "form": None, "aggregate_rating": None,
            "translation_group_id": None, "original_work_id": None,
            "external_source": "openlibrary", "external_id": key,
            "created_by_user_id": None,
        }))
        for ak in work_author_keys(work):
            work_author_pairs.append((wid, ak))
            if lang:
                author_langs.setdefault(ak, Counter())[lang] += 1
        n_works += 1
    fw.close()
    print(f"works.csv: {n_works:,}")

    # ---- Authors.
    fa, authors_csv = writer(out_dir / "authors.csv", AUTHOR_COLS)
    seen_author_ids: dict[str, str] = {}  # author key -> uuid
    n_authors = 0
    for author in jsonl(in_dir / "authors.jsonl.gz"):
        key, name = author.get("key"), (author.get("name") or "").strip()
        if not key or not name:
            continue
        aid = ol_id(key)
        seen_author_ids[key] = aid
        langs = author_langs.get(key)
        bio = ol_text(author.get("bio"))
        native = native_script(_WS.sub(" ", name))
        authors_csv.writerow(row({
            "id": aid, "created_at": NOW, "updated_at": NOW, "deleted_at": None,
            "name": native, "name_translit": transliterate(native),
            "name_fold": fold(native),
            "pen_name": None, "image_url": cover_url_of(author, kind="a"),
            "primary_language": langs.most_common(1)[0][0] if langs else None,
            "bio": bio[:DESC_MAX] if bio else None,
            "external_source": "openlibrary", "external_id": key,
            "created_by_user_id": None, "linked_user_id": None,
        }))
        n_authors += 1
    fa.close()
    print(f"authors.csv: {n_authors:,}")

    # ---- work_authors (only pairs whose author record actually exists).
    fwa, wa_csv = writer(out_dir / "work_authors.csv", ["work_id", "author_id"])
    pairs = {(wid, seen_author_ids[ak]) for wid, ak in work_author_pairs if ak in seen_author_ids}
    for wid, aid in sorted(pairs):
        wa_csv.writerow([wid, aid])
    fwa.close()
    print(f"work_authors.csv: {len(pairs):,}")

    # ---- Pass 2 over editions: write the chosen ones + normalized publishers.
    fe, editions_csv = writer(out_dir / "editions.csv", EDITION_COLS)
    fp, publishers_csv = writer(out_dir / "publishers.csv", PUBLISHER_COLS)
    publisher_ids: dict[str, str] = {}  # lower(name) -> uuid
    seen_isbns: set[str] = set()
    n_editions = 0
    for ed in jsonl(in_dir / "editions.jsonl.gz"):
        key = ed.get("key")
        if not key or key not in chosen:
            continue
        wks = edition_work_keys(ed)
        wid = ol_id(wks[0]) if wks else None
        if wid not in kept_work_ids:
            continue
        publisher_id = None
        for raw in ed.get("publishers") or []:
            if isinstance(raw, str) and raw.strip():
                name = _WS.sub(" ", raw.strip())
                low = name.lower()
                if low not in publisher_ids:
                    publisher_ids[low] = str(uuid.uuid5(NS, f"publisher:{low}"))
                    native = native_script(name)
                    publishers_csv.writerow(row({
                        "id": publisher_ids[low], "created_at": NOW, "updated_at": NOW,
                        "deleted_at": None, "name": native,
                        "name_translit": transliterate(native),
                        "name_fold": fold(native), "logo_url": None,
                        "primary_language": None, "external_source": "openlibrary",
                        "external_id": None,
                    }))
                publisher_id = publisher_ids[low]
                break
        isbn = isbn_of(ed)
        if isbn in seen_isbns:
            isbn = None  # editions.isbn is UNIQUE — first writer wins
        elif isbn:
            seen_isbns.add(isbn)
        codes = edition_lang_codes(ed)
        year = first_year(ed.get("publish_date"))
        pages = ed.get("number_of_pages")
        editions_csv.writerow(row({
            "id": ol_id(key), "created_at": NOW, "updated_at": NOW, "deleted_at": None,
            "work_id": wid, "publisher_id": publisher_id,
            "series_id": None, "series_number": None,
            "isbn": isbn, "language": LANG_NAMES.get(codes[0]) if codes else None,
            "page_count": pages if isinstance(pages, int) and 0 < pages < 20000 else None,
            "pub_date": f"{year}-01-01" if year else None,
            "format": norm_format(ed), "cover_url": cover_url_of(ed),
            "back_cover_url": None, "buy_links": None,
            "external_source": "openlibrary", "external_id": key,
        }))
        n_editions += 1
    fe.close()
    fp.close()
    print(f"editions.csv: {n_editions:,}; publishers.csv: {len(publisher_ids):,}")


if __name__ == "__main__":
    main()
