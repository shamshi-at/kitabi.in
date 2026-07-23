"""Build a work-popularity table from the OL ratings + reading-log dumps.

Output: a TSV of `work_key<TAB>score`, sorted descending — `02_filter.py`
takes the top N as the seed's "global head" tier. Score is simply the number
of rating rows plus reading-log rows attached to the work; crude, but it
ranks Pride & Prejudice above a 1970s technical manual, which is all a seed
needs.

Usage:
    python 01_popularity.py --ratings ol_dump_ratings_latest.txt.gz \
        --reading-log ol_dump_reading-log_latest.txt.gz --out work_popularity.tsv
"""

from __future__ import annotations

import argparse
from collections import Counter

from ol_stream import iter_tsv


def count_works(path: str, counter: Counter) -> int:
    """Tally the /works/… key on each row. Column layouts differ slightly
    between the two dumps (and have shifted historically), so find the work
    key positionally rather than trusting a fixed column index."""
    rows = 0
    for cols in iter_tsv(path):
        for col in cols:
            if col.startswith("/works/"):
                counter[col] += 1
                rows += 1
                break
    return rows


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--ratings", help="ol_dump_ratings_*.txt.gz")
    ap.add_argument("--reading-log", dest="reading_log", help="ol_dump_reading-log_*.txt.gz")
    ap.add_argument("--out", required=True, help="output TSV path")
    args = ap.parse_args()
    if not args.ratings and not args.reading_log:
        ap.error("give at least one of --ratings / --reading-log")

    counter: Counter = Counter()
    for label, path in (("ratings", args.ratings), ("reading log", args.reading_log)):
        if path:
            rows = count_works(path, counter)
            print(f"{label}: {rows:,} rows over {len(counter):,} distinct works so far")

    with open(args.out, "w", encoding="utf-8") as f:
        for key, score in counter.most_common():
            f.write(f"{key}\t{score}\n")
    print(f"wrote {len(counter):,} works -> {args.out}")


if __name__ == "__main__":
    main()
