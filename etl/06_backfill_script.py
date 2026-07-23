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

Rows are only rewritten when `to_malayalam_script` returns something — an
English title on a Malayalam work, or a row already in script, is left alone.
Re-running after an --apply is a no-op for the same reason, so it's safe to
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
    from app.services.translit import transliterate
except ImportError as exc:  # pragma: no cover
    print(f"run this with api/.venv/bin/python ({exc})", file=sys.stderr)
    raise SystemExit(1) from exc

LOCAL_URL = "postgresql://postgres:postgres@localhost:55442/kitabi"

# table -> (text column, romanized column)
TABLES = [
    ("works", "title", "title_translit"),
    ("authors", "name", "name_translit"),
    ("publishers", "name", "name_translit"),
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
    conn = await asyncpg.connect(url, timeout=30)
    try:
        total = converted = 0
        for table, text_col, translit_col in TABLES:
            rows = await conn.fetch(
                f"select id, {text_col} as val from {table} where deleted_at is null"
            )
            changes = []
            for r in rows:
                total += 1
                native = to_malayalam_script(r["val"])
                if native and native != r["val"]:
                    changes.append((r["id"], native, transliterate(native)))
            converted += len(changes)
            print(f"\n{table}: {len(changes)} of {len(rows)} rows to convert")
            for _id, native, _t in changes[:5]:
                print(f"    -> {native[:60]}")
            if len(changes) > 5:
                print(f"    … and {len(changes) - 5} more")

            if apply and changes:
                # One statement per row: the values differ per row, and these
                # are hundreds of rows, not millions.
                async with conn.transaction():
                    await conn.executemany(
                        f"update {table} set {text_col}=$2, {translit_col}=$3,"
                        f" updated_at=now() where id=$1",
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
