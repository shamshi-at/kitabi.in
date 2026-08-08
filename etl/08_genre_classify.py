#!/usr/bin/env python
"""Classify the catalogue's works into the closed genre vocabulary (W5).

Three explicit stages, so a human sits between the model and the database:

  plan    Read works (id/title/authors/language/year/form/description), batch
          them to Claude, write one JSONL row per work to the plan file.
          Read-only on the database. Resumable: works already in the plan file
          are skipped, so a killed run continues where it stopped.
  apply   Read the (reviewed) plan file and write genres + missing forms to
          the database. Only vocabulary names; only confidences passed via
          --confidence (default high,medium). Idempotent — existing links are
          skipped — and every write is recorded to a receipt JSONL.
  revert  Undo exactly one receipt file: delete exactly the links it created
          and null exactly the forms it set (only if still unchanged). A bad
          batch is one command away from gone — genre hubs are indexed pages,
          so a wrong classification is public; reversibility is the safety.

Run with the api venv (this script imports the API's models and vocabulary —
one source of truth, no drifting copy):

    cd etl
    ../api/.venv/bin/python 08_genre_classify.py plan --out genre_plan.jsonl
    # review the plan (spot-check; `jq 'select(.confidence=="low")'` etc.)
    ../api/.venv/bin/python 08_genre_classify.py apply --plan genre_plan.jsonl

DATABASE_URL comes from the environment, else api/.env. Like alembic/env.py
(CLAUDE.md: the 5 Aug lesson), a NON-LOCAL database is refused unless
--production is passed — api/.env points at the Supabase pooler, so a bare
`apply` would otherwise write production by default, silently.

The Anthropic call: claude-sonnet-5 (recognising Malayalam novels through
ITRANS romanization needs the world knowledge; the whole catalogue costs well
under a dollar), thinking disabled (classification is recall, not reasoning —
and max_tokens caps thinking + prose together, the 26 Jul lesson), key from
ANTHROPIC_API_KEY else api/.env. One-off owner-run script, not an endpoint, so
the llm_quota metering rule for public endpoints doesn't apply.
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

import httpx

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "api"))

from app.services.anthropic_client import ANTHROPIC_URL, ANTHROPIC_VERSION  # noqa: E402
from app.services.genre_vocab import (  # noqa: E402
    CONFIDENCES,
    GENRES,
    classification_prompt,
    parse_classification,
)

MODEL = os.environ.get("GENRE_MODEL", "claude-sonnet-5")
BATCH = 20
MAX_DESC = 300


# --------------------------------------------------------------------------
# Environment
# --------------------------------------------------------------------------


def _env_from_dotenv(name: str) -> str | None:
    path = ROOT / "api" / ".env"
    if not path.exists():
        return None
    for line in path.read_text().splitlines():
        if line.startswith(f"{name}="):
            return line.split("=", 1)[1].strip()
    return None


def database_url() -> str:
    url = os.environ.get("DATABASE_URL") or _env_from_dotenv("DATABASE_URL")
    if not url:
        sys.exit("DATABASE_URL not set (env or api/.env)")
    return url.replace("postgresql+asyncpg://", "postgresql://")


def api_key() -> str:
    key = os.environ.get("ANTHROPIC_API_KEY") or _env_from_dotenv("ANTHROPIC_API_KEY")
    if not key:
        sys.exit("ANTHROPIC_API_KEY not set (env or api/.env)")
    return key


def guard_production(url: str, allowed: bool) -> None:
    """Same rule as alembic/env.py: writing a non-local host must be said out
    loud. A note in a docstring stops nobody; a process that exits does."""
    host = urllib.parse.urlsplit(url).hostname or ""
    local = host in {"localhost", "127.0.0.1", "::1"}
    if not local and not allowed:
        sys.exit(
            f"refusing to write non-local database host {host!r} — "
            "pass --production if you really mean it"
        )


# --------------------------------------------------------------------------
# plan
# --------------------------------------------------------------------------


async def fetch_works(url: str) -> list[dict]:
    import asyncpg

    conn = await asyncpg.connect(url, statement_cache_size=0)
    try:
        rows = await conn.fetch(
            """
            SELECT w.id::text AS id, w.title, w.language, w.form,
                   w.first_publish_year AS year,
                   left(coalesce(w.description, ''), $1) AS description,
                   coalesce(string_agg(a.name, '; ' ORDER BY a.name), '') AS authors
            FROM works w
            LEFT JOIN work_authors wa ON wa.work_id = w.id
            LEFT JOIN authors a ON a.id = wa.author_id AND a.deleted_at IS NULL
            WHERE w.deleted_at IS NULL
            GROUP BY w.id
            ORDER BY w.title
            """,
            MAX_DESC,
        )
    finally:
        await conn.close()
    return [dict(r) for r in rows]


async def ask_claude(client: httpx.AsyncClient, key: str, works: list[dict]) -> str:
    resp = await client.post(
        ANTHROPIC_URL,
        headers={
            "x-api-key": key,
            "anthropic-version": ANTHROPIC_VERSION,
            "content-type": "application/json",
        },
        json={
            "model": MODEL,
            "max_tokens": 4096,
            "thinking": {"type": "disabled"},
            "system": (
                "You are a careful literary cataloguer with deep knowledge of South Asian "
                "literature in every major Indian language, and of world literature. "
                "You never invent a classification you cannot stand behind: an honest "
                "'unknown' is worth more than a plausible guess, because your answers "
                "become public browse pages."
            ),
            "messages": [{"role": "user", "content": classification_prompt(works)}],
        },
    )
    resp.raise_for_status()
    payload = resp.json()
    for block in payload.get("content", []):
        if isinstance(block, dict) and block.get("type") == "text":
            return block.get("text") or ""
    return ""


async def cmd_plan(args: argparse.Namespace) -> None:
    out = Path(args.out)
    done: set[str] = set()
    if out.exists():
        for line in out.read_text().splitlines():
            try:
                done.add(json.loads(line)["id"])
            except (json.JSONDecodeError, KeyError):
                pass

    works = [w for w in await fetch_works(database_url()) if w["id"] not in done]
    if args.limit:
        works = works[: args.limit]
    print(f"{len(works)} works to classify ({len(done)} already in {out})")
    if not works:
        return

    key = api_key()
    written = failures = 0
    async with httpx.AsyncClient(timeout=120.0) as client:
        # Blocking append on purpose (noqa ASYNC230): this CLI is strictly
        # sequential, and flushing each batch to disk before the next call is
        # what makes a killed run resumable.
        with out.open("a", encoding="utf-8") as sink:  # noqa: ASYNC230
            for i in range(0, len(works), BATCH):
                batch = works[i : i + BATCH]
                expected = {w["id"] for w in batch}
                rows: list[dict] = []
                problems: list[str] = []
                for attempt in (1, 2):
                    try:
                        raw = await ask_claude(client, key, batch)
                    except httpx.HTTPError as exc:
                        problems = [f"http error: {exc}"]
                        await asyncio.sleep(2 * attempt)
                        continue
                    rows, problems = parse_classification(raw, expected)
                    if rows:
                        break
                by_id = {r["id"]: r for r in rows}
                for w in batch:
                    row = by_id.get(
                        w["id"],
                        {
                            "id": w["id"],
                            "genres": [],
                            "form": None,
                            "confidence": "unknown",
                        },
                    )
                    row["title"] = w["title"]
                    row["authors"] = w["authors"]
                    row["language"] = w["language"]
                    sink.write(json.dumps(row, ensure_ascii=False) + "\n")
                    written += 1
                sink.flush()
                failures += len(problems)
                for p in problems:
                    print(f"  ! {p}", file=sys.stderr)
                print(f"  batch {i // BATCH + 1}: {len(rows)}/{len(batch)} classified")

    print(f"wrote {written} rows to {out} ({failures} problems — see stderr)")


# --------------------------------------------------------------------------
# apply / revert
# --------------------------------------------------------------------------


def read_plan(path: Path, confidences: set[str]) -> list[dict]:
    rows = []
    for n, line in enumerate(path.read_text().splitlines(), 1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            sys.exit(f"{path}:{n}: unparseable line")
        if row.get("confidence") in confidences and (
            row.get("genres") or row.get("form")
        ):
            rows.append(row)
    return rows


async def cmd_apply(args: argparse.Namespace) -> None:
    import asyncpg

    url = database_url()
    guard_production(url, args.production)
    confidences = {c.strip() for c in args.confidence.split(",")} & set(CONFIDENCES)
    rows = read_plan(Path(args.plan), confidences)
    print(f"{len(rows)} plan rows at confidence {sorted(confidences)}")

    receipt = Path(args.receipt)
    conn = await asyncpg.connect(url, statement_cache_size=0)
    linked = formed = 0
    try:
        # The closed vocabulary get-or-create, once up front. Genre names are
        # UNIQUE; ON CONFLICT keeps a concurrent add from crashing the run.
        genre_ids: dict[str, str] = {}
        for name in GENRES:
            gid = await conn.fetchval(
                """
                INSERT INTO genres (id, name, created_at, updated_at)
                VALUES ($1, $2, now(), now())
                ON CONFLICT (name) DO UPDATE SET updated_at = genres.updated_at
                RETURNING id::text
                """,
                uuid.uuid4(),
                name,
            )
            genre_ids[name] = gid

        with receipt.open("a", encoding="utf-8") as sink:
            for row in rows:
                work_id = row["id"]
                added: list[str] = []
                for name in row.get("genres") or []:
                    gid = genre_ids.get(name)
                    if gid is None:
                        continue  # non-vocabulary name in a hand-edited plan
                    inserted = await conn.fetchval(
                        """
                        INSERT INTO work_genres (work_id, genre_id)
                        SELECT $1, $2
                        WHERE EXISTS (SELECT 1 FROM works WHERE id = $1 AND deleted_at IS NULL)
                        ON CONFLICT DO NOTHING
                        RETURNING genre_id::text
                        """,
                        uuid.UUID(work_id),
                        uuid.UUID(gid),
                    )
                    if inserted:
                        added.append(name)
                        linked += 1

                form_set = None
                if row.get("form"):
                    updated = await conn.fetchval(
                        """
                        UPDATE works SET form = $2, updated_at = now()
                        WHERE id = $1 AND form IS NULL AND deleted_at IS NULL
                        RETURNING id
                        """,
                        uuid.UUID(work_id),
                        row["form"],
                    )
                    if updated:
                        form_set = row["form"]
                        formed += 1

                if added or form_set:
                    sink.write(
                        json.dumps(
                            {
                                "id": work_id,
                                "genres_added": added,
                                "form_set": form_set,
                            },
                            ensure_ascii=False,
                        )
                        + "\n"
                    )
    finally:
        await conn.close()
    print(f"linked {linked} genres, set {formed} forms — receipt: {receipt}")


async def cmd_revert(args: argparse.Namespace) -> None:
    import asyncpg

    url = database_url()
    guard_production(url, args.production)
    receipt = Path(args.receipt)
    unlinked = unformed = 0
    conn = await asyncpg.connect(url, statement_cache_size=0)
    try:
        for line in receipt.read_text().splitlines():
            if not line.strip():
                continue
            row = json.loads(line)
            for name in row.get("genres_added") or []:
                n = await conn.execute(
                    """
                    DELETE FROM work_genres
                    WHERE work_id = $1
                      AND genre_id = (SELECT id FROM genres WHERE name = $2)
                    """,
                    uuid.UUID(row["id"]),
                    name,
                )
                unlinked += int(n.split()[-1])
            if row.get("form_set"):
                # Only if still what we wrote — a later human edit wins.
                n = await conn.execute(
                    "UPDATE works SET form = NULL, updated_at = now() "
                    "WHERE id = $1 AND form = $2",
                    uuid.UUID(row["id"]),
                    row["form_set"],
                )
                unformed += int(n.split()[-1])
    finally:
        await conn.close()
    print(f"reverted {unlinked} genre links, {unformed} forms from {receipt}")


# --------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser(
        "plan", help="classify works into a reviewable JSONL (DB read-only)"
    )
    p.add_argument("--out", default="genre_plan.jsonl")
    p.add_argument(
        "--limit", type=int, default=0, help="smoke-test on the first N works only"
    )

    a = sub.add_parser("apply", help="write a reviewed plan to the database")
    a.add_argument("--plan", default="genre_plan.jsonl")
    a.add_argument("--receipt", default="genre_receipt.jsonl")
    a.add_argument("--confidence", default="high,medium")
    a.add_argument("--production", action="store_true")

    r = sub.add_parser("revert", help="undo exactly what one receipt file recorded")
    r.add_argument("--receipt", default="genre_receipt.jsonl")
    r.add_argument("--production", action="store_true")

    args = parser.parse_args()
    asyncio.run(
        {"plan": cmd_plan, "apply": cmd_apply, "revert": cmd_revert}[args.cmd](args)
    )


if __name__ == "__main__":
    main()
