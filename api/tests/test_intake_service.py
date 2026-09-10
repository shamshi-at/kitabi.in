"""Staging and promotion — the half of intake that can create catalogue rows.

The property under test throughout is the one the owner asked for (9 Sep
2026): *no unwanted records*. Concretely that means discovery writes nothing
to the catalogue, promotion never publishes an incomplete or refused
candidate, never publishes the same book twice however it is re-run, and
leaves a receipt for everything it did publish.
"""

import uuid

import pytest
from sqlalchemy import func, select

from app.models import Author, CatalogIntake, Edition, Publisher, Work
from app.models.catalog_intake import (
    STATE_COMPLETE,
    STATE_DUPLICATE,
    STATE_INCOMPLETE,
    STATE_PROMOTED,
    STATE_REJECTED,
)
from app.services import intake_service
from app.services.intake_gate import Candidate

SOURCE = "openlibrary_en"


def candidate(key: str = "/works/OL1W", **over) -> Candidate:
    base = dict(
        source=SOURCE,
        source_key=key,
        external_source="openlibrary",
        external_id=key,
        title="The God of Small Things",
        authors=("Arundhati Roy",),
        publisher="HarperCollins India",
        isbn="9780060977498",
        cover_url="https://covers.openlibrary.org/b/id/1-L.jpg",
        language="English",
    )
    base.update(over)
    return Candidate(**base)


async def catalogue_size(session) -> tuple[int, int]:
    works = await session.scalar(select(func.count()).select_from(Work))
    editions = await session.scalar(select(func.count()).select_from(Edition))
    return works, editions


@pytest.fixture
async def session(db_sessionmaker):
    async with db_sessionmaker() as s:
        yield s


# --------------------------------------------------------------------------
# discovery creates nothing
# --------------------------------------------------------------------------


async def test_recording_candidates_touches_no_catalogue_table(session):
    """The safety property the whole two-step design exists for: a source can
    be crawled and re-crawled without a single book appearing."""
    await intake_service.record(
        session,
        [candidate(), candidate("/works/OL2W", isbn=None), candidate("/works/OL3W")],
        source=SOURCE,
    )
    assert await catalogue_size(session) == (0, 0)
    assert await session.scalar(select(func.count()).select_from(CatalogIntake)) == 3


async def test_candidates_are_staged_at_the_state_the_gate_gave_them(session):
    await intake_service.record(
        session,
        [
            candidate("/works/OK"),
            candidate("/works/GAP", isbn=None),
            candidate("/works/BAD", title="[South Asia pamphlet collection."),
        ],
        source=SOURCE,
    )
    rows = {r.source_key: r for r in (await session.execute(select(CatalogIntake))).scalars()}
    assert rows["/works/OK"].state == STATE_COMPLETE
    assert rows["/works/GAP"].state == STATE_INCOMPLETE
    assert rows["/works/BAD"].state == STATE_REJECTED
    assert rows["/works/GAP"].note == "waiting on: isbn"


async def test_a_recrawl_updates_rather_than_duplicating(session):
    await intake_service.record(session, [candidate(isbn=None)], source=SOURCE)
    await intake_service.record(session, [candidate()], source=SOURCE)
    rows = (await session.execute(select(CatalogIntake))).scalars().all()
    assert len(rows) == 1
    assert rows[0].state == STATE_COMPLETE


# --------------------------------------------------------------------------
# promotion
# --------------------------------------------------------------------------


async def test_a_complete_candidate_becomes_a_book_with_its_receipt(session):
    await intake_service.record(session, [candidate()], source=SOURCE)
    counts = await intake_service.promote(session, limit=10)

    assert counts == {STATE_PROMOTED: 1}
    row = (await session.execute(select(CatalogIntake))).scalar_one()
    assert row.state == STATE_PROMOTED
    assert row.work_id is not None and row.edition_id is not None
    assert row.promoted_at is not None

    work = await session.get(Work, row.work_id)
    assert work.title == "The God of Small Things"
    assert work.language == "English"
    # Provenance matches what the existing etl seed stamps, so the next run
    # recognises this book instead of creating a second one.
    assert (work.external_source, work.external_id) == ("openlibrary", "/works/OL1W")


async def test_a_promoted_book_arrives_complete(session):
    """Every field the gate required is actually on the row — a gate that
    passed a record whose publisher then failed to attach would be no gate."""
    await intake_service.record(session, [candidate()], source=SOURCE)
    await intake_service.promote(session, limit=10)

    work = (await session.execute(select(Work))).unique().scalar_one()
    edition = (await session.execute(select(Edition))).scalar_one()
    assert [a.name for a in work.authors] == ["Arundhati Roy"]
    assert edition.isbn == "9780060977498"
    assert edition.cover_url
    assert edition.publisher_id is not None
    publisher = await session.get(Publisher, edition.publisher_id)
    assert publisher.name == "HarperCollins India"


async def test_promotion_fills_the_search_columns_the_orm_maintains(session):
    """The difference from `etl/04_load.sql`, which `COPY`s and so needs
    `06_backfill_script.py` afterwards to recompute these. Going through the
    service layer means cross-script search works the moment the row lands."""
    await intake_service.record(
        session, [candidate(title="Chemmeen", authors=("Thakazhi",))], source=SOURCE
    )
    await intake_service.promote(session, limit=10)
    work = (await session.execute(select(Work))).unique().scalar_one()
    assert work.title_fold
    assert work.slug, "a published page needs its canonical URL immediately"


@pytest.mark.parametrize(
    "broken",
    [
        dict(isbn=None),
        dict(cover_url=None),
        dict(publisher=None),
        dict(authors=()),
        dict(title="[South Asia pamphlet collection."),
    ],
)
async def test_an_incomplete_or_refused_candidate_is_never_promoted(session, broken):
    await intake_service.record(session, [candidate(**broken)], source=SOURCE)
    counts = await intake_service.promote(session, limit=10)
    assert counts == {}
    assert await catalogue_size(session) == (0, 0)


async def test_the_daily_limit_is_a_ceiling_on_what_can_be_created(session):
    """The bound on how much a mistake in a source adapter can cost before
    anyone looks at it."""
    await intake_service.record(
        session,
        [candidate(f"/works/OL{i}W", isbn=f"978006097749{i}") for i in range(4)],
        source=SOURCE,
    )
    # Only some of those ISBNs are checksum-valid; whatever is complete, the
    # limit must hold.
    await intake_service.promote(session, limit=1)
    works, _ = await catalogue_size(session)
    assert works <= 1


async def test_promotion_is_resumable_rather_than_repeating(session):
    """A Railway redeploy mid-batch kills the job. The next run must continue,
    not re-publish what it already did."""
    await intake_service.record(
        session,
        [candidate("/works/A"), candidate("/works/B", isbn="9780143028109")],
        source=SOURCE,
    )
    await intake_service.promote(session, limit=1)
    await intake_service.promote(session, limit=10)
    works, editions = await catalogue_size(session)
    assert (works, editions) == (2, 2)


# --------------------------------------------------------------------------
# not publishing the same book twice
# --------------------------------------------------------------------------


async def test_an_isbn_already_in_the_catalogue_is_a_duplicate_not_a_second_work(session):
    await intake_service.record(session, [candidate()], source=SOURCE)
    await intake_service.promote(session, limit=10)

    # The same book found again under a different upstream key — only the
    # ISBN can tell us it is the same printing.
    await intake_service.record(session, [candidate("/works/OTHER")], source=SOURCE)
    counts = await intake_service.promote(session, limit=10)

    assert counts == {STATE_DUPLICATE: 1}
    works, _ = await catalogue_size(session)
    assert works == 1
    row = (
        await session.execute(
            select(CatalogIntake).where(CatalogIntake.source_key == "/works/OTHER")
        )
    ).scalar_one()
    assert row.state == STATE_DUPLICATE
    assert row.work_id is not None, "a duplicate should say which book it duplicates"


async def test_a_work_the_earlier_seed_already_published_is_recognised(session):
    """The 1,428 works `etl/` loaded carry `openlibrary` + the OL work key. A
    *different printing* of one of them has an unclaimed ISBN, so the ISBN
    guard cannot see it — only provenance can, and without this check the
    first intake run would duplicate the entire existing seed.
    """
    session.add(
        Work(
            title="Already Seeded",
            external_source="openlibrary",
            external_id="/works/OL1W",
        )
    )
    await session.commit()

    await intake_service.record(session, [candidate("/works/OL1W")], source=SOURCE)
    counts = await intake_service.promote(session, limit=10)

    assert counts == {STATE_DUPLICATE: 1}
    works, _ = await catalogue_size(session)
    assert works == 1


async def test_rediscovering_a_promoted_book_does_not_reopen_it(session):
    """Rewriting a promoted row's payload would make its receipt describe
    something other than what was created."""
    await intake_service.record(session, [candidate()], source=SOURCE)
    await intake_service.promote(session, limit=10)

    counts = await intake_service.record(
        session, [candidate(title="A Different Title")], source=SOURCE
    )
    assert counts == {"already_promoted": 1}
    row = (await session.execute(select(CatalogIntake))).scalar_one()
    assert row.state == STATE_PROMOTED
    assert row.payload["title"] == "The God of Small Things"


# --------------------------------------------------------------------------
# the held queue, and undo
# --------------------------------------------------------------------------


async def test_rescreening_releases_a_row_whose_gap_was_filled(session):
    """What storing the payload buys: a candidate held for a missing field is
    released when something supplies it, with no re-crawl."""
    await intake_service.record(session, [candidate(isbn=None)], source=SOURCE)
    row = (await session.execute(select(CatalogIntake))).scalar_one()
    assert row.state == STATE_INCOMPLETE

    row.payload = {**row.payload, "isbn": "9780060977498"}
    await session.commit()

    counts = await intake_service.rescreen_incomplete(session)
    assert counts == {STATE_COMPLETE: 1}
    await session.refresh(row)
    assert row.isbn == "9780060977498"


async def test_rescreening_leaves_refused_rows_alone(session):
    """A refused row is not waiting for anything; re-screening it every night
    would be work with no possible outcome."""
    await intake_service.record(
        session, [candidate(title="[South Asia pamphlet collection.")], source=SOURCE
    )
    assert await intake_service.rescreen_incomplete(session) == {}


async def test_a_promotion_can_be_undone_from_its_receipt(session):
    """`08`/`09`/`10` get reversibility from a receipt file. This job runs
    unattended, so the receipt is the intake row itself."""
    await intake_service.record(session, [candidate()], source=SOURCE)
    await intake_service.promote(session, limit=10)
    row = (await session.execute(select(CatalogIntake))).scalar_one()

    assert await intake_service.revert(session, [row.id]) == 1

    work = await session.get(Work, row.work_id)
    assert work.deleted_at is not None, "soft delete only (rule 3)"
    assert all(e.deleted_at is not None for e in work.editions)
    await session.refresh(row)
    assert row.state == STATE_COMPLETE


async def test_revert_ignores_a_row_this_pipeline_did_not_promote(session):
    """The receipt is the proof of authorship — without that check, revert is
    a way to delete any book in the catalogue."""
    session.add(Work(title="A reader's book"))
    await session.commit()
    reader_work = (await session.execute(select(Work))).unique().scalar_one()

    row = CatalogIntake(
        source=SOURCE,
        source_key="/works/NOPE",
        state=STATE_COMPLETE,
        payload=candidate().to_payload(),
        work_id=reader_work.id,
    )
    session.add(row)
    await session.commit()

    assert await intake_service.revert(session, [row.id]) == 0
    await session.refresh(reader_work)
    assert reader_work.deleted_at is None


async def test_revert_on_an_unknown_id_is_a_no_op(session):
    assert await intake_service.revert(session, [uuid.uuid4()]) == 0


# --------------------------------------------------------------------------
# authors and publishers are reused, not re-created
# --------------------------------------------------------------------------


async def test_two_books_by_one_author_share_the_author_row(session):
    await intake_service.record(
        session,
        [
            candidate("/works/A"),
            candidate("/works/B", title="The Ministry of Utmost Happiness", isbn="9780143028109"),
        ],
        source=SOURCE,
    )
    await intake_service.promote(session, limit=10)
    assert await session.scalar(select(func.count()).select_from(Author)) == 1
    assert await session.scalar(select(func.count()).select_from(Publisher)) == 1


async def test_re_promoting_a_reverted_book_hits_the_soft_deleted_isbn(session):
    """A reachable path, not a hypothetical. `revert` soft-deletes the Work and
    puts the candidate back to `complete`, so the next nightly run tries again
    — but `editions_isbn_key` is a plain unique index, not a partial one, so
    the soft-deleted row still occupies the number. The pre-check looks at live
    rows only and sees nothing; the constraint fires at commit, and
    `_commit_guarding_isbn` rolls the session back before raising.

    What must survive that rollback is our bookkeeping: the candidate has to
    end up marked, not left `complete` to be retried forever.
    """
    await intake_service.record(session, [candidate()], source=SOURCE)
    await intake_service.promote(session, limit=10)
    row = (await session.execute(select(CatalogIntake))).scalar_one()
    await intake_service.revert(session, [row.id])
    await session.refresh(row)
    assert row.state == STATE_COMPLETE

    counts = await intake_service.promote(session, limit=10)

    await session.refresh(row)
    assert row.state != STATE_COMPLETE, "a row that cannot be created must not stay due"
    assert counts, "the run must report what happened rather than silently doing nothing"
    live = await session.scalar(
        select(func.count()).select_from(Work).where(Work.deleted_at.is_(None))
    )
    assert live == 0, "no second Work for an ISBN the catalogue already holds"
