#!/usr/bin/env python
"""Give a Library-of-Congress-romanized work the title people actually read.

09_marc_cleanup fixed the punctuation; this fixes the *words*. The catalogue's
Indic-language records are ALA-LC romanizations, which leaves three states
needing three different answers — see `api/app/services/title_restore.py`:

    Ardhi rate azadi            [Gujarati, Collins & Lapierre]
        -> આઝાદી અડધી રાતે                a native title, romanized
    3 misṭeka ôpha māya lāipha  [Gujarati, Chetan Bhagat]
        -> The 3 Mistakes of My Life    an ENGLISH title, transliterated twice
    The Secret                  [Gujarati, Rhonda Byrne]
        -> unchanged                    already right

Owner decision, 31 Aug 2026: **native title where the edition really has one,
the English title where the edition only transliterated it.** That is a
per-book judgement — it needs to know that Bhagat writes in English — so a
model proposes and a human confirms, exactly like 08_genre_classify.

  plan    Read the romanized works, batch them to Claude, write one reviewable
          JSONL row each. Read-only on the database. Resumable.
  apply   Write the reviewed plan. Only kinds `native`/`english`, only at a
          confidence passed via --confidence (default high). Receipt per write.
  revert  Restore exactly what one receipt recorded, where the column still
          holds what we wrote.

    cd etl
    ../api/.venv/bin/python 10_title_restore.py plan --out runs/<date>/titles.jsonl
    jq -c 'select(.kind=="english")'                 titles.jsonl
    jq -c 'select(.confidence!="high")'              titles.jsonl
    ../api/.venv/bin/python 10_title_restore.py apply --plan titles.jsonl --production

Two guards do the work a reviewer cannot do by eye, both in title_restore:
a `native` answer must be IN that language's script, and an `english` answer
must carry no non-Latin character. That is what makes a wrong-script or
still-romanized answer a rejected row rather than something you have to spot —
and it is exactly the failure that sank the mechanical sanscript conversion
(Devanagari vowels inside Gujarati, raw Latin left in Gurmukhi).

Never touches `slug`: a slug is a published URL, assigned once and never
recomputed, so retitling does not move the page. Recomputes
`title_translit`/`title_fold` itself, because a raw UPDATE bypasses the ORM
hooks that normally maintain them.
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

try:
    import asyncpg

    from app.services.anthropic_client import ANTHROPIC_URL, ANTHROPIC_VERSION, reply_text
    from app.services.title_restore import (
        CONFIDENCES,
        ENGLISH,
        NATIVE,
        SCRIPT_RANGES,
        parse_restoration,
        restoration_prompt,
        tally_votes,
    )
    from app.services.translit import fold, transliterate
except ImportError as exc:  # pragma: no cover
    print(f"run this with api/.venv/bin/python ({exc})", file=sys.stderr)
    raise SystemExit(1) from exc

MODEL = os.environ.get("TITLE_MODEL", "claude-sonnet-5")
BATCH = 15
LOCAL_HOSTS = {"localhost", "127.0.0.1", "::1"}


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


def api_key() -> str:
    key = os.environ.get("ANTHROPIC_API_KEY") or _env_from_dotenv("ANTHROPIC_API_KEY")
    if not key:
        sys.exit("ANTHROPIC_API_KEY not set (env or api/.env)")
    return key


def guard_production(url: str, allowed: bool) -> None:
    """alembic/env.py's rule, plus 06_backfill's: api/.env points at production,
    so writing a non-local host must be said out loud — and a non-pooler
    Supabase host is IPv6-only and hangs rather than failing."""
    host = urllib.parse.urlsplit(url).hostname or ""
    if host in LOCAL_HOSTS:
        return
    if not allowed:
        sys.exit(
            f"refusing to write non-local database host {host!r} — "
            "pass --production if you really mean it"
        )
    if ":6543/" not in url:
        sys.exit("DATABASE_URL is not the Supavisor pooler (port 6543); it will hang.")


async def connect(url: str):  # noqa: ANN201
    # statement_cache_size=0 is mandatory against the Supavisor pooler.
    return await asyncpg.connect(url, timeout=30, statement_cache_size=0)


# --------------------------------------------------------------------------
# plan
# --------------------------------------------------------------------------


async def fetch_candidates(url: str) -> list[dict]:
    """Works in an Indic language whose title carries no character of that
    language's script — i.e. every row the romanization actually affects. A
    work already in its own script needs no opinion from anybody."""
    conn = await connect(url)
    try:
        rows = await conn.fetch(
            """
            SELECT w.id::text AS id, w.title, w.subtitle, w.language,
                   w.first_publish_year AS year,
                   left(coalesce(w.description, ''), 400) AS description,
                   coalesce(string_agg(DISTINCT a.name, '; '), '') AS authors,
                   (SELECT e.isbn FROM editions e
                     WHERE e.work_id = w.id AND e.deleted_at IS NULL AND e.isbn IS NOT NULL
                     LIMIT 1) AS isbn,
                   (SELECT p.name FROM editions e JOIN publishers p ON p.id = e.publisher_id
                     WHERE e.work_id = w.id AND e.deleted_at IS NULL LIMIT 1) AS publisher
            FROM works w
            LEFT JOIN work_authors wa ON wa.work_id = w.id
            LEFT JOIN authors a ON a.id = wa.author_id AND a.deleted_at IS NULL
            WHERE w.deleted_at IS NULL AND w.language = ANY($1::text[])
            GROUP BY w.id
            ORDER BY w.title
            """,
            list(SCRIPT_RANGES),
        )
    finally:
        await conn.close()

    out = []
    for r in rows:
        lo, hi = SCRIPT_RANGES[r["language"]]
        if any(lo <= ord(c) <= hi for c in r["title"]):
            continue  # already in its own script
        out.append(dict(r))
    return out


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
            # Thinking disabled: this is recall, not reasoning, and max_tokens
            # caps thinking and prose together (the 26 Jul lesson).
            "thinking": {"type": "disabled"},
            "system": (
                "You are a careful bibliographer with deep knowledge of South Asian "
                "publishing in every major Indian language, and of which books are "
                "translations from English. You know what a book is actually CALLED "
                "on its cover. You never invent a title you cannot stand behind: an "
                "honest 'unknown' is worth more than a plausible guess, because your "
                "answers become public pages."
            ),
            "messages": [{"role": "user", "content": restoration_prompt(works)}],
        },
    )
    resp.raise_for_status()
    return reply_text(resp.json())


async def _one_vote(
    client: httpx.AsyncClient, key: str, batch: list[dict], expected: dict[str, str | None]
) -> tuple[list[dict], list[str]]:
    """One independent sample of one batch, retried once on a transport error."""
    for attempt in (1, 2):
        try:
            raw = await ask_claude(client, key, batch)
        except httpx.HTTPError as exc:
            if attempt == 2:
                return [], [f"http error: {exc}"]
            await asyncio.sleep(3 * attempt)
            continue
        return parse_restoration(raw, expected)
    return [], []


async def cmd_plan(args: argparse.Namespace) -> None:
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    done: set[str] = set()
    if out.exists():
        for line in out.read_text().splitlines():
            try:
                done.add(json.loads(line)["id"])
            except (json.JSONDecodeError, KeyError):
                pass

    works = [w for w in await fetch_candidates(database_url()) if w["id"] not in done]
    if args.limit:
        works = works[: args.limit]
    print(f"{len(works)} romanized works to identify ({len(done)} already in {out})")
    if not works:
        return

    key = api_key()
    written = failures = 0
    async with httpx.AsyncClient(timeout=180.0) as client:
        # Blocking append on purpose (noqa ASYNC230): strictly sequential, and
        # flushing each batch before the next call is what makes a killed run
        # resumable.
        with out.open("a", encoding="utf-8") as sink:  # noqa: ASYNC230
            for i in range(0, len(works), BATCH):
                batch = works[i : i + BATCH]
                expected = {w["id"]: w["language"] for w in batch}
                # Ask the same batch N times INDEPENDENTLY and keep only what
                # the runs agree on. The model's own `confidence` is not a
                # reliability signal — a 60-row re-ask of titles it called
                # `high` disagreed with itself 9% of the time, and one of those
                # reached production (`Akhet` -> અખેત, cover reads આખેટ).
                # Concurrent because they are independent; the wall clock is
                # then the same as a single-vote run.
                results = await asyncio.gather(
                    *(_one_vote(client, key, batch, expected) for _ in range(args.votes))
                )
                runs = [r for r, _ in results if r]
                problems = [p for _, ps in results for p in ps]
                rows = tally_votes(runs, expected) if runs else []
                by_id = {r["id"]: r for r in rows}
                for w in batch:
                    row = by_id.get(
                        w["id"], {"id": w["id"], "kind": "unknown", "title": None,
                                  "confidence": "unknown", "votes": 0, "runs": 0}
                    )
                    row |= {
                        "before": w["title"],
                        "language": w["language"],
                        "authors": w["authors"],
                    }
                    sink.write(json.dumps(row, ensure_ascii=False) + "\n")
                    written += 1
                sink.flush()
                failures += len(problems)
                for p in problems:
                    print(f"  ! {p}", file=sys.stderr)
                kept = sum(1 for r in rows if r["kind"] in (NATIVE, ENGLISH))
                unan = sum(1 for r in rows
                           if r["kind"] in (NATIVE, ENGLISH) and r["votes"] == args.votes)
                print(f"  batch {i // BATCH + 1}/{(len(works) - 1) // BATCH + 1}: "
                      f"{kept}/{len(batch)} agreed ({unan} unanimously)")

    print(f"wrote {written} rows to {out} ({failures} problems — see stderr)")


# --------------------------------------------------------------------------
# apply / revert
# --------------------------------------------------------------------------


def read_plan(path: Path, confidences: set[str], min_votes: int) -> list[dict]:
    rows = []
    for n, line in enumerate(path.read_text().splitlines(), 1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            sys.exit(f"{path}:{n}: unparseable line")
        if (
            row.get("kind") in (NATIVE, ENGLISH)
            and row.get("title")
            and row.get("confidence") in confidences
            # A plan written before voting existed has no `votes` key; treating
            # that as 0 makes it fail the gate rather than sail past it.
            and row.get("votes", 0) >= min_votes
            and row["title"] != row.get("before")
        ):
            rows.append(row)
    return rows


async def _retitle(conn, work_id: str, new: str, expect: str) -> bool:  # noqa: ANN001
    """Guarded on the current title still being what the plan saw — a plan is a
    snapshot, and a human edit in between must not be overwritten."""
    result = await conn.execute(
        "UPDATE works SET title = $2, title_translit = $3, title_fold = $4, "
        "updated_at = now() WHERE id = $1 AND deleted_at IS NULL AND title = $5",
        uuid.UUID(work_id), new, transliterate(new), fold(new), expect,
    )
    return result.split()[-1] != "0"


async def cmd_apply(args: argparse.Namespace) -> None:
    url = database_url()
    guard_production(url, args.production)
    confidences = {c.strip() for c in args.confidence.split(",")} & set(CONFIDENCES)
    rows = read_plan(Path(args.plan), confidences, args.min_votes)
    print(f"{len(rows)} titles to restore at confidence {sorted(confidences)}, "
          f"min {args.min_votes} agreeing votes")
    if not rows:
        return

    conn = await connect(url)
    done: list[dict] = []
    skipped = 0
    try:
        async with conn.transaction():
            for row in rows:
                if await _retitle(conn, row["id"], row["title"], row["before"]):
                    done.append({"id": row["id"], "kind": row["kind"],
                                 "votes": f'{row.get("votes")}/{row.get("runs")}',
                                 "before": row["before"], "after": row["title"]})
                else:
                    skipped += 1
    finally:
        await conn.close()

    # Written only after the transaction commits: a receipt is a claim about
    # what the database now holds.
    receipt = Path(args.receipt)
    receipt.parent.mkdir(parents=True, exist_ok=True)
    with receipt.open("a", encoding="utf-8") as sink:
        for e in done:
            sink.write(json.dumps(e, ensure_ascii=False) + "\n")
    print(f"retitled {len(done)}, skipped {skipped} (changed since the plan) — {receipt}")


async def cmd_revert(args: argparse.Namespace) -> None:
    url = database_url()
    guard_production(url, args.production)
    conn = await connect(url)
    reverted = kept = 0
    try:
        async with conn.transaction():
            for line in Path(args.receipt).read_text().splitlines():
                if not line.strip():
                    continue
                row = json.loads(line)
                ok = await _retitle(conn, row["id"], row["before"], row["after"])
                reverted += ok
                kept += not ok
    finally:
        await conn.close()
    print(f"reverted {reverted}, left {kept} alone (edited since)")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("plan", help="identify romanized titles into a reviewable JSONL")
    p.add_argument("--out", default="title_plan.jsonl")
    p.add_argument("--limit", type=int, default=0, help="smoke-test on the first N works")
    p.add_argument("--votes", type=int, default=3,
                   help="independent samples per batch; a title is kept only where they agree")

    a = sub.add_parser("apply", help="write a reviewed plan to the database")
    a.add_argument("--plan", default="title_plan.jsonl")
    a.add_argument("--receipt", default="title_receipt.jsonl")
    a.add_argument("--confidence", default="high")
    a.add_argument("--min-votes", type=int, default=2,
                   help="how many independent runs must have agreed (3 = unanimous)")
    a.add_argument("--production", action="store_true")

    r = sub.add_parser("revert", help="undo exactly what one receipt recorded")
    r.add_argument("--receipt", default="title_receipt.jsonl")
    r.add_argument("--production", action="store_true")

    args = parser.parse_args()
    asyncio.run({"plan": cmd_plan, "apply": cmd_apply, "revert": cmd_revert}[args.cmd](args))


if __name__ == "__main__":
    main()
