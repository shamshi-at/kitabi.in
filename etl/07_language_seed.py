"""Per-language catalog seed from the OpenLibrary *live* API.

The dump pipeline (01→03) needs the 9.2 GB editions dump; this job instead
asks the OL search API for the top-N works **per language** (reader-interest
ranked, `sort=readinglog`), fetches each selected work / best edition / author
as full JSON records — the same shape the bulk dumps carry — and writes the
works/editions/authors `.jsonl.gz` files that `03_transform.py` already
consumes. Everything downstream (translit/fold, native script, uuid5 ids,
publisher normalization, idempotent `04_load.sql`) is inherited unchanged.

Selection per language:
    Indic codes  →  q="language:<code>"           (books *in* the language)
    eng          →  q="language:eng subject:india" (English books Indian
                                                    readers reach for)

Ranking is OL's reading-log count, so an Indic list is a mix of native
literature and in-language translations of global hits — both are "books an
Indian audience is interested in, available in that language". The stored
edition is always one *in the target language*.

Dedup, three layers: a work key is claimed by the first language that selects
it (Indic languages run before eng); within a language, a second work whose
*normalized title* matches one already kept is skipped — OL itself carries
duplicate work records for popular books ("The palace of illusions" / "The
Palace of Illusions"), distinct keys, same book; and `04_load.sql` skips
anything already in the catalog by external_id — so re-runs converge.

Covers: the chosen edition's own cover when it has one, else the work's cover
(same artwork, possibly another language's jacket — better than a blank).
Author photos come along for free via `authors.photos`.

Usage:
    api/.venv/bin/python 07_language_seed.py --out-dir ~/ol-dumps/langseed \
        [--per-lang 100] [--langs mal,tam,...,eng] [--concurrency 4]

Takes ~10–20 min for 14 languages × 100 (≈4k polite API calls, 4-way).
"""

from __future__ import annotations

import argparse
import gzip
import json
import random
import re
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from ol_stream import INDIC_LANG_CODES, edition_lang_codes, work_author_keys

BASE = "https://openlibrary.org"
UA = "KitabiSeed/1.0 (kitabi.in; at.shamshi@gmail.com)"
SEARCH_FIELDS = "key,cover_i,editions,editions.key,editions.cover_i"
PAGE_SIZE = 100
MAX_PAGES = 5  # overfetch: up to 500 candidates per language to fill 100
MIN_INTERVAL = 0.25  # seconds between request *starts*, across all threads

CACHE_DIR: Path | None = None  # set in main(); record fetches survive re-runs
_pace_lock = threading.Lock()
_last_start = 0.0


def _pace() -> None:
    """Keep the aggregate request rate polite regardless of thread count."""
    global _last_start
    with _pace_lock:
        wait = _last_start + MIN_INTERVAL - time.monotonic()
        if wait > 0:
            time.sleep(wait)
        _last_start = time.monotonic()


def get_json(path: str, tries: int = 5) -> dict | None:
    """GET {BASE}{path} with pacing, retry/backoff (503 waits much longer,
    that's OL saying slow down), and a disk cache so a re-run resumes instead
    of re-crawling. None after final failure."""
    cache = None
    if CACHE_DIR is not None and path.endswith(".json"):
        cache = CACHE_DIR / re.sub(r"[^A-Za-z0-9._-]", "_", path.lstrip("/"))
        if cache.exists():
            try:
                return json.loads(cache.read_text(encoding="utf-8"))
            except (json.JSONDecodeError, OSError):
                pass
    url = BASE + path
    for attempt in range(tries):
        try:
            _pace()
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=40) as resp:
                body = resp.read().decode("utf-8")
            data = json.loads(body)
            if cache is not None:
                cache.write_text(body, encoding="utf-8")
            return data
        except (
            urllib.error.URLError,
            TimeoutError,
            json.JSONDecodeError,
            OSError,
        ) as e:
            if attempt == tries - 1:
                print(f"  !! gave up on {path}: {e}", file=sys.stderr)
                return None
            throttled = isinstance(e, urllib.error.HTTPError) and e.code in (429, 503)
            time.sleep((15 if throttled else 2**attempt) + random.random() * 2)
    return None


def norm_title(title: str) -> str:
    """Collapse case/punctuation/article noise so OL's duplicate work records
    for the same book compare equal ("Chokher bali." == "Chokher Bali")."""
    t = re.sub(r"\W+", " ", title.casefold(), flags=re.UNICODE).strip()
    return re.sub(r"^(the|a|an) ", "", t)


def search_page(query: str, page: int) -> list[dict]:
    qs = urllib.parse.urlencode(
        {
            "q": query,
            "sort": "readinglog",
            "fields": SEARCH_FIELDS,
            "limit": PAGE_SIZE,
            "page": page,
        }
    )
    data = get_json(f"/search.json?{qs}")
    return data.get("docs", []) if data else []


def fetch_candidate(cand: tuple[str, str, int | None], lang: str) -> dict | None:
    """Fetch full work + edition records for one search hit; patch the edition
    so the transform sees language, work link, and a cover. Returns
    {work, edition, author_keys} or None."""
    work_key, ed_key, work_cover = cand
    work = get_json(f"{work_key}.json")
    if not work or not (work.get("title") or "").strip():
        return None
    edition = get_json(f"{ed_key}.json")
    if not edition:
        return None
    # The dump records these come from always carry key/works/languages; the
    # live API mostly does too — patch the gaps rather than drop the book.
    # Force, don't setdefault: for OL's *orphaned editions* the search index
    # invents a virtual work key (/works/OL…M) and GET on it returns the
    # edition record itself — whose embedded key is /books/OL…M. Keeping that
    # would break the work↔edition link downstream.
    work["key"] = work_key
    edition["key"] = ed_key
    # Pin the edition to the work we're seeding — unconditionally. On ~4% of
    # records the live edition's works[] points at a *different* (merged /
    # redirected) work than the search index said, and the transform would
    # then drop the edition, leaving an edition-less work in the catalog.
    edition["works"] = [{"key": work_key}]
    codes = edition_lang_codes(edition)
    if not codes:
        edition["languages"] = [{"key": f"/languages/{lang}"}]
    elif codes[0] != lang and lang in codes:
        # Bilingual editions (an Assamese–English dictionary matches
        # language:asm with codes [eng, asm]): the transform buckets a work
        # by its edition's *first* code, so the target language leads.
        edition["languages"] = sorted(
            edition["languages"], key=lambda e: e.get("key") != f"/languages/{lang}"
        )
    # OL keeps one work for all translations, titled in the original language;
    # Kitabi's Work is per-translation. The in-language edition's own title
    # (e.g. അനിമൽ ഫാം, not "Animal Farm") is the one this catalog row is about.
    ed_title = (edition.get("title") or "").strip()
    if ed_title:
        work["title"] = ed_title
        work["subtitle"] = edition.get("subtitle")
    covers = [c for c in edition.get("covers") or [] if isinstance(c, int) and c > 0]
    if not covers:
        fallback = work_cover or next(
            (c for c in work.get("covers") or [] if isinstance(c, int) and c > 0), None
        )
        if fallback:
            edition["covers"] = [fallback]
    return {"work": work, "edition": edition, "author_keys": work_author_keys(work)}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--per-lang", type=int, default=100)
    ap.add_argument(
        "--langs",
        default=",".join(sorted(INDIC_LANG_CODES)) + ",eng",
        help="MARC codes; eng gets the subject:india query. Indic run first.",
    )
    ap.add_argument("--concurrency", type=int, default=4)
    args = ap.parse_args()

    global CACHE_DIR
    CACHE_DIR = Path(args.out_dir) / "cache"
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    langs = [c.strip() for c in args.langs.split(",") if c.strip()]
    langs.sort(
        key=lambda c: c == "eng"
    )  # eng last: Indic languages claim shared works first

    claimed: set[str] = set()  # work keys already selected (cross-language dedup)
    kept: dict[str, list[dict]] = {}
    pool = ThreadPoolExecutor(max_workers=args.concurrency)

    for lang in langs:
        query = "language:eng subject:india" if lang == "eng" else f"language:{lang}"
        rows: list[dict] = []
        seen_titles: set[str] = set()
        page = 1
        while len(rows) < args.per_lang and page <= MAX_PAGES:
            docs = search_page(query, page)
            if not docs:
                break
            cands = []
            for doc in docs:
                wk = doc.get("key")
                eds = (doc.get("editions") or {}).get("docs") or []
                ek = eds[0].get("key") if eds else None
                if not wk or not ek or wk in claimed:
                    continue
                claimed.add(wk)  # claim optimistically; a failed fetch just drops it
                cands.append((wk, ek, doc.get("cover_i")))
            for res in pool.map(lambda c: fetch_candidate(c, lang), cands):
                if not res or len(rows) >= args.per_lang:
                    continue
                tnorm = norm_title(res["work"]["title"])
                if tnorm in seen_titles:  # OL duplicate work record, same book
                    continue
                seen_titles.add(tnorm)
                rows.append(res)
            page += 1
        covers = sum(1 for r in rows if r["edition"].get("covers"))
        print(
            f"{lang}: kept {len(rows)}/{args.per_lang}  (covers {covers})", flush=True
        )
        if len(rows) < args.per_lang:
            print(
                f"  !! {lang} fell short — OL ran out of fetchable works",
                file=sys.stderr,
            )
        kept[lang] = rows

    # Authors: dedup across every kept work, then fetch once each.
    author_keys = sorted(
        {ak for rows in kept.values() for r in rows for ak in r["author_keys"]}
    )
    print(f"fetching {len(author_keys)} unique authors…", flush=True)
    authors = [a for a in pool.map(lambda k: get_json(f"{k}.json"), author_keys) if a]
    pool.shutdown()

    def dump(name: str, records) -> int:
        n = 0
        with gzip.open(f"{args.out_dir}/{name}.jsonl.gz", "wt", encoding="utf-8") as f:
            for rec in records:
                f.write(json.dumps(rec, ensure_ascii=False) + "\n")
                n += 1
        return n

    all_rows = [r for rows in kept.values() for r in rows]
    print(f"works.jsonl.gz: {dump('works', (r['work'] for r in all_rows))}")
    print(f"editions.jsonl.gz: {dump('editions', (r['edition'] for r in all_rows))}")
    print(f"authors.jsonl.gz: {dump('authors', authors)}")
    total_covers = sum(1 for r in all_rows if r["edition"].get("covers"))
    print(
        f"total: {len(all_rows)} works, {total_covers} with a cover "
        f"({100 * total_covers // max(len(all_rows), 1)}%)"
    )


if __name__ == "__main__":
    main()
