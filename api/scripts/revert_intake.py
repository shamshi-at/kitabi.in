"""Undo what the nightly intake published — a night, a source, or all of it.

The intake publishes unattended, so the way back has to be one command. Every
promotion leaves its receipt on the staging row; this reads those receipts
backwards (`intake_service.revert`).

**A dry run unless you say `--apply`.** Without it this prints what would be
undone and writes nothing.

    # what did last night publish?  (dry run)
    DATABASE_URL="$(grep ^DATABASE_URL .env | cut -d= -f2-)" \
        .venv/bin/python scripts/revert_intake.py --since 2026-10-05

    # undo one shop's books from that night
    … scripts/revert_intake.py --since 2026-10-05 --source harpercollins_in --apply

What undoing means: the books are soft-deleted (rule 3) — they leave the
catalogue, search and the public site, and a reader who already shelved one
keeps their entry. A row that was added as another *printing* of an existing
book loses only that printing. Undone rows are not published again: the ISBN
stays claimed by the soft-deleted edition, so the next night records them as
duplicates.

To stop the intake altogether, remove `ENV CATALOG_INTAKE_ENABLED=1` from
`api/Dockerfile` and push.
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys
from datetime import UTC, datetime
from urllib.parse import urlsplit

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app.core.config import get_settings  # noqa: E402
from app.core.db import _engine_kwargs, _normalize  # noqa: E402
from app.models import CatalogIntake  # noqa: E402
from app.models.catalog_intake import STATE_PROMOTED  # noqa: E402
from app.services import intake_service  # noqa: E402


def _day(value: str) -> datetime:
    return datetime.strptime(value, "%Y-%m-%d").replace(tzinfo=UTC)


async def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--since", type=_day, required=True, help="UTC date, YYYY-MM-DD")
    parser.add_argument("--until", type=_day, help="UTC date, exclusive (default: now)")
    parser.add_argument("--source", help="only this adapter, e.g. mathrubhumi")
    parser.add_argument("--apply", action="store_true", help="actually undo them")
    args = parser.parse_args()

    url = _normalize(os.environ.get("DATABASE_URL") or get_settings().database_url)
    print(f"database : {urlsplit(url).hostname or '?'}")
    print(f"mode     : {'APPLY — this will soft-delete' if args.apply else 'dry run'}\n")

    engine = create_async_engine(url, **_engine_kwargs(url), echo=False)
    try:
        async with AsyncSession(engine) as session:
            query = select(CatalogIntake).where(
                CatalogIntake.state == STATE_PROMOTED, CatalogIntake.promoted_at >= args.since
            )
            if args.until:
                query = query.where(CatalogIntake.promoted_at < args.until)
            if args.source:
                query = query.where(CatalogIntake.source == args.source)
            rows = (
                (await session.execute(query.order_by(CatalogIntake.promoted_at))).scalars().all()
            )

            for row in rows:
                payload = row.payload or {}
                kind = "printing" if payload.get(intake_service.PRINTING_KEY) else "book    "
                title = str(payload.get("title"))[:44]
                authors = ", ".join(payload.get("authors") or [])[:28]
                print(
                    f"  {row.promoted_at:%Y-%m-%d %H:%M}  {kind}  {row.source:17} "
                    f"{title:44} {authors}"
                )
            print(f"\n{len(rows)} promotion(s) match.")
            if not rows:
                return 0
            if not args.apply:
                print("Nothing was changed. Add --apply to undo them.")
                return 0
            undone = await intake_service.revert(session, [row.id for row in rows])
            print(f"Undone: {undone}.")
    finally:
        await engine.dispose()
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
