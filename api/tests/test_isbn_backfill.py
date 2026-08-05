"""Migration 000041 — the ISBN-10 → ISBN-13 backfill, driven against real rows.

The interesting behaviour is not what it converts; it is the two cases it must
REFUSE to touch. Both fail silently if wrong: a mis-keyed ISBN-10 converted
anyway becomes a valid ISBN-13 for somebody else's book, and a collision on the
UNIQUE index takes down a deploy rather than one row.
"""

import importlib.util
import uuid
from pathlib import Path

from sqlalchemy import text

_PATH = (
    Path(__file__).resolve().parents[1]
    / "alembic"
    / "versions"
    / "20260805_000041_canonical_isbn13.py"
)
_spec = importlib.util.spec_from_file_location("migration_000041", _PATH)
migration = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(migration)


def test_the_arithmetic_matches_the_service_it_was_copied_from():
    """The migration carries its own copy on purpose (importing app code welds a
    migration to a moving target). This is the guard that the copy is faithful —
    a divergence here means rows were rewritten by rules the app doesn't share."""
    from app.services import isbn as isbn_util

    for ten in ("8126403454", "0306406152", "043942089X", "316148410X"):
        assert migration._is_valid_isbn10(ten)
        assert migration._to_isbn13(ten) == isbn_util.to_isbn13(ten)

    assert not migration._is_valid_isbn10("8126403455")  # bad checksum
    assert not migration._is_valid_isbn10("9788126403455")  # ISBN-13, wrong family


async def _work(db):
    work_id = uuid.uuid4()
    await db.execute(
        text(
            "INSERT INTO works (id, title, created_at, updated_at) "
            "VALUES (:id, 'A Book', now(), now())"
        ),
        {"id": work_id},
    )
    return work_id


async def _edition(db, work_id, isbn):
    edition_id = uuid.uuid4()
    await db.execute(
        text(
            "INSERT INTO editions (id, work_id, isbn, created_at, updated_at) "
            "VALUES (:id, :work_id, :isbn, now(), now())"
        ),
        {"id": edition_id, "work_id": work_id, "isbn": isbn},
    )
    return edition_id


async def _isbn_of(db, edition_id):
    return (
        await db.execute(text("SELECT isbn FROM editions WHERE id = :id"), {"id": edition_id})
    ).scalar_one()


async def test_backfill_canonicalises_leaves_alone_and_never_collides(db_sessionmaker):
    async with db_sessionmaker() as db:
        work = await _work(db)
        converted = await _edition(db, work, "8126403454")  # valid → rewritten
        misprint = await _edition(db, work, "1234567890")  # bad checksum → left alone
        already13 = await _edition(db, work, "9780306406157")  # not ISBN-10 shaped
        no_isbn = await _edition(db, work, None)

        # The collision case: both forms of the SAME book already on two rows.
        # `editions.isbn` is UNIQUE, so rewriting the 10 would violate it.
        collide_13 = await _edition(db, work, "9780439420891")
        collide_10 = await _edition(db, work, "043942089X")
        await db.commit()

        connection = await db.connection()
        await connection.run_sync(migration._backfill)
        await db.commit()

        assert await _isbn_of(db, converted) == "9788126403455"
        assert await _isbn_of(db, misprint) == "1234567890", "a bad checksum must not be guessed at"
        assert await _isbn_of(db, already13) == "9780306406157"
        assert await _isbn_of(db, no_isbn) is None
        assert await _isbn_of(db, collide_10) == "043942089X", "the colliding row is left for merge"
        assert await _isbn_of(db, collide_13) == "9780439420891"


async def test_backfill_is_idempotent(db_sessionmaker):
    """It runs on every replay of the migration history, and a second pass must
    find nothing left to do rather than double-converting."""
    async with db_sessionmaker() as db:
        work = await _work(db)
        edition = await _edition(db, work, "8126403454")
        await db.commit()

        for _ in range(2):
            connection = await db.connection()
            await connection.run_sync(migration._backfill)
            await db.commit()

        assert await _isbn_of(db, edition) == "9788126403455"


async def test_backfill_on_an_empty_catalogue_does_nothing(db_sessionmaker):
    async with db_sessionmaker() as db:
        connection = await db.connection()
        await connection.run_sync(migration._backfill)
        await db.commit()
