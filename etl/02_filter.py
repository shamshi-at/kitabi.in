"""Filter the full OL dumps down to the seed set.

Keep set = (works with at least one edition in a wanted language — Tier 1,
the Indic wedge) ∪ (top-N works by popularity — Tier 2, the global head).
Then emit exactly the records the transform needs, as gzipped JSONL:

    out-dir/works.jsonl.gz     kept works
    out-dir/editions.jsonl.gz  every edition of a kept work (capping happens
                               in the transform, which can score them)
    out-dir/authors.jsonl.gz   every author referenced by a kept work

Streams everything; the only memory held is key *sets* (a few hundred MB at
top=300k). Makes two passes over the editions dump — pass 1 to learn which
works have a wanted-language edition, pass 2 to extract editions of kept
works — so expect this to be the slow step (~1–2 h laptop).
"""

from __future__ import annotations

import argparse
import gzip
import json

from ol_stream import INDIC_LANG_CODES, edition_lang_codes, edition_work_keys, iter_dump, work_author_keys


def load_top_works(path: str | None, top: int) -> set[str]:
    keys: set[str] = set()
    if not path or top <= 0:
        return keys
    with open(path, encoding="utf-8") as f:
        for line in f:
            if len(keys) >= top:
                break
            key = line.split("\t", 1)[0].strip()
            if key.startswith("/works/"):
                keys.add(key)
    return keys


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--works", required=True)
    ap.add_argument("--editions", required=True)
    ap.add_argument("--authors", required=True)
    ap.add_argument("--popularity", help="TSV from 01_popularity.py")
    ap.add_argument("--top", type=int, default=300_000, help="popularity works to keep")
    ap.add_argument(
        "--languages",
        default=",".join(sorted(INDIC_LANG_CODES)),
        help="comma-separated MARC codes whose works are kept wholesale ('' to disable)",
    )
    ap.add_argument(
        "--max-works",
        type=int,
        default=0,
        help="cap the keep set at N works (0 = no cap). For bounded test runs; "
        "the cut is by sorted key, so the same inputs always give the same N.",
    )
    ap.add_argument("--out-dir", required=True)
    args = ap.parse_args()

    import os

    os.makedirs(args.out_dir, exist_ok=True)
    wanted_langs = {c.strip() for c in args.languages.split(",") if c.strip()}

    keep = load_top_works(args.popularity, args.top)
    print(f"tier 2 (popularity top {args.top:,}): {len(keep):,} works")

    # Pass 1 over editions: which works have an edition in a wanted language?
    if wanted_langs:
        lang_works: set[str] = set()
        scanned = 0
        for _typ, _key, ed in iter_dump(args.editions):
            scanned += 1
            if wanted_langs.intersection(edition_lang_codes(ed)):
                lang_works.update(edition_work_keys(ed))
        print(f"tier 1 ({','.join(sorted(wanted_langs))}): {len(lang_works):,} works "
              f"(scanned {scanned:,} editions)")
        keep |= lang_works
    if args.max_works and len(keep) > args.max_works:
        keep = set(sorted(keep)[: args.max_works])
        print(f"capped to --max-works {args.max_works:,}")
    print(f"keep set: {len(keep):,} works")

    # Works pass: write kept works, collect their author keys.
    author_keys: set[str] = set()
    kept_works = 0
    with gzip.open(f"{args.out_dir}/works.jsonl.gz", "wt", encoding="utf-8") as out:
        for _typ, key, work in iter_dump(args.works):
            if key in keep:
                out.write(json.dumps(work, ensure_ascii=False) + "\n")
                author_keys.update(work_author_keys(work))
                kept_works += 1
    print(f"works.jsonl.gz: {kept_works:,} works, referencing {len(author_keys):,} authors")

    # Pass 2 over editions: every edition of a kept work.
    kept_eds = 0
    with gzip.open(f"{args.out_dir}/editions.jsonl.gz", "wt", encoding="utf-8") as out:
        for _typ, _key, ed in iter_dump(args.editions):
            if any(wk in keep for wk in edition_work_keys(ed)):
                out.write(json.dumps(ed, ensure_ascii=False) + "\n")
                kept_eds += 1
    print(f"editions.jsonl.gz: {kept_eds:,} editions")

    # Authors pass.
    kept_authors = 0
    with gzip.open(f"{args.out_dir}/authors.jsonl.gz", "wt", encoding="utf-8") as out:
        for _typ, key, author in iter_dump(args.authors):
            if key in author_keys:
                out.write(json.dumps(author, ensure_ascii=False) + "\n")
                kept_authors += 1
    print(f"authors.jsonl.gz: {kept_authors:,} authors")


if __name__ == "__main__":
    main()
