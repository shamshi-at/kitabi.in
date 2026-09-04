"""The pre-launch wipe against a real database, with a reader's complete
footprint seeded first.

`test_reset_user_data.py` checks the script's bookkeeping; this runs the actual
statements. It is the half that would catch a delete ordered after its parent
(FK violation), a scrub naming a column that moved, or — the failure that would
actually hurt — a wipe that takes catalog rows with it.
"""

import importlib.util
import json
import sys
import uuid
from datetime import UTC, date, datetime, timedelta
from pathlib import Path
from urllib.parse import urlsplit

import pytest
from sqlalchemy import text

from app.models.active_reading_session import ActiveReadingSession
from app.models.activity_log_entry import ActivityLogEntry
from app.models.admin import ContentReport
from app.models.author import Author
from app.models.author_claim import AuthorClaim
from app.models.conflict_history import ConflictHistory
from app.models.connection import Connection
from app.models.device_token import DeviceToken
from app.models.edition import Edition
from app.models.genre import Genre
from app.models.lending_record import LendingRecord
from app.models.library_entry import LibraryEntry
from app.models.library_entry_tag import LibraryEntryTag
from app.models.llm_usage import LlmUsage
from app.models.personal_tag import PersonalTag
from app.models.profile import Profile
from app.models.promotion import Promotion, PromotionContent, PromotionEvent
from app.models.publisher import Publisher
from app.models.rating import Rating
from app.models.reading_note import ReadingNote
from app.models.reading_session import ReadingSession
from app.models.rec_cache import RecCache
from app.models.review import Review
from app.models.sync_op import SyncOp
from app.models.work import Work
from app.models.work_revision import WorkRevision

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "reset_user_data.py"


def _load():
    spec = importlib.util.spec_from_file_location("reset_user_data", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


async def _counts(db, tables) -> dict[str, int]:
    return {t: (await db.execute(text(f'select count(*) from "{t}"'))).scalar_one() for t in tables}


async def _seed(db, user_id: uuid.UUID) -> dict:
    """One reader with something in every table the wipe touches, on top of a
    small catalog that must survive it untouched."""
    now = datetime.now(UTC)

    author = Author(name="Thakazhi Sivasankara Pillai", created_by_user_id=user_id)
    publisher = Publisher(name="DC Books")
    genre = Genre(name="Malayalam Fiction")
    db.add_all([author, publisher, genre])
    await db.flush()

    work = Work(
        title="Chemmeen",
        authors=[author],
        genres=[genre],
        created_by_user_id=user_id,
        aggregate_rating=4.5,
    )
    db.add(work)
    await db.flush()
    edition = Edition(work_id=work.id, publisher_id=publisher.id, page_count=224)
    db.add(edition)
    await db.flush()

    db.add(Profile(id=user_id, email="tester@example.com", username="tester"))
    entry = LibraryEntry(user_id=user_id, edition_id=edition.id, status="reading")
    db.add(entry)
    await db.flush()

    session = ReadingSession(
        user_id=user_id,
        library_entry_id=entry.id,
        started_at=now - timedelta(hours=1),
        ended_at=now,
        duration_seconds=3600,
    )
    tag = PersonalTag(user_id=user_id, name="Kerala shelf")
    db.add_all([session, tag])
    await db.flush()

    promotion = Promotion(name="test campaign", work_id=work.id)
    db.add(promotion)
    await db.flush()
    db.add(PromotionContent(promotion_id=promotion.id, headline="A book worth your evening"))

    db.add_all(
        [
            ReadingNote(
                user_id=user_id,
                library_entry_id=entry.id,
                session_id=session.id,
                body="The sea is a character.",
            ),
            LibraryEntryTag(user_id=user_id, library_entry_id=entry.id, tag_id=tag.id),
            LendingRecord(
                user_id=user_id,
                library_entry_id=entry.id,
                edition_id=edition.id,
                borrower_name="Anu",
                lent_date=date(2026, 8, 1),
            ),
            Rating(user_id=user_id, work_id=work.id, value=5),
            Review(user_id=user_id, work_id=work.id, body="Devastating.", visible=True),
            ActivityLogEntry(
                user_id=user_id,
                event_type="finished",
                entity_type="library_entry",
                entity_id=entry.id,
                occurred_at=now,
            ),
            ConflictHistory(
                user_id=user_id,
                entity="library_entries",
                entity_id=entry.id,
                rule="last_write_wins",
                winning_payload={},
                discarded_payload={},
                expires_at=now + timedelta(days=30),
            ),
            SyncOp(
                op_id=uuid.uuid4(),
                user_id=user_id,
                device_id=uuid.uuid4(),
                entity="library_entries",
                entity_id=entry.id,
                op_type="create",
                status="applied",
            ),
            DeviceToken(user_id=user_id, token="fcm-token-abc", device_id="phone-a"),
            ActiveReadingSession(
                user_id=user_id,
                session_id=uuid.uuid4(),
                library_entry_id=entry.id,
                started_at=now,
                device_id="phone-a",
            ),
            Connection(requester_id=user_id, addressee_id=uuid.uuid4()),
            ContentReport(reporter_user_id=user_id, target_type="review", target_id=uuid.uuid4()),
            AuthorClaim(author_id=author.id, user_id=user_id),
            WorkRevision(work_id=work.id, proposed_by_user_id=user_id, payload={"title": "x"}),
            LlmUsage(user_id=user_id, feature="recommendations", day=now.date(), count=3),
            RecCache(
                user_id=user_id,
                fingerprint="whatever fed the prompt",
                picks=[{"work_id": str(work.id), "why": "Because."}],
                generated_at=now,
            ),
            PromotionEvent(
                id=uuid.uuid4(),
                promotion_id=promotion.id,
                user_id=user_id,
                kind="impression",
                occurred_at=now,
            ),
        ]
    )
    await db.commit()
    return {
        "work_id": work.id,
        "edition_id": edition.id,
        "author_id": author.id,
        "publisher_id": publisher.id,
        "genre_id": genre.id,
        "promotion_id": promotion.id,
    }


@pytest.mark.anyio
async def test_wipe_removes_every_reader_row_and_keeps_the_catalog(db_sessionmaker, user):
    mod = _load()
    user_id = uuid.UUID(user["id"])

    async with db_sessionmaker() as db:
        # Counted either side of the seed, and compared as a DELTA.
        #
        # `_counts` counts whole tables, and `run_wipe` empties whole tables, so
        # this suite's other tests leave committed rows lying about. Asserting
        # "every table is non-empty" therefore passed on *their* rows: rec_cache
        # sat in USER_TABLES with nothing in this seed ever touching it, and the
        # check that exists to catch exactly that stayed green — while failing
        # the moment the file was run on its own, which is how it surfaced
        # (4 Sep 2026). A delta only passes if THIS seed inserted the row.
        empty = await _counts(db, mod.USER_TABLES)
        seeded = await _seed(db, user_id)
        before = await _counts(db, mod.USER_TABLES)
        missed = [t for t in mod.USER_TABLES if before[t] <= empty[t]]
        assert not missed, f"seed missed: {missed}"

        await mod.run_wipe(db, list(mod.USER_TABLES))
        await db.commit()

        after = await _counts(db, mod.USER_TABLES)
        assert after == dict.fromkeys(mod.USER_TABLES, 0)

        # The catalog is still there, joins included.
        for table, pk in [
            ("works", seeded["work_id"]),
            ("editions", seeded["edition_id"]),
            ("authors", seeded["author_id"]),
            ("publishers", seeded["publisher_id"]),
            ("genres", seeded["genre_id"]),
            ("promotions", seeded["promotion_id"]),
        ]:
            n = (
                await db.execute(text(f"select count(*) from {table} where id = :i"), {"i": pk})
            ).scalar_one()
            assert n == 1, f"{table} lost its row"
        for join in ("work_authors", "work_genres"):
            n = (await db.execute(text(f"select count(*) from {join}"))).scalar_one()
            assert n == 1, f"{join} lost its row"

        # ...but carries no pointer to the reader who is gone, and no rating.
        row = (
            await db.execute(
                text("select created_by_user_id, aggregate_rating from works where id = :i"),
                {"i": seeded["work_id"]},
            )
        ).one()
        assert row == (None, None)
        row = (
            await db.execute(
                text("select created_by_user_id, linked_user_id from authors where id = :i"),
                {"i": seeded["author_id"]},
            )
        ).one()
        assert row == (None, None)


@pytest.mark.anyio
async def test_snapshot_captures_everything_the_wipe_destroys(db_sessionmaker, user):
    """`--apply` refuses to run without a snapshot, so the snapshot has to be a
    real undo record — every deleted row and every scrubbed value, JSON-encodable."""
    mod = _load()
    user_id = uuid.UUID(user["id"])
    async with db_sessionmaker() as db:
        seeded = await _seed(db, user_id)

        snap = await mod.snapshot(db, list(mod.USER_TABLES))
        assert set(snap["tables"]) == set(mod.USER_TABLES)

        # Row counts in the snapshot match what the wipe then deletes.
        deleted = await mod.run_wipe(db, list(mod.USER_TABLES))
        await db.commit()
    for t in mod.USER_TABLES:
        assert len(snap["tables"][t]) == deleted[t], t

    # The pre-scrub catalog values are recoverable from it.
    works = {r["id"]: r for r in snap["scrubs"]["works.created_by_user_id"]}
    assert works[str(seeded["work_id"])]["created_by_user_id"] == str(user_id)
    ratings = {r["id"]: r for r in snap["scrubs"]["works.aggregate_rating"]}
    assert ratings[str(seeded["work_id"])]["aggregate_rating"] == 4.5

    json.dumps(snap)  # UUIDs, datetimes, dates and JSONB all survive encoding


@pytest.mark.anyio
async def test_the_cli_itself_wipes_and_writes_its_snapshot(
    db_sessionmaker, database_url, user, tmp_path, monkeypatch
):
    """Drive `main()` the way a person does, not just its helpers.

    The first production run failed exactly here: the counting SELECTs autobegin
    a transaction, so `conn.begin()` raised and the wipe deleted nothing while
    the snapshot on disk suggested it had. Every helper test passed.
    """
    mod = _load()
    async with db_sessionmaker() as db:
        seeded = await _seed(db, uuid.UUID(user["id"]))

    snap_path = tmp_path / "snapshot.json"
    host = urlsplit(database_url).hostname
    monkeypatch.setenv("DATABASE_URL", database_url)
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "reset_user_data.py",
            "--apply",
            "--confirm-host",
            host,
            "--snapshot",
            str(snap_path),
        ],
    )

    assert await mod.main() == 0

    written = json.loads(snap_path.read_text())
    assert sum(len(v) for v in written["tables"].values()) > 0

    async with db_sessionmaker() as db:
        after = await _counts(db, mod.USER_TABLES)
        assert after == dict.fromkeys(mod.USER_TABLES, 0)
        n = (
            await db.execute(
                text("select count(*) from works where id = :i"), {"i": seeded["work_id"]}
            )
        ).scalar_one()
        assert n == 1


@pytest.mark.anyio
async def test_apply_refuses_without_a_snapshot_or_with_the_wrong_host(
    db_sessionmaker, database_url, user, tmp_path, monkeypatch
):
    """Both guards must actually stop the run — and leave the data alone."""
    mod = _load()
    async with db_sessionmaker() as db:
        await _seed(db, uuid.UUID(user["id"]))

    monkeypatch.setenv("DATABASE_URL", database_url)

    for argv in (
        ["reset_user_data.py", "--apply", "--confirm-host", urlsplit(database_url).hostname],
        [
            "reset_user_data.py",
            "--apply",
            "--confirm-host",
            "wrong.example.com",
            "--snapshot",
            str(tmp_path / "s.json"),
        ],
    ):
        monkeypatch.setattr(sys, "argv", argv)
        assert await mod.main() == 2

    async with db_sessionmaker() as db:
        assert (await db.execute(text("select count(*) from profiles"))).scalar_one() == 1


@pytest.mark.anyio
async def test_optional_flags_drop_promotions_and_admin_sessions(db_sessionmaker, user):
    """The promotion campaign survives the default wipe and only goes when asked."""
    mod = _load()
    async with db_sessionmaker() as db:
        await _seed(db, uuid.UUID(user["id"]))

        await mod.run_wipe(db, list(mod.USER_TABLES))
        await db.commit()
        assert (await db.execute(text("select count(*) from promotions"))).scalar_one() == 1

        await mod.run_wipe(db, list(mod.OPTIONAL["drop-promotions"]))
        await db.commit()
        assert (await db.execute(text("select count(*) from promotions"))).scalar_one() == 0
        assert (await db.execute(text("select count(*) from promotion_contents"))).scalar_one() == 0
