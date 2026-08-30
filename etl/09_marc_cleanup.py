#!/usr/bin/env python
"""Translate the catalogue's MARC cataloguing punctuation into reader-facing text.

Most of the seed did not come from a bookshop feed. For every Indic language
except Malayalam, OpenLibrary's records originate in US research-library MARC,
so the catalogue displays `"Mukajjiya kanasugaḷu"` with the quotes, `Gandhiji.`
with the terminal period, `Sagar pataal ma safar =` with a parallel-title
marker whose other half was never imported, and `Basheer, Vaikom Muhammad`
filed the way a card catalogue sorts rather than the way a cover reads.

Three stages, so a human sits between the rules and the database — the same
shape as 08_genre_classify, and for the same reason: these are public pages.

  plan    Read works/authors/publishers, run app.services.marc_cleanup over
          every row, write one reviewable JSONL row per proposed change.
          Read-only on the database.
  apply   Write the reviewed plan. Only rows at a risk passed via --risk
          (default `safe`; `review` covers name un-inversion). Idempotent, and
          every write is recorded to a receipt JSONL with its exact before.
  revert  Undo exactly one receipt: restore each `before`, but only where the
          column still holds what we wrote — a later human edit wins.

    cd etl
    ../api/.venv/bin/python 09_marc_cleanup.py plan --out marc_plan.jsonl
    jq -c 'select(.rules == [])'          marc_plan.jsonl   # flagged, never fixed
    jq -c 'select(.risk == "review")'     marc_plan.jsonl   # the un-inversions
    jq -c 'select(.rules != ["nfc"])'     marc_plan.jsonl   # the visible changes
    ../api/.venv/bin/python 09_marc_cleanup.py apply --plan marc_plan.jsonl --production

Run it with the api venv: the rules live in `api/app/services/marc_cleanup.py`
(one source of truth, unit-tested by `api/tests/test_marc_cleanup.py`) and the
search columns are recomputed with the API's own `translit`.

**Recomputing those columns is not optional.** These are raw asyncpg UPDATEs,
so the `before_update` hooks in `app/models/translit_hooks.py` that normally
maintain `title_translit`/`title_fold`/`name_translit`/`name_fold` never fire —
the same trap `06_backfill_script.py` documents. A row written without them
keeps a search key for text it no longer holds.

What this deliberately does NOT do:

  - It never converts romanization to native script. `Mukajjiya kanasugaḷu`
    stays romanized; turning it back into ಮುಕಜ್ಜಿಯ ಕನಸುಗಳು belongs to
    `services/malayalam_script`, which is Malayalam-only by design (see the
    `language != "Malayalam"` gate in 03_transform.py, 29 Jul 2026).
  - It never touches `slug`. A slug is a published URL, assigned once and
    never recomputed (see `Work.slug`) — so cleaning a title does not move
    the page, and `/book/gandhiji-` keeps resolving.
  - It never edits `description`. Half the seeded blurbs are cataloguers'
    notes ("On Assamese philology."), but deciding whether a note should be
    shown as a blurb is a judgement about presentation, not a punctuation
    rule, and this script only does what it can do mechanically.
  - It never merges duplicate rows. `services/merge_service` already proposes
    those, with a review UI in the admin console. Worth running *after* this:
    un-inverting `Basheer, Vaikom Muhammad` turns a word-order match into an
    exact one, which is the class merge_service can apply automatically.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
import urllib.parse
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "api"))

try:
    import asyncpg

    from app.services import marc_cleanup as mc
    from app.services.translit import fold, transliterate
except ImportError as exc:  # pragma: no cover
    print(f"run this with api/.venv/bin/python ({exc})", file=sys.stderr)
    raise SystemExit(1) from exc

LOCAL_HOSTS = {"localhost", "127.0.0.1", "::1"}

# table -> (text columns, romanized column, fold column, source column for both)
TABLES = {
    "works": (("title", "subtitle"), "title_translit", "title_fold", "title"),
    "authors": (("name",), "name_translit", "name_fold", "name"),
    "publishers": (("name",), "name_translit", "name_fold", "name"),
}


# --------------------------------------------------------------------------
# environment
# --------------------------------------------------------------------------


def _env_from_dotenv(name: str) -> str | None:
    path = ROOT / "api" / ".env"
    if not path.exists():
        return None
    for line in path.read_text().splitlines():
        if line.startswith(f"{name}="):
            return line.split("=", 1)[1].strip().strip("\"'")
    return None


def database_url() -> str:
    url = os.environ.get("DATABASE_URL") or _env_from_dotenv("DATABASE_URL")
    if not url:
        sys.exit("DATABASE_URL not set (env or api/.env)")
    return url.replace("postgresql+asyncpg://", "postgresql://")


def guard_production(url: str, allowed: bool) -> None:
    """Two guards, both learned the hard way.

    The first is alembic/env.py's rule (CLAUDE.md, 5 Aug 2026): `api/.env`
    points DATABASE_URL at production, so a bare `apply` would write it
    silently. Writing a non-local host has to be said out loud.

    The second is 06_backfill_script's: Supabase's direct host is IPv6-only
    and *hangs* rather than failing, so a non-local target that isn't the
    Supavisor pooler is almost certainly a mistake about to look like a
    network problem.
    """
    host = urllib.parse.urlsplit(url).hostname or ""
    if host in LOCAL_HOSTS:
        return
    if not allowed:
        sys.exit(
            f"refusing to write non-local database host {host!r} — "
            "pass --production if you really mean it"
        )
    if ":6543/" not in url:
        sys.exit(
            "DATABASE_URL is not the Supavisor pooler (port 6543); the direct host "
            "is IPv6-only and will hang rather than fail. Fix api/.env."
        )


async def connect(url: str):  # noqa: ANN201
    # statement_cache_size=0 is mandatory against the Supavisor transaction
    # pooler: asyncpg names its prepared statements, the pooler hands out a
    # different backend per transaction, and a reused backend already holding
    # that name fails with DuplicatePreparedStatement. Flaky rather than
    # deterministic, so it must be off rather than merely lucky.
    return await asyncpg.connect(url, timeout=30, statement_cache_size=0)


# --------------------------------------------------------------------------
# plan
# --------------------------------------------------------------------------


async def _fetch(conn, table: str) -> list[dict]:  # noqa: ANN001
    if table == "works":
        rows = await conn.fetch(
            """
            SELECT w.id::text AS id, w.title, w.subtitle, w.language,
                   coalesce(array_agg(a.name) FILTER (WHERE a.id IS NOT NULL),
                            '{}') AS author_names
            FROM works w
            LEFT JOIN work_authors wa ON wa.work_id = w.id
            LEFT JOIN authors a ON a.id = wa.author_id AND a.deleted_at IS NULL
            WHERE w.deleted_at IS NULL
            GROUP BY w.id
            ORDER BY w.title
            """
        )
    else:
        rows = await conn.fetch(
            f"SELECT id::text AS id, name, primary_language AS language "  # noqa: S608
            f"FROM {table} WHERE deleted_at IS NULL ORDER BY name"
        )
    return [dict(r) for r in rows]


def _plan_row(table: str, row: dict) -> dict | None:
    """One proposed change, or a flag-only row, or None when there's nothing."""
    if table == "works":
        fix = mc.clean_work(
            row["title"], row["subtitle"], tuple(row["author_names"] or ())
        )
        before = {"title": row["title"], "subtitle": row["subtitle"]}
        after = {"title": fix.title, "subtitle": fix.subtitle}
    else:
        # Only authors are un-inverted: a publisher's comma is a department or
        # an address, never a filing order (see marc_cleanup.clean_name).
        fix = mc.clean_name(row["name"], uninvert=(table == "authors"))
        before = {"name": row["name"]}
        after = {"name": fix.name}

    if not fix.changed and not fix.flags:
        return None
    return {
        "table": table,
        "id": row["id"],
        "risk": fix.risk,
        "rules": fix.rules,
        "flags": fix.flags,
        "before": before,
        "after": after if fix.changed else before,
        "language": row.get("language"),
    }


async def cmd_plan(args: argparse.Namespace) -> None:
    out = Path(args.out)
    if out.exists() and not args.force:
        sys.exit(f"{out} exists — review or delete it first (or pass --force)")

    url = database_url()
    tables = [t.strip() for t in args.tables.split(",") if t.strip() in TABLES]
    conn = await connect(url)
    written = flagged = 0
    try:
        with out.open("w", encoding="utf-8") as sink:
            for table in tables:
                rows = await _fetch(conn, table)
                if args.limit:
                    rows = rows[: args.limit]
                n = f = 0
                for row in rows:
                    plan = _plan_row(table, row)
                    if plan is None:
                        continue
                    sink.write(json.dumps(plan, ensure_ascii=False) + "\n")
                    if plan["rules"]:
                        n += 1
                    else:
                        f += 1
                sink.flush()
                written += n
                flagged += f
                print(f"  {table:<12} {n:>4} changes, {f:>3} flagged-only, of {len(rows)} rows")
    finally:
        await conn.close()
    print(f"\nwrote {written} changes + {flagged} flag-only rows to {out}")
    print("review before applying — the flag-only rows are rows this cannot fix.")


# --------------------------------------------------------------------------
# apply / revert
# --------------------------------------------------------------------------


def read_plan(path: Path, risks: set[str]) -> list[dict]:
    rows = []
    for n, line in enumerate(path.read_text().splitlines(), 1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            sys.exit(f"{path}:{n}: unparseable line")
        if row.get("table") not in TABLES:
            sys.exit(f"{path}:{n}: unknown table {row.get('table')!r}")
        # No rules means the row was flagged for a human, not fixed. Those are
        # never applied, whatever a hand-edit says about their risk.
        if row.get("rules") and row.get("risk") in risks:
            rows.append(row)
    return rows


def _search_columns(table: str, after: dict) -> tuple[str | None, str | None]:
    """The romanized + folded forms for the row's post-fix text."""
    source = after[TABLES[table][3]]
    return transliterate(source), fold(source)


async def _write(conn, table: str, row_id: str, values: dict) -> bool:  # noqa: ANN001
    """Write `values` (text columns) plus the search columns they imply.

    Guarded on the *current* text still being what the plan saw. A plan is a
    snapshot; between planning and applying, someone may have edited the row
    through the admin console or "Improve this entry", and a cleanup must not
    silently overwrite a human.
    """
    cols, translit_col, fold_col, _ = TABLES[table]
    translit, folded = _search_columns(table, values["after"])
    sets = [f"{c} = ${i + 2}" for i, c in enumerate(cols)]
    params = [values["after"][c] for c in cols]
    n = len(cols)
    where = " AND ".join(f"{c} IS NOT DISTINCT FROM ${n + 4 + i}" for i, c in enumerate(cols))
    result = await conn.execute(
        f"UPDATE {table} SET {', '.join(sets)}, "  # noqa: S608
        f"{translit_col} = ${n + 2}, {fold_col} = ${n + 3}, updated_at = now() "
        f"WHERE id = $1 AND deleted_at IS NULL AND {where}",
        uuid.UUID(row_id),
        *params,
        translit,
        folded,
        *[values["expect"][c] for c in cols],
    )
    return result.split()[-1] != "0"


async def cmd_apply(args: argparse.Namespace) -> None:
    url = database_url()
    guard_production(url, args.production)
    risks = {r.strip() for r in args.risk.split(",")} & set(mc.RISKS)
    rows = read_plan(Path(args.plan), risks)
    print(f"{len(rows)} plan rows at risk {sorted(risks)}")
    if not rows:
        return

    receipt = Path(args.receipt)
    conn = await connect(url)
    # Buffered, and written only after the transaction commits: a receipt is a
    # claim about what the database now holds, so it must never describe writes
    # that rolled back.
    done: list[dict] = []
    skipped = 0
    try:
        async with conn.transaction():
            for row in rows:
                ok = await _write(
                    conn,
                    row["table"],
                    row["id"],
                    {"after": row["after"], "expect": row["before"]},
                )
                if not ok:
                    skipped += 1
                    continue
                done.append(
                    {
                        "table": row["table"],
                        "id": row["id"],
                        "rules": row["rules"],
                        "before": row["before"],
                        "after": row["after"],
                    }
                )
    finally:
        await conn.close()

    with receipt.open("a", encoding="utf-8") as sink:
        for entry in done:
            sink.write(json.dumps(entry, ensure_ascii=False) + "\n")
    print(
        f"applied {len(done)}, skipped {skipped} (row changed since the plan) "
        f"— receipt: {receipt}"
    )


async def cmd_revert(args: argparse.Namespace) -> None:
    url = database_url()
    guard_production(url, args.production)
    receipt = Path(args.receipt)
    conn = await connect(url)
    reverted = kept = 0
    try:
        async with conn.transaction():
            for line in receipt.read_text().splitlines():
                if not line.strip():
                    continue
                row = json.loads(line)
                # Only if the column still holds what we wrote — a later human
                # edit wins, the same rule 08_genre_classify's revert follows.
                ok = await _write(
                    conn,
                    row["table"],
                    row["id"],
                    {"after": row["before"], "expect": row["after"]},
                )
                reverted += ok
                kept += not ok
    finally:
        await conn.close()
    print(f"reverted {reverted}, left {kept} alone (edited since) from {receipt}")


# --------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("plan", help="propose changes into a reviewable JSONL (DB read-only)")
    p.add_argument("--out", default="marc_plan.jsonl")
    p.add_argument("--tables", default="works,authors,publishers")
    p.add_argument("--limit", type=int, default=0, help="smoke-test on the first N rows per table")
    p.add_argument("--force", action="store_true", help="overwrite an existing plan file")

    a = sub.add_parser("apply", help="write a reviewed plan to the database")
    a.add_argument("--plan", default="marc_plan.jsonl")
    a.add_argument("--receipt", default="marc_receipt.jsonl")
    a.add_argument("--risk", default=mc.SAFE, help=f"comma-separated, of {','.join(mc.RISKS)}")
    a.add_argument("--production", action="store_true")

    r = sub.add_parser("revert", help="undo exactly what one receipt file recorded")
    r.add_argument("--receipt", default="marc_receipt.jsonl")
    r.add_argument("--production", action="store_true")

    args = parser.parse_args()
    asyncio.run({"plan": cmd_plan, "apply": cmd_apply, "revert": cmd_revert}[args.cmd](args))


if __name__ == "__main__":
    main()
