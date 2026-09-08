"""The shared recap page — `/reader/<handle>/recap/<key>`.

The page a share card links to (owner request, 8 Sep 2026: "if we share a month
card with link, others can see what all books he read in that month"). Two
things it must never get wrong: who it renders for, and whether its numbers
agree with the card that linked to it.
"""

import uuid
from datetime import UTC, date, datetime, timedelta

import pytest

from app.models import Author, Edition, LibraryEntry, Profile, ReadingSession, Work
from app.services import public_service, slug_service


async def _reader(db, *, username="shamshi", recaps=True, profile=True, offset=330) -> Profile:
    row = Profile(
        id=uuid.uuid4(),
        email=f"{username}@x.test",
        username=username,
        full_name="Shamshi",
        profile_visible=profile,
        recaps_visible=recaps,
        utc_offset_minutes=offset,
    )
    db.add(row)
    await db.commit()
    return row


async def _book(db, title: str) -> Edition:
    author = Author(name="Benyamin")
    db.add(author)
    await db.flush()
    await slug_service.ensure_slug(db, author)
    work = Work(title=title, authors=[author])
    db.add(work)
    await db.flush()
    edition = Edition(work_id=work.id)
    db.add(edition)
    await slug_service.ensure_slug(db, work, extras=[author.name])
    await db.commit()
    return edition


async def _finished(db, reader: Profile, edition: Edition, on: date) -> LibraryEntry:
    entry = LibraryEntry(
        id=uuid.uuid4(),
        user_id=reader.id,
        edition_id=edition.id,
        status="read",
        finish_date=on,
    )
    db.add(entry)
    await db.commit()
    return entry


async def _sitting(
    db, reader: Profile, entry: LibraryEntry, *, started: datetime, seconds: int, pages=(None, None)
) -> None:
    db.add(
        ReadingSession(
            id=uuid.uuid4(),
            user_id=reader.id,
            library_entry_id=entry.id,
            started_at=started,
            ended_at=started + timedelta(seconds=seconds),
            duration_seconds=seconds,
            page_start=pages[0],
            page_end=pages[1],
        )
    )
    await db.commit()


# --------------------------------------------------------------------------
# The gate
# --------------------------------------------------------------------------


async def test_a_reader_who_has_not_published_recaps_has_no_page(db_sessionmaker):
    """The link is *derived* from the handle and the window, so it is guessable
    by construction — the gate is what protects the reader, not the URL. Off
    until they turn it on, and 404 in a way that can't be told apart from a
    handle that was never registered."""
    async with db_sessionmaker() as db:
        await _reader(db, username="quiet", recaps=False)
        assert await public_service.reader_recap(db, "quiet", "2026-09") is None
        assert await public_service.reader_recap(db, "nobody", "2026-09") is None


async def test_a_private_profile_has_no_recap_even_with_recaps_on(db_sessionmaker):
    """Both flags, not either. Turning recaps on must not smuggle a profile the
    reader has hidden back onto the web."""
    async with db_sessionmaker() as db:
        await _reader(db, username="hidden", recaps=True, profile=False)
        assert await public_service.reader_recap(db, "hidden", "2026-09") is None


async def test_an_unparseable_key_is_the_same_404(db_sessionmaker):
    async with db_sessionmaker() as db:
        await _reader(db, username="open")
        assert await public_service.reader_recap(db, "open", "2026-13") is None
        assert await public_service.reader_recap(db, "open", "../secrets") is None


async def test_the_handle_is_case_insensitive(db_sessionmaker):
    async with db_sessionmaker() as db:
        await _reader(db, username="shamshi")
        assert await public_service.reader_recap(db, "ShAmShI", "2026-09") is not None


# --------------------------------------------------------------------------
# The numbers, and the books
# --------------------------------------------------------------------------


async def test_the_page_carries_the_books_finished_in_the_window(db_sessionmaker):
    """The reason a recipient follows the link at all."""
    async with db_sessionmaker() as db:
        reader = await _reader(db)
        september = await _book(db, "Aadujeevitham")
        august = await _book(db, "Khasakkinte Itihasam")
        await _finished(db, reader, september, date(2026, 9, 3))
        await _finished(db, reader, august, date(2026, 8, 30))

        page = await public_service.reader_recap(db, "shamshi", "2026-09")

    assert page is not None
    assert [b.title for b in page.books] == ["Aadujeevitham"]
    # ...and the card links onward into the catalogue, which is half the point
    # of a public page at all.
    assert page.books[0].slug


async def test_a_book_read_with_no_finish_date_still_counts(db_sessionmaker):
    """`finish_date ?? updated_at` is the rule the app itself counts by — a book
    marked read without one (an older row, a CSV import) would otherwise vanish
    from every window it could belong to, and the page would contradict the card
    that linked to it."""
    async with db_sessionmaker() as db:
        reader = await _reader(db)
        edition = await _book(db, "Randamoozham")
        entry = LibraryEntry(
            id=uuid.uuid4(),
            user_id=reader.id,
            edition_id=edition.id,
            status="read",
            finish_date=None,
        )
        db.add(entry)
        await db.commit()
        this_month = f"{entry.updated_at.year:04d}-{entry.updated_at.month:02d}"

        page = await public_service.reader_recap(db, "shamshi", this_month)

    assert page is not None
    assert [b.title for b in page.books] == ["Randamoozham"]


async def test_the_totals_are_the_windows_own_sittings(db_sessionmaker):
    async with db_sessionmaker() as db:
        reader = await _reader(db, offset=0)
        edition = await _book(db, "Aadujeevitham")
        entry = await _finished(db, reader, edition, date(2026, 9, 3))
        await _sitting(
            db,
            reader,
            entry,
            started=datetime(2026, 9, 2, 20, 0, tzinfo=UTC),
            seconds=3600,
            pages=(10, 60),
        )
        await _sitting(
            db,
            reader,
            entry,
            started=datetime(2026, 9, 3, 20, 0, tzinfo=UTC),
            seconds=1800,
            pages=(60, 90),
        )
        # Last month — must not be counted.
        await _sitting(
            db,
            reader,
            entry,
            started=datetime(2026, 8, 31, 20, 0, tzinfo=UTC),
            seconds=9999,
            pages=(1, 10),
        )

        page = await public_service.reader_recap(db, "shamshi", "2026-09")

    assert page is not None
    assert page.total_seconds == 5400
    assert page.sittings == 2
    assert page.pages_read == 80
    assert page.days_read == 2
    assert page.seconds_by_day == {"2026-09-02": 3600, "2026-09-03": 1800}
    # Printed as an inclusive last day: "1–30 September", never "to 1 October".
    assert (page.start, page.end) == (date(2026, 9, 1), date(2026, 9, 30))


async def test_a_sitting_with_no_pages_costs_nothing(db_sessionmaker):
    """Mirrors the app's `sessionPagesRead`: no range, or one that ended where
    it began, contributes nothing — never a negative."""
    async with db_sessionmaker() as db:
        reader = await _reader(db, offset=0)
        edition = await _book(db, "Aadujeevitham")
        entry = await _finished(db, reader, edition, date(2026, 9, 3))
        await _sitting(
            db, reader, entry, started=datetime(2026, 9, 2, 9, 0, tzinfo=UTC), seconds=600
        )
        await _sitting(
            db,
            reader,
            entry,
            started=datetime(2026, 9, 2, 10, 0, tzinfo=UTC),
            seconds=600,
            pages=(40, 40),
        )

        page = await public_service.reader_recap(db, "shamshi", "2026-09")

    assert page is not None
    assert page.pages_read == 0
    assert page.sittings == 2


async def test_a_late_night_sitting_belongs_to_the_readers_day_not_utcs(db_sessionmaker):
    """The whole reason `utc_offset_minutes` exists. 11pm IST on 30 September is
    17:30 UTC the same day — but 00:30 IST on 1 October is 19:00 UTC on the
    30th, and counting in UTC would file it under September on the page while
    the card that linked to it filed it under October."""
    async with db_sessionmaker() as db:
        reader = await _reader(db, offset=330)  # IST
        edition = await _book(db, "Aadujeevitham")
        entry = await _finished(db, reader, edition, date(2026, 9, 3))
        # 00:30 on 1 Oct, IST.
        await _sitting(
            db, reader, entry, started=datetime(2026, 9, 30, 19, 0, tzinfo=UTC), seconds=600
        )
        # 23:00 on 30 Sep, IST.
        await _sitting(
            db, reader, entry, started=datetime(2026, 9, 30, 17, 30, tzinfo=UTC), seconds=900
        )

        september = await public_service.reader_recap(db, "shamshi", "2026-09")
        october = await public_service.reader_recap(db, "shamshi", "2026-10")

    assert september is not None and october is not None
    assert september.seconds_by_day == {"2026-09-30": 900}
    assert october.seconds_by_day == {"2026-10-01": 600}


async def test_an_all_time_window_stops_at_today(db_sessionmaker):
    """`all` parses to an open-ended range; nobody has read tomorrow, and an end
    in 2100 would make every "days in the window" figure nonsense."""
    async with db_sessionmaker() as db:
        await _reader(db)
        page = await public_service.reader_recap(db, "shamshi", "all")

    assert page is not None
    assert page.end <= date.today() + timedelta(days=1)


@pytest.mark.parametrize(
    "key", ["2026-09-08", "2026-w37", "2026-09", "2026", "all", "90d-2026-09-08"]
)
async def test_every_window_the_app_can_share_has_a_page(db_sessionmaker, key):
    """Every window gets a link (owner decision, 8 Sep 2026), so every key the
    share sheet can print has to resolve — an empty window renders as an honest
    quiet page, not a 404."""
    async with db_sessionmaker() as db:
        await _reader(db)
        page = await public_service.reader_recap(db, "shamshi", key)
    assert page is not None
    assert page.key == key


async def test_the_endpoint_404s_the_same_way_the_service_does(client, db_sessionmaker):
    async with db_sessionmaker() as db:
        await _reader(db, username="open")
        await _reader(db, username="shy", recaps=False)

    assert (await client.get("/public/reader/open/recap/2026-09")).status_code == 200
    assert (await client.get("/public/reader/shy/recap/2026-09")).status_code == 404
    assert (await client.get("/public/reader/open/recap/2026-99")).status_code == 404
