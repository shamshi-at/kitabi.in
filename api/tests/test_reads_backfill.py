"""Migration 000050's backfill, run against real rows.

The backfill is the only part of "a read is a record" that touches data that
already exists, so it is the part worth a test. It runs the **actual**
statements from the migration module — imported, not retyped — because a
fixture written from a copy of the SQL only proves the copy agrees with itself
(the 9 Aug 2026 review-body lesson).

What it has to get right: one read per entry that shows evidence of reading and
none for an entry nobody has opened; the entry's status mapped onto the pass;
the dates and page carried across; and every existing sitting and note adopted
into that pass with a fresh `server_seq`, so devices re-pull them and learn
which read they belong to.
"""

import importlib.util
import uuid
from datetime import UTC, date, datetime, timedelta
from pathlib import Path

import pytest
from sqlalchemy import text

from app.models.edition import Edition
from app.models.library_entry import LibraryEntry
from app.models.reading_note import ReadingNote
from app.models.reading_session import ReadingSession
from app.models.work import Work

MIGRATION = (
    Path(__file__).resolve().parents[1] / "alembic" / "versions" / "20260904_000050_reads.py"
)


def _migration():
    spec = importlib.util.spec_from_file_location("m000050", MIGRATION)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


async def _edition(db) -> Edition:
    work = Work(title="Aadujeevitham")
    db.add(work)
    await db.flush()
    edition = Edition(work_id=work.id, page_count=212)
    db.add(edition)
    await db.flush()
    return edition


@pytest.mark.anyio
async def test_backfill_writes_one_read_per_read_book_and_adopts_its_log(db_sessionmaker, user):
    mod = _migration()
    user_id = uuid.UUID(user["id"])
    now = datetime.now(UTC)

    async with db_sessionmaker() as db:
        edition = await _edition(db)

        finished = LibraryEntry(
            user_id=user_id,
            edition_id=edition.id,
            status="read",
            start_date=date(2026, 3, 12),
            finish_date=date(2026, 4, 3),
            current_page=212,
        )
        reading = LibraryEntry(
            user_id=user_id, edition_id=edition.id, status="reading", current_page=88
        )
        # Never opened: no dates, no page, no sittings. Inventing a pass for
        # this one would claim a reading that never happened.
        untouched = LibraryEntry(user_id=user_id, edition_id=edition.id, status="wishlist")
        db.add_all([finished, reading, untouched])
        await db.flush()

        sitting = ReadingSession(
            user_id=user_id,
            library_entry_id=finished.id,
            started_at=now - timedelta(hours=1),
            ended_at=now,
            duration_seconds=3600,
        )
        db.add(sitting)
        await db.flush()
        note = ReadingNote(
            user_id=user_id,
            library_entry_id=finished.id,
            session_id=sitting.id,
            body="The desert chapters land differently now.",
        )
        db.add(note)
        await db.flush()

        # The rows exist without a pass, exactly as every row in production
        # does the moment before this migration runs.
        await db.execute(
            text("UPDATE reading_sessions SET read_id = NULL WHERE id = :i"),
            {"i": sitting.id},
        )
        await db.execute(
            text("UPDATE reading_notes SET read_id = NULL WHERE id = :i"),
            {"i": note.id},
        )
        seq_before = (
            await db.execute(
                text("SELECT server_seq FROM reading_sessions WHERE id = :i"),
                {"i": sitting.id},
            )
        ).scalar_one()

        await db.execute(text(mod.BACKFILL_READS_SQL))
        for child in ("reading_sessions", "reading_notes"):
            await db.execute(text(mod.ADOPT_CHILDREN_SQL.format(child=child)))
        await db.commit()

        rows = (
            await db.execute(
                text(
                    "SELECT library_entry_id, status, start_date, finish_date,"
                    " current_page FROM reads WHERE user_id = :u"
                ),
                {"u": user_id},
            )
        ).all()
        by_entry = {r[0]: r for r in rows}

        # One pass each for the two books with history, none for the untouched.
        assert set(by_entry) == {finished.id, reading.id}

        assert by_entry[finished.id][1] == "read"
        assert by_entry[finished.id][2] == date(2026, 3, 12)
        assert by_entry[finished.id][3] == date(2026, 4, 3)
        assert by_entry[finished.id][4] == 212
        assert by_entry[reading.id][1] == "reading"

        # The sitting and the note now name the pass they belong to…
        read_id = (
            await db.execute(
                text("SELECT id FROM reads WHERE library_entry_id = :e"),
                {"e": finished.id},
            )
        ).scalar_one()
        stamped_session, seq_after = (
            await db.execute(
                text("SELECT read_id, server_seq FROM reading_sessions WHERE id = :i"),
                {"i": sitting.id},
            )
        ).one()
        assert stamped_session == read_id
        stamped_note = (
            await db.execute(
                text("SELECT read_id FROM reading_notes WHERE id = :i"), {"i": note.id}
            )
        ).scalar_one()
        assert stamped_note == read_id

        # …and moved above any cursor a device can already hold, or the phone
        # that wrote them would never learn which pass they belong to.
        assert seq_after > seq_before


@pytest.mark.anyio
async def test_backfill_is_idempotent(db_sessionmaker, user):
    """A migration that can run twice must not write the pass twice."""
    mod = _migration()
    user_id = uuid.UUID(user["id"])

    async with db_sessionmaker() as db:
        edition = await _edition(db)
        entry = LibraryEntry(
            user_id=user_id,
            edition_id=edition.id,
            status="read",
            finish_date=date(2021, 1, 9),
        )
        db.add(entry)
        await db.flush()

        await db.execute(text(mod.BACKFILL_READS_SQL))
        await db.commit()
        first = (
            await db.execute(
                text("SELECT count(*) FROM reads WHERE library_entry_id = :e"),
                {"e": entry.id},
            )
        ).scalar_one()
        assert first == 1
