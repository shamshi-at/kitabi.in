"""See a night's catalogue intake before letting it happen.

Runs the real adapters against the real sources, screens every candidate
through the real gate, and asks the real database which of them it already
holds — then prints exactly what tonight's job would create. **It writes
nothing.** There is no `--apply`: promoting is the job's business, and the
switch for that is `CATALOG_INTAKE_ENABLED` in `api/Dockerfile`.

    # against production, read-only — the useful one
    DATABASE_URL="$(grep ^DATABASE_URL api/.env | cut -d= -f2-)" \
        .venv/bin/python scripts/preview_intake.py

    # a smaller, faster look
    .venv/bin/python scripts/preview_intake.py --seeds 3 --per-seed 10

    # everything that would be held back, and why
    .venv/bin/python scripts/preview_intake.py --show-held

**Point it at production.** That is not a hazard here, it is the point: a
preview against an empty dev database cannot tell you which books you already
have, and "already in the catalogue" is most of what distinguishes a useful
night from a wasted one. Every statement this issues is a SELECT, the session
is never committed, and it is opened read-only where the driver allows it.

What the numbers mean:

    would create    complete, not already held — these become books tonight
    already have    the catalogue holds this book (same ISBN, or same
                    upstream record from the earlier etl seed)
    held            a real book missing a field; waits for another source
    refused         not a book, or not fixable — never retried
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys
from collections import Counter
from urllib.parse import urlsplit

import httpx
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app.core.config import get_settings  # noqa: E402
from app.core.db import _engine_kwargs, _normalize  # noqa: E402
from app.jobs.catalog_intake import USER_AGENT  # noqa: E402
from app.services import intake_gate, intake_openlibrary, intake_service  # noqa: E402
from app.services.intake_gate import Candidate  # noqa: E402


def _fmt(value: object, width: int) -> str:
    text = "—" if value in (None, "", ()) else str(value)
    return text if len(text) <= width else text[: width - 1] + "…"


async def _discover(seeds: int, per_seed: int) -> list[Candidate]:
    chosen = intake_openlibrary.SEEDS[:seeds] if seeds else intake_openlibrary.SEEDS
    print(f"asking {len(chosen)} seed(s) for up to {per_seed} each…\n")
    async with httpx.AsyncClient(timeout=30, headers={"User-Agent": USER_AGENT}) as client:
        return await intake_openlibrary.discover(client, seeds=chosen, per_seed=per_seed)


async def main() -> int:
    settings = get_settings()
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--seeds", type=int, default=0, help="use only the first N seeds (0 = all)")
    p.add_argument("--per-seed", type=int, default=intake_openlibrary.PER_SEED)
    p.add_argument(
        "--limit",
        type=int,
        default=settings.catalog_intake_daily_limit,
        help="the nightly budget to simulate (default: catalog_intake_daily_limit)",
    )
    p.add_argument("--show-held", action="store_true", help="list every held candidate")
    p.add_argument("--show-refused", action="store_true", help="list every refused candidate")
    args = p.parse_args()

    url = _normalize(os.environ.get("DATABASE_URL") or settings.database_url)
    host = urlsplit(url).hostname or "?"
    print(f"database : {host}  (read-only — this script never writes)")
    print(f"budget   : {args.limit} books a night\n")

    candidates = await _discover(args.seeds, args.per_seed)
    print(f"discovered {len(candidates)} candidates\n")

    engine = create_async_engine(url, **_engine_kwargs(url), echo=False)
    would_create: list[Candidate] = []
    already: list[tuple[Candidate, object]] = []
    held: list[intake_gate.Screened] = []
    refused: list[intake_gate.Screened] = []

    try:
        async with AsyncSession(engine) as session:
            # Belt and braces: ask the server to refuse a write even if this
            # script ever grows one by accident.
            await session.connection(execution_options={"postgresql_readonly": True})
            for candidate in candidates:
                screened = intake_gate.screen(candidate)
                if screened.rejected:
                    refused.append(screened)
                elif not screened.ok:
                    held.append(screened)
                else:
                    existing = await intake_service.already_catalogued(session, screened.candidate)
                    if existing is not None:
                        already.append((screened.candidate, existing))
                    else:
                        would_create.append(screened.candidate)
    finally:
        await engine.dispose()

    tonight = would_create[: args.limit]
    print("=" * 96)
    print(f"  would create   {len(would_create):4}   ({len(tonight)} tonight, at the budget)")
    print(f"  already have   {len(already):4}")
    print(f"  held           {len(held):4}   waiting for a field another source may supply")
    print(f"  refused        {len(refused):4}   not a book, or not fixable")
    print("=" * 96)

    if tonight:
        print("\nTONIGHT — these would become catalogue books:\n")
        print(f"  {'TITLE':40} {'AUTHOR':22} {'PUBLISHER':22} {'ISBN':14} COVER")
        print("  " + "-" * 92)
        for c in tonight:
            print(
                f"  {_fmt(c.title, 40):40} {_fmt(', '.join(c.authors), 22):22} "
                f"{_fmt(c.publisher, 22):22} {_fmt(c.isbn, 14):14} "
                f"{'yes' if c.cover_url else 'NO'}"
            )
        if len(would_create) > len(tonight):
            print(f"\n  …and {len(would_create) - len(tonight)} more on following nights.")

    if held:
        print("\nHELD — why:\n")
        for reason, n in Counter(r for s in held for r in s.missing).most_common():
            print(f"  {n:4}  {reason}")
        if args.show_held:
            for s in held:
                print(f"    - {_fmt(s.candidate.title, 60):60} {', '.join(s.missing)}")

    if refused:
        print("\nREFUSED — why:\n")
        for reason, n in Counter(r for s in refused for r in s.fatal).most_common():
            print(f"  {n:4}  {reason}")
        if args.show_refused:
            for s in refused:
                print(f"    - {_fmt(s.candidate.title, 60):60} {', '.join(s.fatal)}")

    print("\nNothing was written. To let this actually run, set")
    print("CATALOG_INTAKE_ENABLED=1 (see api/Dockerfile).")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
