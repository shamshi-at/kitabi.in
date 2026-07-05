"""Seed the shared catalog with major Malayalam / Kerala authors, their
publishers, and a few major works each. Idempotent — safe to re-run (upserts by
name/title, never duplicates).

Run from the `api/` directory:

    .venv/bin/python scripts/seed_catalog.py

Targets whatever `DATABASE_URL` resolves to (local dev by default; export the
Supavisor pooler URL to seed production). Author portraits / publisher logos are
read from `kerala_seed_images.py` when present (fetched from Wikimedia)."""

import asyncio
import sys
from pathlib import Path

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent))  # `app` package
sys.path.insert(0, str(_HERE))  # sibling data modules

from kerala_seed import AUTHORS, PUBLISHERS  # noqa: E402

from app.core.config import get_settings  # noqa: E402
from app.core.db import _engine_kwargs, _normalize  # noqa: E402
from app.models import Author, Edition, Publisher, Work  # noqa: E402

try:
    from kerala_seed_images import AUTHOR_IMAGES, PUBLISHER_LOGOS  # noqa: E402
except ImportError:  # images not fetched yet — seed the text data anyway
    AUTHOR_IMAGES: dict[str, str | None] = {}
    PUBLISHER_LOGOS: dict[str, str | None] = {}


async def _get_or_create(session, model, name: str):
    stmt = select(model).where(func.lower(model.name) == name.lower())
    row = (await session.execute(stmt)).scalar_one_or_none()
    created = row is None
    if row is None:
        row = model(name=name)
        session.add(row)
        await session.flush()
    return row, created


async def _find_work(session, title: str) -> Work | None:
    stmt = select(Work).where(func.lower(Work.title) == title.lower())
    return (await session.execute(stmt)).scalar_one_or_none()


async def seed() -> dict[str, int]:
    settings = get_settings()
    # Reuse the app's pooler-safe engine config (statement cache off, unique
    # prepared-statement names) so this works against the Supavisor pooler too.
    url = _normalize(settings.database_url)
    engine = create_async_engine(url, **_engine_kwargs(url))
    sessionmaker = async_sessionmaker(engine, expire_on_commit=False)
    counts = {"publishers": 0, "authors": 0, "works": 0}

    async with sessionmaker() as session:
        publishers: dict[str, Publisher] = {}
        for spec in PUBLISHERS:
            pub, created = await _get_or_create(session, Publisher, spec["name"])
            logo = PUBLISHER_LOGOS.get(spec["name"])
            if logo:
                pub.logo_url = logo
            publishers[spec["name"]] = pub
            counts["publishers"] += int(created)

        for spec in AUTHORS:
            author, created = await _get_or_create(session, Author, spec["name"])
            counts["authors"] += int(created)
            if spec.get("pen_name"):
                author.pen_name = spec["pen_name"]
            image = AUTHOR_IMAGES.get(spec["name"])
            if image:
                author.image_url = image

            publisher = publishers.get(spec["publisher"])
            for work_spec in spec["works"]:
                if await _find_work(session, work_spec["title"]) is not None:
                    continue  # already catalogued (seed re-run, or from OpenLibrary)
                work = Work(
                    title=work_spec["title"],
                    language="Malayalam",
                    first_publish_year=work_spec.get("year"),
                    authors=[author],
                )
                session.add(work)
                await session.flush()
                session.add(
                    Edition(
                        work_id=work.id,
                        publisher_id=publisher.id if publisher else None,
                        language="Malayalam",
                    )
                )
                counts["works"] += 1

        await session.commit()

    await engine.dispose()
    return counts


if __name__ == "__main__":
    result = asyncio.run(seed())
    print(
        f"Seeded: +{result['authors']} authors, +{result['publishers']} publishers, "
        f"+{result['works']} works (existing rows left untouched)."
    )
