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
        [
            candidate("/works/A"),
            # A different book — the same title and author would make this a
            # second printing of A, which is its own test further down.
            candidate("/works/B", title="The Ministry of Utmost Happiness", isbn="9780143028109"),
        ],
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


# --------------------------------------------------------------------------
# `already_catalogued` — the rule the preview script and the job must share
# --------------------------------------------------------------------------


async def test_already_catalogued_is_none_for_a_book_we_do_not_have(session):
    assert await intake_service.already_catalogued(session, candidate()) is None


async def test_already_catalogued_matches_on_the_same_upstream_record(session):
    session.add(Work(title="Seeded", external_source="openlibrary", external_id="/works/OL1W"))
    await session.commit()
    found = await intake_service.already_catalogued(session, candidate("/works/OL1W"))
    assert found is not None


async def test_already_catalogued_matches_on_isbn_from_a_different_upstream_record(session):
    """OpenLibrary carries duplicate work keys for popular books, so provenance
    alone would let the second one through."""
    await intake_service.record(session, [candidate("/works/FIRST")], source=SOURCE)
    await intake_service.promote(session, limit=1)

    found = await intake_service.already_catalogued(session, candidate("/works/SECOND"))
    assert found is not None


async def test_already_catalogued_recognises_the_other_isbn_spelling(session):
    """The catalogue may hold the ISBN-10 off an older printing while the
    candidate carries the 13 — two spellings of one printing."""
    await intake_service.record(session, [candidate()], source=SOURCE)
    await intake_service.promote(session, limit=1)
    edition = (await session.execute(select(Edition))).scalar_one()
    edition.isbn = "0060977493"  # the ISBN-10 of the same book
    await session.commit()

    found = await intake_service.already_catalogued(
        session, candidate("/works/OTHER", isbn="9780060977498")
    )
    assert found is not None


async def test_already_catalogued_ignores_a_soft_deleted_book(session):
    """A reverted book is gone as far as readers are concerned, so the preview
    must not report it as "already have" — the promotion path has its own guard
    for the number the deleted row still occupies."""
    await intake_service.record(session, [candidate()], source=SOURCE)
    await intake_service.promote(session, limit=1)
    row = (await session.execute(select(CatalogIntake))).scalar_one()
    await intake_service.revert(session, [row.id])

    assert await intake_service.already_catalogued(session, candidate()) is None


async def test_already_catalogued_writes_nothing(session):
    """It is called from a read-only session in `scripts/preview_intake.py`."""
    session.add(Work(title="Seeded", external_source="openlibrary", external_id="/works/OL1W"))
    await session.commit()
    before = await catalogue_size(session)
    for _ in range(3):
        await intake_service.already_catalogued(session, candidate())
    assert await catalogue_size(session) == before
    assert await session.scalar(select(func.count()).select_from(CatalogIntake)) == 0


async def test_a_shop_bundle_or_a_placeholder_isbn_never_becomes_a_book(session):
    """Owner, 3 Oct 2026: no book without a valid ISBN, and none whose name
    is not a book's. Staged — so the queue shows what was turned away and why
    — and never promoted."""
    await intake_service.record(
        session,
        [
            candidate("/works/COMBO", title="Madhavikutty 3 Book Combo"),
            candidate("/works/DUMMY", isbn="9781234567897"),
            candidate("/works/LABEL", title="Sapiens (Tamil Edition)", isbn="9780143039648"),
        ],
        source=SOURCE,
    )
    assert await intake_service.promote(session, limit=10) == {}
    assert await catalogue_size(session) == (0, 0)

    rows = {r.source_key: r for r in (await session.execute(select(CatalogIntake))).scalars()}
    assert rows["/works/COMBO"].state == STATE_REJECTED
    assert rows["/works/COMBO"].note == "refused: title_not_a_book"
    assert rows["/works/LABEL"].state == STATE_REJECTED
    assert rows["/works/DUMMY"].state == STATE_INCOMPLETE
    assert rows["/works/DUMMY"].note == "waiting on: isbn_invalid"


# --------------------------------------------------------------------------
# covers — a book is published with a cover we own, or it waits (P2)
# --------------------------------------------------------------------------

from app.core.config import get_settings  # noqa: E402
from app.services.cover_ingest import Ingested  # noqa: E402

R2 = "https://covers.kitabi.in"
PUBLISHER_COVER = "https://www.mbibooks.com/wp-content/uploads/front.jpg"
PUBLISHER_BACK = "https://www.mbibooks.com/wp-content/uploads/back.jpg"


def fake_covers(outcomes: dict[str, Ingested] | None = None):
    """Stands in for `cover_ingest.ingester(...)`: every URL is "stored" unless
    `outcomes` says otherwise. `.calls` is every URL it was asked for."""
    calls: list[str] = []

    async def run(url: str) -> Ingested:
        calls.append(url)
        if outcomes and url in outcomes:
            return outcomes[url]
        return Ingested(url=f"{R2}/catalog/{url.rsplit('/', 1)[-1]}")

    run.calls = calls
    return run


def no_fetch_expected():
    async def run(url: str) -> Ingested:
        raise AssertionError(f"this cover must not be fetched: {url}")

    return run


async def only_row(session) -> CatalogIntake:
    return (await session.execute(select(CatalogIntake))).scalar_one()


async def test_a_promoted_book_points_at_our_copy_of_its_cover(session):
    await intake_service.record(session, [candidate(cover_url=PUBLISHER_COVER)], source=SOURCE)
    covers = fake_covers()
    counts = await intake_service.promote(session, limit=10, covers=covers)

    assert counts == {STATE_PROMOTED: 1}
    row = await only_row(session)
    edition = await session.get(Edition, row.edition_id)
    assert edition.cover_url == f"{R2}/catalog/front.jpg"
    assert covers.calls == [PUBLISHER_COVER]
    # The payload stays what the source said: it is the record a re-crawl is
    # compared against, not a description of what we stored.
    assert row.payload["cover_url"] == PUBLISHER_COVER


async def test_an_openlibrary_cover_is_brought_home_too_once_there_is_storage(session):
    """With storage configured nothing is left hotlinked — the plan's "done
    when" is a promoted book served from our own bucket."""
    await intake_service.record(session, [candidate()], source=SOURCE)
    await intake_service.promote(session, limit=10, covers=fake_covers())
    edition = await session.get(Edition, (await only_row(session)).edition_id)
    assert edition.cover_url.startswith(f"{R2}/catalog/")


async def test_the_back_cover_is_ingested_alongside_the_front(session):
    await intake_service.record(
        session,
        [candidate(cover_url=PUBLISHER_COVER, back_cover_url=PUBLISHER_BACK)],
        source=SOURCE,
    )
    await intake_service.promote(session, limit=10, covers=fake_covers())
    edition = await session.get(Edition, (await only_row(session)).edition_id)
    assert edition.cover_url == f"{R2}/catalog/front.jpg"
    assert edition.back_cover_url == f"{R2}/catalog/back.jpg"


@pytest.mark.parametrize("verdict", [Ingested(gone=True), Ingested()], ids=["gone", "transient"])
async def test_a_back_cover_that_fails_never_holds_the_book(session, verdict):
    """A back cover is a bonus. Most books in the catalogue have none."""
    await intake_service.record(
        session,
        [candidate(cover_url=PUBLISHER_COVER, back_cover_url=PUBLISHER_BACK)],
        source=SOURCE,
    )
    counts = await intake_service.promote(
        session, limit=10, covers=fake_covers({PUBLISHER_BACK: verdict})
    )
    assert counts == {STATE_PROMOTED: 1}
    edition = await session.get(Edition, (await only_row(session)).edition_id)
    assert edition.cover_url == f"{R2}/catalog/front.jpg"
    assert edition.back_cover_url is None


async def test_an_unusable_cover_sends_the_candidate_back_and_creates_nothing(session):
    await intake_service.record(session, [candidate(cover_url=PUBLISHER_COVER)], source=SOURCE)
    counts = await intake_service.promote(
        session,
        limit=10,
        covers=fake_covers({PUBLISHER_COVER: Ingested(gone=True, reason="too small")}),
    )

    assert counts == {"cover_unusable": 1}
    assert await catalogue_size(session) == (0, 0)
    row = await only_row(session)
    assert row.state == STATE_INCOMPLETE
    assert row.missing == ["cover_url"]
    assert "too small" in row.note
    assert row.attempts == 0  # nothing transient happened; this is a verdict


async def test_a_dead_cover_is_not_walked_back_into_the_queue_by_the_next_crawl(session):
    """The loop this exists to prevent: the source still lists the same dead
    image tomorrow, the gate sees a cover again, and the book costs a fetch and
    a promotion slot every night, forever."""
    dead = fake_covers({PUBLISHER_COVER: Ingested(gone=True, reason="404")})
    await intake_service.record(session, [candidate(cover_url=PUBLISHER_COVER)], source=SOURCE)
    await intake_service.promote(session, limit=10, covers=dead)
    assert dead.calls == [PUBLISHER_COVER]

    # The nightly job, again: re-crawl (same URL), re-screen, promote.
    await intake_service.record(session, [candidate(cover_url=PUBLISHER_COVER)], source=SOURCE)
    await intake_service.rescreen_incomplete(session)
    counts = await intake_service.promote(session, limit=10, covers=dead)

    assert counts == {}
    assert dead.calls == [PUBLISHER_COVER]  # not asked for a second time
    row = await only_row(session)
    assert row.state == STATE_INCOMPLETE
    assert "unusable" in row.note


async def test_a_new_cover_from_the_source_releases_a_book_held_for_a_dead_one(session):
    """ "Missing" means another source — or the same one, later — may fill it."""
    replacement = "https://www.mbibooks.com/wp-content/uploads/front-v2.jpg"
    covers = fake_covers({PUBLISHER_COVER: Ingested(gone=True, reason="404")})
    await intake_service.record(session, [candidate(cover_url=PUBLISHER_COVER)], source=SOURCE)
    await intake_service.promote(session, limit=10, covers=covers)

    await intake_service.record(session, [candidate(cover_url=replacement)], source=SOURCE)
    counts = await intake_service.promote(session, limit=10, covers=covers)

    assert counts == {STATE_PROMOTED: 1}
    edition = await session.get(Edition, (await only_row(session)).edition_id)
    assert edition.cover_url == f"{R2}/catalog/front-v2.jpg"


async def test_a_cover_we_could_not_fetch_tonight_is_tried_again_tomorrow(session):
    await intake_service.record(session, [candidate(cover_url=PUBLISHER_COVER)], source=SOURCE)
    counts = await intake_service.promote(
        session, limit=10, covers=fake_covers({PUBLISHER_COVER: Ingested(reason="timeout")})
    )

    assert counts == {"cover_retry": 1}
    assert await catalogue_size(session) == (0, 0)
    row = await only_row(session)
    assert row.state == STATE_COMPLETE  # still due
    assert row.attempts == 1
    assert row.payload["cover_url"] == PUBLISHER_COVER  # and still has its cover

    assert await intake_service.promote(session, limit=10, covers=fake_covers()) == {
        STATE_PROMOTED: 1
    }


async def test_a_source_that_is_down_ends_the_run_instead_of_charging_every_row(session):
    """Five in a row is an outage, not five bad covers. Pushing on would spend
    an attempt on every remaining book for something that is not its fault."""
    books = [
        candidate(f"/works/OL{n}W", isbn=isbn, cover_url=f"https://www.mbibooks.com/{n}.jpg")
        for n, isbn in enumerate(
            [
                "9780060977498",
                "9780143039648",
                "9780140283297",
                "9780679722649",
                "9780099578512",
                "9780143031031",
                "9780007350834",
            ]
        )
    ]
    await intake_service.record(session, books, source=SOURCE)
    down = fake_covers({c.cover_url: Ingested(reason="timeout") for c in books})

    counts = await intake_service.promote(session, limit=10, covers=down)

    assert counts == {"cover_retry": intake_service.MAX_CONSECUTIVE_COVER_FAILURES}
    rows = (await session.execute(select(CatalogIntake))).scalars().all()
    assert sorted(r.attempts for r in rows) == [0, 0, 1, 1, 1, 1, 1]


async def test_without_storage_a_publisher_cover_waits_rather_than_being_hotlinked(session):
    """No R2 keys must not mean "publish it pointing at the publisher's site":
    that is a host the edge proxy and the app have never been told about, at
    ~600 KB an image."""
    await intake_service.record(session, [candidate(cover_url=PUBLISHER_COVER)], source=SOURCE)
    counts = await intake_service.promote(session, limit=10, covers=None)

    assert counts == {"held": 1}
    assert await catalogue_size(session) == (0, 0)
    row = await only_row(session)
    assert row.state == STATE_COMPLETE  # nothing is wrong with the book
    assert row.attempts == 0  # and waiting on our configuration costs it nothing
    assert row.note == intake_service.NOTE_NO_COVER_STORAGE

    # The moment storage exists, the same row goes through.
    assert await intake_service.promote(session, limit=10, covers=fake_covers()) == {
        STATE_PROMOTED: 1
    }


async def test_without_storage_an_unservable_back_cover_is_dropped_not_hotlinked(session):
    await intake_service.record(session, [candidate(back_cover_url=PUBLISHER_BACK)], source=SOURCE)
    assert await intake_service.promote(session, limit=10) == {STATE_PROMOTED: 1}
    edition = await session.get(Edition, (await only_row(session)).edition_id)
    assert edition.cover_url == "https://covers.openlibrary.org/b/id/1-L.jpg"
    assert edition.back_cover_url is None


async def test_a_book_we_already_hold_never_costs_a_cover_fetch(session):
    """The duplicate check runs first, so re-discovering the catalogue does not
    re-download it or leave orphans in the bucket."""
    await intake_service.record(session, [candidate()], source=SOURCE)
    await intake_service.promote(session, limit=10)
    await intake_service.record(session, [candidate("/works/OL2W")], source=SOURCE)

    counts = await intake_service.promote(session, limit=10, covers=no_fetch_expected())
    assert counts == {STATE_DUPLICATE: 1}


async def test_a_cover_already_in_our_bucket_is_not_fetched_again(session, monkeypatch):
    settings = get_settings().model_copy(update={"r2_covers_public_url": R2})
    monkeypatch.setattr("app.services.intake_service.get_settings", lambda: settings)
    ours = f"{R2}/catalog/abc.jpg"
    await intake_service.record(session, [candidate(cover_url=ours)], source=SOURCE)

    counts = await intake_service.promote(session, limit=10, covers=no_fetch_expected())
    assert counts == {STATE_PROMOTED: 1}
    edition = await session.get(Edition, (await only_row(session)).edition_id)
    assert edition.cover_url == ours


# --------------------------------------------------------------------------
# a re-crawl, a book's own page, and new releases (storefronts, 3 Oct 2026)
# --------------------------------------------------------------------------


async def test_a_blank_in_tonights_crawl_does_not_erase_last_nights_answer(session):
    """A shop drops a cover while it re-uploads it; a feed page comes back
    without the attribute it carried yesterday. "Not told" is not "no longer
    true"."""
    await intake_service.record(session, [candidate(page_count=320)], source=SOURCE)
    await intake_service.record(
        session, [candidate(cover_url=None, page_count=None)], source=SOURCE
    )
    row = await only_row(session)
    assert row.state == STATE_COMPLETE
    assert row.payload["cover_url"] == "https://covers.openlibrary.org/b/id/1-L.jpg"
    assert row.payload["page_count"] == 320


async def test_a_changed_value_in_tonights_crawl_does_replace_the_old_one(session):
    await intake_service.record(session, [candidate(page_count=320)], source=SOURCE)
    await intake_service.record(session, [candidate(page_count=336)], source=SOURCE)
    assert (await only_row(session)).payload["page_count"] == 336


async def test_what_the_page_said_outranks_the_feed_and_survives_rescreening(session):
    await intake_service.record(
        session, [candidate(title="Spinosaurus", authors=(), isbn=None)], source=SOURCE
    )
    row = await only_row(session)
    state = intake_service.apply_page_facts(
        row, {"title": "The Real Title", "authors": ["Arundhati Roy"], "isbn": "9780060977498"}
    )
    await session.commit()
    assert state == STATE_COMPLETE

    # The nightly crawl again, then the nightly re-screen.
    await intake_service.record(
        session, [candidate(title="Spinosaurus", authors=(), isbn=None)], source=SOURCE
    )
    await intake_service.rescreen_incomplete(session)

    row = await only_row(session)
    assert row.state == STATE_COMPLETE
    assert row.payload["title"] == "The Real Title"
    assert row.payload["authors"] == ["Arundhati Roy"]
    assert row.payload[intake_service.PAGE_READ_KEY] is True


async def test_new_releases_are_published_ahead_of_the_backlog(session):
    """Owner, 3 Oct 2026: "new release should be there in our db". Without
    this a book out this week waits behind every backlist title staged before
    it — months, at the daily limit."""
    # Two nights' backlist, then tonight's newest page.
    await intake_service.record(
        session,
        [candidate("/works/OLD1", title="Backlist One", isbn="9780143028109")],
        source=SOURCE,
    )
    await intake_service.record(
        session,
        [candidate("/works/OLD2", title="Backlist Two", isbn="9780140283297")],
        source=SOURCE,
    )
    await intake_service.record(
        session, [candidate("/works/NEW", title="Out This Week")], source=SOURCE, fresh=True
    )

    assert await intake_service.promote(session, limit=1) == {STATE_PROMOTED: 1}
    titles = [w.title for w in (await session.execute(select(Work))).scalars()]
    assert titles == ["Out This Week"]

    # …and the backlog still drains, in the order it was found.
    await intake_service.promote(session, limit=1)
    titles = {w.title for w in (await session.execute(select(Work))).scalars()}
    assert titles == {"Out This Week", "Backlist One"}


async def test_seeing_a_staged_book_on_the_newest_page_does_not_make_it_new(session):
    await intake_service.record(session, [candidate(isbn=None)], source=SOURCE)
    await intake_service.record(session, [candidate()], source=SOURCE, fresh=True)
    assert intake_service.FRESH_KEY not in (await only_row(session)).payload


async def test_a_second_printing_is_added_to_the_book_not_published_as_another(session):
    """A storefront lists the hardback and the paperback as two products. Two
    Works for one book is rule 17 broken at the door."""
    await intake_service.record(
        session,
        [
            candidate("/works/HB", format="Hardback"),
            candidate("/works/PB", isbn="9780143028109", format="Paperback", page_count=340),
        ],
        source=SOURCE,
    )
    counts = await intake_service.promote(session, limit=10)

    assert counts == {STATE_PROMOTED: 1, "printing": 1}
    assert await catalogue_size(session) == (1, 2)
    rows = {r.source_key: r for r in (await session.execute(select(CatalogIntake))).scalars()}
    assert rows["/works/PB"].state == STATE_PROMOTED
    assert rows["/works/PB"].work_id == rows["/works/HB"].work_id
    assert rows["/works/PB"].edition_id != rows["/works/HB"].edition_id
    editions = (await session.execute(select(Edition))).scalars().all()
    # …each keeping its own format, folded to the catalogue's spelling.
    assert {e.format for e in editions} == {"Hardcover", "Paperback"}


async def test_a_shortened_author_name_is_still_the_same_author(session):
    """`Scott Fitzgerald` for `F. Scott Fitzgerald` — a real row,
    harpercollins.co.in, 3 Oct 2026."""
    await intake_service.record(
        session,
        [
            candidate("/works/A", title="The Great Gatsby", authors=("F. Scott Fitzgerald",)),
            candidate(
                "/works/B",
                title="The Great Gatsby",
                authors=("Scott Fitzgerald",),
                isbn="9780143028109",
            ),
        ],
        source=SOURCE,
    )
    assert await intake_service.promote(session, limit=10) == {STATE_PROMOTED: 1, "printing": 1}
    assert await session.scalar(select(func.count()).select_from(Author)) == 1


async def test_the_same_title_by_someone_else_is_held_for_a_person(session):
    """It may be our book under a differently spelled author, or a different
    book that shares a title. Both wrong guesses leave a record someone has to
    repair, so the job makes neither — and fetches no cover for it."""
    await intake_service.record(session, [candidate("/works/A")], source=SOURCE)
    await intake_service.promote(session, limit=10)
    await intake_service.record(
        session,
        [candidate("/works/B", authors=("Somebody Else",), isbn="9780143028109")],
        source=SOURCE,
    )

    counts = await intake_service.promote(session, limit=10, covers=no_fetch_expected())

    assert counts == {"held_duplicate": 1}
    assert await catalogue_size(session) == (1, 1)
    rows = {r.source_key: r for r in (await session.execute(select(CatalogIntake))).scalars()}
    held = rows["/works/B"]
    assert held.state == STATE_INCOMPLETE
    assert held.missing == [intake_service.HELD_POSSIBLE_DUPLICATE]
    assert str(rows["/works/A"].work_id) in held.note

    # And it stays held: the nightly crawl and re-screen do not release it.
    await intake_service.record(
        session,
        [candidate("/works/B", authors=("Somebody Else",), isbn="9780143028109")],
        source=SOURCE,
    )
    await intake_service.rescreen_incomplete(session)
    assert await intake_service.promote(session, limit=10, covers=no_fetch_expected()) == {}
    await session.refresh(held)
    assert held.state == STATE_INCOMPLETE


async def test_the_same_title_in_another_language_is_its_own_book(session):
    """A translation is a Work of its own, not a printing of the original."""
    await intake_service.record(
        session,
        [
            candidate("/works/EN"),
            candidate("/works/FR", language="French", isbn="9780143028109"),
        ],
        source=SOURCE,
    )
    assert await intake_service.promote(session, limit=10) == {STATE_PROMOTED: 2}
    assert await catalogue_size(session) == (2, 2)


async def _author(session, name: str) -> Author:
    author = Author(name=name)
    session.add(author)
    await session.commit()
    return author


@pytest.mark.parametrize(
    "as_the_shop_wrote_it",
    ["Shakespeare William", "SHAKESPEARE, William", "William Shakespeare."],
)
async def test_an_author_we_already_have_is_credited_under_the_name_we_have(
    session, as_the_shop_wrote_it
):
    """`Shakespeare William` was in the first preview of a real night
    (harpercollins.co.in, 4 Oct 2026). Published as written it is a second
    author row, and a second author page, for someone the catalogue holds."""
    known = await _author(session, "William Shakespeare")
    await intake_service.record(
        session,
        [candidate(title="Othello", authors=(as_the_shop_wrote_it,))],
        source=SOURCE,
    )
    assert await intake_service.promote(session, limit=10) == {STATE_PROMOTED: 1}

    work = (await session.execute(select(Work))).scalar_one()
    assert [a.id for a in work.authors] == [known.id]
    assert await session.scalar(select(func.count()).select_from(Author)) == 1


async def test_a_shortened_name_is_credited_to_the_full_one(session):
    known = await _author(session, "F. Scott Fitzgerald")
    await intake_service.record(
        session,
        [candidate(title="Tender Is the Night", authors=("Scott Fitzgerald",))],
        source=SOURCE,
    )
    await intake_service.promote(session, limit=10)
    work = (await session.execute(select(Work))).scalar_one()
    assert [a.id for a in work.authors] == [known.id]


async def test_a_name_that_could_be_two_people_is_left_as_the_source_wrote_it(session):
    """Two existing authors match; choosing between them is a person's call."""
    await _author(session, "Anita Desai")
    await _author(session, "Anita K. Desai")
    assert await intake_service.catalogue_spelling(session, "Desai Anita") == "Anita Desai"
    assert await intake_service.catalogue_spelling(session, "A. Desai") == "A. Desai"
    await _author(session, "Desai Anita K")
    # "K Anita Desai" now reorders to two different rows.
    assert await intake_service.catalogue_spelling(session, "K Anita Desai") == "K Anita Desai"


async def test_an_unknown_or_single_word_name_is_not_touched(session):
    await _author(session, "Osho")
    assert await intake_service.catalogue_spelling(session, "Osho") == "Osho"
    assert await intake_service.catalogue_spelling(session, "Someone New") == "Someone New"


async def test_a_night_of_new_releases_is_shared_between_the_sources(session):
    """Every shop's newest page is staged in the same minute. Without taking
    turns, the shop read last fills the night and the first fifty books are
    all from one publisher."""
    isbns = iter(
        ["9780060977498", "9780143039648", "9780140283297", "9780679722649", "9780099578512"]
        + ["9780143031031", "9780007350834", "9780143028109"]
    )
    for source, count in (("shop_a", 5), ("shop_b", 3)):
        await intake_service.record(
            session,
            [
                candidate(
                    f"{source}/{n}", source=source, title=f"{source} book {n}", isbn=next(isbns)
                )
                for n in range(count)
            ],
            source=source,
            fresh=True,
        )

    assert await intake_service.promote(session, limit=4) == {STATE_PROMOTED: 4}
    promoted = (
        (await session.execute(select(CatalogIntake).where(CatalogIntake.state == STATE_PROMOTED)))
        .scalars()
        .all()
    )
    assert sorted(r.source for r in promoted) == ["shop_a", "shop_a", "shop_b", "shop_b"]


async def test_undoing_a_printing_leaves_the_book_it_joined_standing(session):
    """A printing row's `work_id` names a book this pipeline did not create —
    possibly one with readers' shelves and reviews on it. Undoing the printing
    takes that one edition and nothing else."""
    await intake_service.record(session, [candidate("/works/HB")], source=SOURCE)
    await intake_service.promote(session, limit=10)
    await intake_service.record(
        session, [candidate("/works/PB", isbn="9780143028109")], source=SOURCE
    )
    assert await intake_service.promote(session, limit=10) == {"printing": 1}
    rows = {r.source_key: r for r in (await session.execute(select(CatalogIntake))).scalars()}
    printing = rows["/works/PB"]

    assert await intake_service.revert(session, [printing.id]) == 1

    work = await session.get(Work, rows["/works/HB"].work_id)
    await session.refresh(work)
    assert work.deleted_at is None, "the book the printing joined must survive"
    first = await session.get(Edition, rows["/works/HB"].edition_id)
    second = await session.get(Edition, printing.edition_id)
    await session.refresh(first)
    await session.refresh(second)
    assert first.deleted_at is None
    assert second.deleted_at is not None
    await session.refresh(printing)
    assert printing.state == STATE_COMPLETE
    assert intake_service.PRINTING_KEY not in printing.payload
