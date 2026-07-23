"""Convert already-loaded ALA-LC romanized rows to Malayalam script.

The first production seed landed before the transform learned to convert, so
its works/authors/publishers carry titles like `Kēraḷa sthalanāmakōśaṃ`. This
rewrites those in place — and recomputes the romanized search column from the
native script, which is a raw UPDATE and therefore bypasses the ORM hooks that
normally maintain it.

Dry run by default: prints every change it would make and touches nothing.

    python 06_backfill_script.py                 # preview
    python 06_backfill_script.py --apply         # write
    python 06_backfill_script.py --local         # target the dev DB instead

A row is rewritten when its text converts, or when only its romanized search
key is stale — so this also refreshes rows an earlier run already converted
after the romanization rules improve. An English title on a Malayalam work is
left alone. Re-running once everything is current is a no-op, so it's safe to
repeat.
"""

from __future__ import annotations

import argparse
import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "api"))

try:
    import asyncpg

    from app.services.malayalam_script import to_malayalam_script
    from app.services.translit import fold, transliterate
except ImportError as exc:  # pragma: no cover
    print(f"run this with api/.venv/bin/python ({exc})", file=sys.stderr)
    raise SystemExit(1) from exc

LOCAL_URL = "postgresql://postgres:postgres@localhost:55442/kitabi"

# table -> (text column, romanized column, spelling-fold column)
TABLES = [
    ("works", "title", "title_translit", "title_fold"),
    ("authors", "name", "name_translit", "name_fold"),
    ("publishers", "name", "name_translit", "name_fold"),
]


def _prod_url() -> str:
    env = Path(__file__).resolve().parents[1] / "api" / ".env"
    if not env.exists():
        raise SystemExit(f"no {env} — cannot resolve the prod URL")
    for line in env.read_text().splitlines():
        if line.startswith("DATABASE_URL="):
            url = line.split("=", 1)[1].strip().strip("\"'").replace("+asyncpg", "")
            if ":6543/" not in url:
                raise SystemExit(
                    "DATABASE_URL is not the Supavisor pooler (port 6543); the direct "
                    "host is IPv6-only and will hang. Fix api/.env."
                )
            return url
    raise SystemExit("DATABASE_URL not found in api/.env")


async def run(url: str, apply: bool) -> None:
    # statement_cache_size=0 is mandatory against the Supavisor transaction
    # pooler: asyncpg names its prepared statements (__asyncpg_stmt_1__), the
    # pooler hands out a different backend per transaction, and a reused
    # backend already holding that name fails with DuplicatePreparedStatement.
    # It is flaky rather than deterministic — a run can succeed and the next
    # one blow up on the first fetch — so it must be off, not merely lucky.
    conn = await asyncpg.connect(url, timeout=30, statement_cache_size=0)
    try:
        total = converted = 0
        for table, text_col, translit_col, fold_col in TABLES:
            rows = await conn.fetch(
                f"select id, {text_col} as val, {translit_col} as tr, {fold_col} as fl"
                f" from {table} where deleted_at is null"
            )
            changes = []
            for r in rows:
                total += 1
                native = to_malayalam_script(r["val"]) or r["val"]
                romanized = transliterate(native)
                folded = fold(native)
                # Rewrite when the text changes OR when only the search key is
                # stale — a row converted by an earlier run still needs its
                # translit refreshed when the romanization rules improve
                # (the ee/oo long vowels, the nasal tildes), and for those
                # rows to_malayalam_script now correctly returns None.
                if native != r["val"] or romanized != r["tr"] or folded != r["fl"]:
                    changes.append((r["id"], native, romanized, folded))
            converted += len(changes)
            print(f"\n{table}: {len(changes)} of {len(rows)} rows to convert")
            for _id, native, *_rest in changes[:5]:
                print(f"    -> {native[:60]}")
            if len(changes) > 5:
                print(f"    … and {len(changes) - 5} more")

            if apply and changes:
                # One statement per row: the values differ per row, and these
                # are hundreds of rows, not millions.
                async with conn.transaction():
                    await conn.executemany(
                        f"update {table} set {text_col}=$2, {translit_col}=$3,"
                        f" {fold_col}=$4, updated_at=now() where id=$1",
                        changes,
                    )
                print(f"    applied {len(changes)}")

        print(f"\n{converted} of {total} catalog rows {'updated' if apply else 'would change'}")
        if not apply:
            print("dry run — nothing written. Re-run with --apply to commit.")
    finally:
        await conn.close()


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--apply", action="store_true", help="write the changes (default: preview)")
    ap.add_argument("--local", action="store_true", help="target the dev DB on 55442")
    args = ap.parse_args()

    url = LOCAL_URL if args.local else _prod_url()
    where = "LOCAL dev" if args.local else "PRODUCTION"
    print(f"target: {where}\nmode:   {'APPLY' if args.apply else 'dry run'}")
    asyncio.run(run(url, args.apply))


if __name__ == "__main__":
    main()
