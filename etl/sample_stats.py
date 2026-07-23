"""Size a dump from a partial (ranged) download — no 12 GB pull required.

Feed it a prefix of a works/editions/authors dump (see README for the curl -r
one-liner). It streams whatever decompresses, reports field coverage and the
average bytes each record would occupy mapped into Kitabi's schema, and — if
told the full dump's compressed size — extrapolates total row counts.

    python sample_stats.py works_prefix.gz --full-gz-bytes 3113851289

Caveat: the sample is the *front* of the dump (records are in key order, i.e.
roughly oldest-first), so treat language/coverage percentages as indicative,
not exact.
"""

from __future__ import annotations

import argparse
import json
import os
from collections import Counter

from ol_stream import (
    INDIC_LANG_CODES,
    cover_url_of,
    edition_lang_codes,
    isbn_of,
    iter_dump,
    ol_text,
)

# Rough per-row Postgres overhead: 24 B tuple header + item pointer + null
# bitmap + fixed columns (uuids, timestamps) — before the variable text.
ROW_OVERHEAD = {"works": 150, "editions": 190, "authors": 140}


def mapped_bytes(kind: str, rec: dict) -> int:
    """Approximate heap bytes for this record mapped into our schema (translit
    column ~= title again; +4 B varlena header per text field, folded into
    ROW_OVERHEAD)."""
    n = ROW_OVERHEAD[kind]
    if kind == "works":
        title = rec.get("title") or ""
        n += 2 * len(title.encode()) + len((ol_text(rec.get("subtitle")) or "").encode())
        n += min(len((ol_text(rec.get("description")) or "").encode()), 5000)
        n += 30  # language + external_id
    elif kind == "editions":
        n += len((rec.get("key") or "").encode()) + 20  # external_id + isbn
        if cover_url_of(rec):
            n += 55
    elif kind == "authors":
        name = rec.get("name") or ""
        n += 2 * len(name.encode())
        n += min(len((ol_text(rec.get("bio")) or "").encode()), 5000)
        n += 30
    return n


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("prefix", help="partial .txt.gz download")
    ap.add_argument("--kind", choices=["works", "editions", "authors"],
                    help="defaults to a guess from the filename")
    ap.add_argument("--full-gz-bytes", type=int,
                    help="compressed size of the FULL dump, to extrapolate row counts")
    args = ap.parse_args()

    kind = args.kind
    if not kind:
        for k in ("works", "editions", "authors"):
            if k in os.path.basename(args.prefix):
                kind = k
                break
    if not kind:
        ap.error("cannot guess --kind from filename; pass it explicitly")

    rows = 0
    json_bytes = 0
    pg_bytes = 0
    with_desc = with_cover = with_isbn = with_lang = with_pages = 0
    langs: Counter = Counter()
    title_bytes = 0

    for _typ, _key, rec in iter_dump(args.prefix):
        rows += 1
        json_bytes += len(json.dumps(rec, ensure_ascii=False).encode())
        pg_bytes += mapped_bytes(kind, rec)
        if kind in ("works", "authors"):
            field = "description" if kind == "works" else "bio"
            if ol_text(rec.get(field)):
                with_desc += 1
            title_bytes += len((rec.get("title") or rec.get("name") or "").encode())
        if kind == "editions":
            codes = edition_lang_codes(rec)
            if codes:
                with_lang += 1
                langs[codes[0]] += 1
            if isbn_of(rec):
                with_isbn += 1
            if rec.get("number_of_pages"):
                with_pages += 1
        if cover_url_of(rec, kind="a" if kind == "authors" else "b"):
            with_cover += 1

    if not rows:
        print("no rows decoded — is the file a valid dump prefix?")
        return

    prefix_size = os.path.getsize(args.prefix)
    print(f"kind: {kind}")
    print(f"rows decoded from {prefix_size / 2**20:.0f} MB prefix: {rows:,}")
    print(f"avg raw JSON: {json_bytes / rows:.0f} B; avg mapped PG heap: {pg_bytes / rows:.0f} B")
    print(f"avg title/name: {title_bytes / rows:.0f} B" if kind != "editions" else "", end="")
    if kind in ("works", "authors"):
        print(f"; with description/bio: {100 * with_desc / rows:.1f}%")
    print(f"with cover: {100 * with_cover / rows:.1f}%")
    if kind == "editions":
        print(f"with ISBN: {100 * with_isbn / rows:.1f}%; with language: "
              f"{100 * with_lang / rows:.1f}%; with pages: {100 * with_pages / rows:.1f}%")
        indic = sum(n for c, n in langs.items() if c in INDIC_LANG_CODES)
        print(f"Indic-language editions in sample: {indic:,} "
              f"({100 * indic / max(with_lang, 1):.2f}% of language-tagged)")
        print("top languages:", ", ".join(f"{c}:{n:,}" for c, n in langs.most_common(12)))

    if args.full_gz_bytes:
        scale = args.full_gz_bytes / prefix_size
        est_rows = int(rows * scale)
        est_heap_gb = est_rows * (pg_bytes / rows) / 2**30
        print(f"— extrapolated (×{scale:.0f}): ~{est_rows:,} rows total; "
              f"~{est_heap_gb:.1f} GB heap if ALL were loaded (indexes extra, roughly +60–100%)")


if __name__ == "__main__":
    main()
