"""Pre-launch wipe: remove every reader account and all personal (Layer 2) data,
keep the whole shared catalog (Layer 1).

Kept: works, editions, authors, publishers, series, genres and their join tables
(`work_authors`, `work_genres`, `work_translators`), plus the admin console's own
accounts. Removed: profiles, library entries, ratings, reviews, notes, reading
sessions, lending records, tags, activity log, sync bookkeeping, device tokens,
LLM quota counters and promotion impression logs. Catalog columns that point at a
reader (`works.created_by_user_id`, `authors.created_by_user_id`,
`authors.linked_user_id`) are set NULL, and `works.aggregate_rating` — which is
derived from reader ratings — is cleared so no book carries a score no rating
supports.

This is a HARD delete, deliberately: CLAUDE.md rule 3 ("soft deletes only") is
about how the running app treats a reader's data, not about scrubbing test data
before launch. A soft delete here would leave every test row sitting in the
database and still flowing down `/sync/pull`.

    # what would happen (default — touches nothing)
    DATABASE_URL=... .venv/bin/python scripts/reset_user_data.py

    # do it
    DATABASE_URL=... .venv/bin/python scripts/reset_user_data.py \
        --apply --confirm-host aws-1-ap-southeast-1.pooler.supabase.com

`--confirm-host` must match the host in DATABASE_URL: the URL usually comes from
an env file, so the host is the one thing you have to type deliberately, and it
is what stops this from running against a database you did not mean.

Deleting the Supabase Auth accounts themselves is a separate step — they live in
`auth.users`, which the application role cannot touch. Run
`scripts/delete_auth_users.py` (needs SUPABASE_SERVICE_ROLE_KEY) after this.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
import uuid
from datetime import date
from decimal import Decimal
from pathlib import Path
from urllib.parse import urlsplit

from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app.core.db import _engine_kwargs, _normalize  # noqa: E402

# Ordered so a child is gone before its parent — these are real FKs, not a
# convention. Everything here is reader-owned and goes entirely.
USER_TABLES: tuple[str, ...] = (
    "library_entry_tags",  # → library_entries, personal_tags
    "active_reading_sessions",  # the live sitting; one row per reader
    "reading_notes",  # → library_entries, reading_sessions
    "reading_sessions",  # → library_entries
    "lending_records",  # → library_entries, editions
    "personal_tags",
    "library_entries",  # → editions (kept)
    "ratings",  # → works (kept)
    "reviews",  # → works (kept)
    "activity_log_entries",
    "conflict_history",
    "sync_ops",
    "device_tokens",
    "connections",
    "content_reports",
    "author_claims",  # → authors (kept)
    "work_revisions",  # → works (kept)
    "llm_usage",
    "promotion_events",  # reader impressions/clicks; the campaign itself stays
    "profiles",
)

# Reader references and reader-derived values living on catalog rows. The row
# survives; the column loses the pointer to an account that no longer exists.
CATALOG_SCRUBS: tuple[tuple[str, str], ...] = (
    ("works", "created_by_user_id = NULL"),
    ("works", "aggregate_rating = NULL"),
    ("authors", "created_by_user_id = NULL"),
    ("authors", "linked_user_id = NULL"),
)

# Never touched by default. The catalog is the point of keeping the database at
# all, and the admin_* tables are the owner's own console login.
KEPT_TABLES: tuple[str, ...] = (
    "works",
    "editions",
    "authors",
    "publishers",
    "series",
    "genres",
    "work_authors",
    "work_genres",
    "work_translators",
    "merge_dismissals",
    "admin_users",
    "admin_recovery_codes",
    "admin_auth_tokens",
    "admin_audit_log",
    "admin_sessions",
    "promotions",
    "promotion_contents",
    "alembic_version",
)

# Opt-in extras — not reader data, but plausibly test leftovers.
OPTIONAL: dict[str, tuple[str, ...]] = {
    "drop-promotions": ("promotion_contents", "promotions"),
    "reset-admin-sessions": ("admin_sessions",),
}


async def counts(conn, tables) -> dict[str, int]:
    out = {}
    for t in tables:
        out[t] = (await conn.execute(text(f'select count(*) from "{t}"'))).scalar_one()
    return out


def _jsonable(v):
    if isinstance(v, uuid.UUID):
        return str(v)
    if isinstance(v, date):  # datetime subclasses date, so this covers both
        return v.isoformat()
    if isinstance(v, Decimal):
        return float(v)
    return v


async def snapshot(conn, targets: list[str]) -> dict:
    """Every row about to be deleted, plus the pre-scrub value of every catalog
    column about to be nulled — the undo record for this exact run.

    Written before the delete, in the same invocation, because the alternative
    (remember to take a dump first) is the step that gets skipped. It is not a
    substitute for a real `pg_dump`: it covers only what this script changes.
    """
    out: dict = {"tables": {}, "scrubs": {}}
    for t in targets:
        rows = (await conn.execute(text(f'select * from "{t}"'))).mappings().all()
        out["tables"][t] = [{k: _jsonable(v) for k, v in r.items()} for r in rows]
    for tbl, assign in CATALOG_SCRUBS:
        col = assign.split(" =")[0]
        rows = (
            (await conn.execute(text(f"select id, {col} from {tbl} where {col} is not null")))
            .mappings()
            .all()
        )
        out["scrubs"][f"{tbl}.{col}"] = [{k: _jsonable(v) for k, v in r.items()} for r in rows]
    return out


async def run_wipe(conn, targets: list[str]) -> dict[str, int]:
    """Delete every reader row and scrub the reader references off catalog rows.

    Caller owns the transaction — `main` wraps this in one so the wipe is all or
    nothing, and the test calls it inside the test session's transaction.
    """
    done: dict[str, int] = {}
    for t in targets:
        done[t] = (await conn.execute(text(f'delete from "{t}"'))).rowcount
    for tbl, assign in CATALOG_SCRUBS:
        col = assign.split(" =")[0]
        done[f"{tbl}.{col}"] = (
            await conn.execute(text(f"update {tbl} set {assign} where {col} is not null"))
        ).rowcount
    return done


async def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--apply", action="store_true", help="actually delete (default: dry run)")
    p.add_argument("--confirm-host", default="", help="must match the host in DATABASE_URL")
    p.add_argument(
        "--drop-promotions",
        action="store_true",
        help="also delete promotion campaigns and their content (test campaigns)",
    )
    p.add_argument(
        "--reset-admin-sessions",
        action="store_true",
        help="also sign every admin console session out",
    )
    p.add_argument(
        "--snapshot",
        metavar="PATH",
        help="write the deleted rows to this JSON file first (required with --apply)",
    )
    args = p.parse_args()

    raw = os.environ.get("DATABASE_URL", "")
    if not raw:
        print("DATABASE_URL is not set.", file=sys.stderr)
        return 2
    url = _normalize(raw)
    host = urlsplit(url).hostname or "?"

    targets = list(USER_TABLES)
    if args.drop_promotions:
        targets += list(OPTIONAL["drop-promotions"])
    if args.reset_admin_sessions:
        targets += list(OPTIONAL["reset-admin-sessions"])

    # An opt-in flag moves a table out of "kept" and into "deleted". Counting it
    # as both makes the final check report the deletion you asked for as damage.
    kept = [t for t in KEPT_TABLES if t not in targets]

    print(f"database host : {host}")
    print(f"mode          : {'APPLY — deletes rows' if args.apply else 'dry run'}\n")

    if args.apply and not args.snapshot:
        print(
            "Refusing to run: --apply needs --snapshot PATH. This delete cannot be "
            "undone from the database itself, so it writes its own undo record first.",
            file=sys.stderr,
        )
        return 2

    if args.apply and args.confirm_host.strip() != host:
        print(
            f"Refusing to run: --confirm-host {args.confirm_host!r} does not match {host!r}.",
            file=sys.stderr,
        )
        return 2

    eng = create_async_engine(url, **_engine_kwargs(url))
    try:
        async with eng.connect() as conn:
            before_del = await counts(conn, targets)
            before_keep = await counts(conn, kept)

            print("to be DELETED:")
            for t in targets:
                print(f"  {before_del[t]:>8}  {t}")
            print(f"  {sum(before_del.values()):>8}  TOTAL rows\n")

            print("to be KEPT:")
            for t in kept:
                print(f"  {before_keep[t]:>8}  {t}")
            print()

            print("catalog columns to scrub:")
            for tbl, assign in CATALOG_SCRUBS:
                col = assign.split(" =")[0]
                n = (
                    await conn.execute(text(f"select count(*) from {tbl} where {col} is not null"))
                ).scalar_one()
                print(f"  {n:>8}  {tbl}.{col}")
            print()

            if not args.apply:
                print("Dry run — nothing was changed. Re-run with --apply --confirm-host to do it.")
                return 0

            snap = await snapshot(conn, targets)
            # Blocking write in an async function on purpose: this is a one-shot
            # CLI, and the snapshot must be on disk before the delete begins.
            Path(args.snapshot).write_text(
                json.dumps(snap, indent=1, ensure_ascii=False), encoding="utf-8"
            )
            n_rows = sum(len(v) for v in snap["tables"].values())
            n_scrub = sum(len(v) for v in snap["scrubs"].values())
            print(f"snapshot: {n_rows} rows + {n_scrub} column values -> {args.snapshot}\n")

            # The counting and snapshot SELECTs above autobegan a transaction on
            # this connection; `begin()` refuses to nest, so close that one out
            # first. Without this the wipe dies here having written a snapshot
            # and deleted nothing — safe, but it looks like it worked.
            await conn.rollback()

            # One transaction: either the whole wipe lands or none of it does.
            async with conn.begin():
                for what, n in (await run_wipe(conn, targets)).items():
                    print(f"  {n:>8}  {what}")

            after_del = await counts(conn, targets)
            after_keep = await counts(conn, kept)
            leftover = {t: n for t, n in after_del.items() if n}
            changed = {
                t: (before_keep[t], after_keep[t]) for t in kept if before_keep[t] != after_keep[t]
            }

            print("\nverification:")
            print(
                f"  reader rows remaining : {sum(after_del.values())}"
                + (f"  {leftover}" if leftover else "")
            )
            print(f"  catalog rows changed  : {changed or 'none'}")
            return 0 if not leftover and not changed else 1
    finally:
        await eng.dispose()


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
