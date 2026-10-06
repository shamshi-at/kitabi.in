"""Kerala Book Store: the multi-publisher Malayalam retailer (6 Oct 2026).

The fixtures are real — a book page and the sitemap, saved from the shop and
trimmed (`tests/fixtures/keralabookstore/`) — for the reason every storefront
test says: markup written from the parser proves only that the code agrees with
itself. If the shop changes its template these keep passing while production
stops finding authors; the signal for that is the intake queue, not this file.

What is pinned:

- the page's fields *mean* what the adapter says (the title and author are the
  Malayalam ones, the publisher is the retailer's name for the house);
- a number the shop mints for books it has no ISBN for is not an ISBN;
- the job reads nothing — not even the sitemap — until it is switched on;
- it asks `robots.txt` first and every page again, and only from the shop's own
  host, at the shop's stated pace;
- the newest unstaged pages come first, and a page that is gone is staged once
  rather than asked about every night.

No network: `httpx.MockTransport`.
"""

from pathlib import Path

import httpx
import pytest
from sqlalchemy import select

from app.core.config import get_settings
from app.jobs import catalog_intake as intake_job
from app.models import Author, CatalogIntake, Work
from app.models.catalog_intake import STATE_COMPLETE, STATE_PROMOTED
from app.services import intake_keralabookstore as kbs
from app.services import intake_service
from app.services.cover_ingest import Ingested
from app.services.intake_gate import screen

FIXTURES = Path(__file__).parent / "fixtures" / "keralabookstore"
BOOK_URL = "https://keralabookstore.com/book/thirikevaranavatha-patha/1007620/"


def book_page() -> str:
    return (FIXTURES / "book_malayalam.html").read_text()


def sitemap() -> str:
    return (FIXTURES / "sitemap.xml").read_text()


def fake_covers():
    """Stands in for the R2 ingester: every cover is "stored" under our bucket,
    and `.calls` is every URL it was asked to bring home."""
    calls: list[str] = []

    async def run(url: str) -> Ingested:
        calls.append(url)
        return Ingested(url=f"https://covers.kitabi.in/catalog/{url.rsplit('/', 1)[-1]}")

    run.calls = calls
    return run


@pytest.fixture
async def session(db_sessionmaker):
    async with db_sessionmaker() as s:
        yield s


# --------------------------------------------------------------------------
# the sitemap
# --------------------------------------------------------------------------


def test_the_sitemap_lists_book_pages_newest_first_and_nothing_else():
    found = kbs.parse_sitemap(sitemap())
    ids = [listing.book_id for listing in found]
    assert ids == [1007625, 1007624, 1007623, 1007622, 3, 2, 1], "highest id is the newest book"
    assert all(listing.url.startswith("https://keralabookstore.com/book/") for listing in found)
    assert "new-books.do" not in "".join(listing.url for listing in found)


def test_a_url_on_another_host_is_not_a_book_page():
    xml = (
        "<urlset>"
        "<url><loc>https://evil.example/book/x/9/</loc></url>"
        "<url><loc>https://keralabookstore.com.evil.example/book/x/8/</loc></url>"
        "<url><loc>http://keralabookstore.com/book/x/7/</loc></url>"
        "<url><loc>https://keralabookstore.com/book/x/6/</loc></url>"
        "</urlset>"
    )
    assert [listing.book_id for listing in kbs.parse_sitemap(xml)] == [6]
    assert kbs.owns("https://keralabookstore.com/book/x/6/")
    assert not kbs.owns("https://evil.example/book/x/6/")
    assert not kbs.owns("http://keralabookstore.com/book/x/6/")


def test_the_next_pages_are_the_newest_ones_not_yet_staged():
    found = kbs.parse_sitemap(sitemap())
    todo = kbs.unstaged(found, staged={1007625, 1007623, 2}, limit=3)
    assert [listing.book_id for listing in todo] == [1007624, 1007622, 3]
    assert kbs.unstaged(found, staged={listing.book_id for listing in found}, limit=5) == []


# --------------------------------------------------------------------------
# a page
# --------------------------------------------------------------------------


def test_a_book_page_is_a_complete_record_in_the_books_own_script():
    book = kbs.parse_page(book_page(), BOOK_URL, 1007620)

    assert book.title == "തിരികെവരാനാവാത്ത പാത"
    assert book.authors == ("ഗോപാലകൃഷ്ണൻ എം പി",)
    assert book.publisher == "Mathrubhumi Books"
    assert book.isbn == "9789376881185"
    assert book.language == "Malayalam"
    assert book.page_count == 337
    assert book.format == "Paperback"
    assert book.cover_url == (
        "https://d1af37c1pl2nfl.cloudfront.net/images/books/mbb/front/thirikevaranavatha-patha.jpg"
    )
    assert (book.source, book.source_key, book.external_source, book.external_id) == (
        "keralabookstore",
        "1007620",
        "keralabookstore",
        "1007620",
    )
    assert book.source_url == BOOK_URL


def test_one_page_passes_the_gate_untouched():
    """The whole point of the source: nothing is missing, so nothing waits for
    a second request — including the title in its own script."""
    result = screen(kbs.parse_page(book_page(), BOOK_URL, 1007620))
    assert result.ok, (result.missing, result.fatal)
    assert result.dropped == ()


def test_the_blurb_is_the_blurb_and_not_the_shops_label():
    book = kbs.parse_page(book_page(), BOOK_URL, 1007620)
    assert book.description.startswith("ഇവിടെ കേരളത്തിലിരുന്ന്")
    assert "Book Name in English" not in book.description
    assert "Thirikevaranavatha" not in book.description
    assert book.description.rstrip().endswith("കെ.കെ. മാരാര്‍"), "the quote the shop prints is kept"


@pytest.mark.parametrize("placeholder", ["9780000140975", "9780000103932", "9780000000002"])
def test_a_number_the_shop_mints_for_a_book_it_has_no_isbn_for_is_not_an_isbn(placeholder):
    """Each of these has a correct check digit — the gate's checksum alone would
    publish the book under a number no book has."""
    page = book_page().replace("9789376881185", placeholder)
    book = kbs.parse_page(page, BOOK_URL, 1007620)
    assert book.isbn is None
    result = screen(book)
    assert result.missing == ("isbn",), "reported as the honest gap, not accepted"


def test_a_real_indian_isbn_that_merely_starts_with_zeros_later_is_kept():
    page = book_page().replace("9789376881185", "9788100000001")
    assert kbs.parse_page(page, BOOK_URL, 1).isbn == "9788100000001"


def test_a_page_that_is_not_a_book_page_is_an_empty_candidate_not_an_error():
    book = kbs.parse_page("<html><body>Not found</body></html>", BOOK_URL, 5)
    assert book.title == "" and book.authors == () and book.isbn is None
    assert screen(book).missing, "the gate says what is missing"


def test_several_authors_on_the_page_are_several_authors():
    page = book_page().replace(
        '<h2 tabindex="0" itemprop="author" itemscope itemtype="http://schema.org/Person">'
        '<span itemprop="name">ഗോപാലകൃഷ്ണൻ എം പി</span>',
        '<h2 tabindex="0" itemprop="author" itemscope itemtype="http://schema.org/Person">'
        '<span itemprop="name">ഗോപാലകൃഷ്ണൻ എം പി</span></h2>'
        '<h2 tabindex="0" itemprop="author" itemscope itemtype="http://schema.org/Person">'
        '<span itemprop="name">സിന്ധു കെ വി</span>',
    )
    assert kbs.parse_page(page, BOOK_URL, 1).authors == ("ഗോപാലകൃഷ്ണൻ എം പി", "സിന്ധു കെ വി")


def test_an_english_book_does_not_get_a_malayalam_script_author():
    """The first preview (6 Oct 2026) showed it: the shop writes every author in
    Malayalam, English books' included, and the catalogue spells an English
    book's author in Latin. Taking the name would be a second author row for
    someone who writes in English — so the book waits for a source that has it."""
    page = (FIXTURES / "book_english.html").read_text()
    book = kbs.parse_page(page, "https://keralabookstore.com/book/dhanushkodi/1007625/", 1007625)
    assert book.title == "Dhanushkodi When the Sea Came Ashore"
    assert book.language == "English"
    assert book.authors == ()
    result = screen(book)
    assert result.missing == ("authors",), (result.missing, result.fatal)


def test_a_malayalam_book_keeps_its_author_whatever_script_the_name_is_in():
    page = book_page().replace("ഗോപാലകൃഷ്ണൻ എം പി", "Gopalakrishnan M P")
    assert kbs.parse_page(page, BOOK_URL, 1).authors == ("Gopalakrishnan M P",)
    assert kbs.parse_page(book_page(), BOOK_URL, 1).authors == ("ഗോപാലകൃഷ്ണൻ എം പി",)


def test_an_english_book_with_an_author_in_latin_letters_keeps_it():
    page = (
        (FIXTURES / "book_english.html")
        .read_text()
        .replace("മാത്യു ജോസഫ് തെക്കേമുറിയിൽ", "Mathew Joseph Thekkemuriyil")
    )
    book = kbs.parse_page(page, "https://keralabookstore.com/book/x/1/", 1)
    assert book.authors == ("Mathew Joseph Thekkemuriyil",)


# --------------------------------------------------------------------------
# reading pages
# --------------------------------------------------------------------------


def _client(pages: dict[str, httpx.Response], seen: list[str]) -> httpx.AsyncClient:
    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(str(request.url))
        return pages.get(str(request.url), httpx.Response(404))

    return httpx.AsyncClient(transport=httpx.MockTransport(handler))


async def test_pages_are_read_in_order_and_only_from_the_shops_own_host():
    seen: list[str] = []
    ok = httpx.Response(200, text=book_page())
    todo = [
        kbs.Listing(1007620, BOOK_URL),
        kbs.Listing(7, "https://evil.example/book/x/7/"),
        kbs.Listing(1007621, "https://keralabookstore.com/book/y/1007621/"),
    ]
    pages = {BOOK_URL: ok, "https://keralabookstore.com/book/y/1007621/": ok}
    async with _client(pages, seen) as client:
        out = await kbs.read_pages(client, todo, pause=0)
    assert seen == [BOOK_URL, "https://keralabookstore.com/book/y/1007621/"]
    assert [c.source_key for c in out] == ["1007620", "1007621"]


async def test_robots_txt_is_asked_about_each_page():
    seen: list[str] = []
    ok = httpx.Response(200, text=book_page())
    todo = [kbs.Listing(1, BOOK_URL), kbs.Listing(2, "https://keralabookstore.com/book/y/2/")]
    async with _client({BOOK_URL: ok}, seen) as client:
        out = await kbs.read_pages(client, todo, may_fetch=lambda url: url == BOOK_URL, pause=0)
    assert seen == [BOOK_URL], "the page robots.txt forbids was never requested"
    assert len(out) == 1


async def test_the_shops_own_pace_is_the_default():
    """Ten seconds is the delay the shop's robots.txt states for the bots it
    names; it names none of us, and ten is still the pace."""
    assert kbs.PAUSE_SECONDS == 10.0


async def test_a_page_that_is_gone_is_staged_once_so_no_night_asks_again():
    seen: list[str] = []
    gone = "https://keralabookstore.com/book/gone/9/"
    async with _client({}, seen) as client:
        out = await kbs.read_pages(client, [kbs.Listing(9, gone)], pause=0)
    (dead,) = out
    assert dead.source_key == "9" and dead.title == ""
    assert screen(dead).missing, "held for a title, which is what keeps it from being asked again"


async def test_a_refused_page_is_left_unstaged_and_four_failures_end_the_night():
    seen: list[str] = []
    urls = [f"https://keralabookstore.com/book/x/{i}/" for i in range(10, 0, -1)]
    pages = {u: httpx.Response(503) for u in urls}
    async with _client(pages, seen) as client:
        out = await kbs.read_pages(
            client,
            [kbs.Listing(i, u) for i, u in zip(range(10, 0, -1), urls, strict=False)],
            pause=0,
        )
    assert out == []
    assert len(seen) == kbs.MAX_CONSECUTIVE_FAILURES, "a shop that stopped answering is left alone"

    seen.clear()
    forbidden = {urls[0]: httpx.Response(403), urls[1]: httpx.Response(200, text=book_page())}
    async with _client(forbidden, seen) as client:
        out = await kbs.read_pages(
            client, [kbs.Listing(10, urls[0]), kbs.Listing(9, urls[1])], pause=0
        )
    assert [c.source_key for c in out] == [
        "9"
    ], "a 403 costs that page, not the night, and is not staged"


async def test_the_sitemap_is_read_or_reported_unreadable():
    async with _client({kbs.SITEMAP_URL: httpx.Response(200, text=sitemap())}, []) as client:
        found = await kbs.listings(client)
    assert found and found[0].book_id == 1007625
    async with _client({kbs.SITEMAP_URL: httpx.Response(503)}, []) as client:
        assert await kbs.listings(client) is None


# --------------------------------------------------------------------------
# staging and publishing
# --------------------------------------------------------------------------


async def test_a_staged_page_is_complete_and_publishes_with_its_native_title_and_author(session):
    book = kbs.parse_page(book_page(), BOOK_URL, 1007620)
    await intake_service.record(session, [book], source=kbs.SOURCE)
    row = (await session.execute(select(CatalogIntake))).scalar_one()
    assert row.state == STATE_COMPLETE and row.missing is None

    covers = fake_covers()
    counts = await intake_service.promote(session, limit=10, covers=covers)
    assert counts == {STATE_PROMOTED: 1}
    assert covers.calls == [book.cover_url], "the shop's cover is brought home, not hotlinked"
    work = (await session.execute(select(Work))).scalar_one()
    assert work.title == "തിരികെവരാനാവാത്ത പാത" and work.language == "Malayalam"
    assert (work.external_source, work.external_id) == ("keralabookstore", "1007620")
    assert (await session.execute(select(Author.name))).scalars().all() == ["ഗോപാലകൃഷ്ണൻ എം പി"]


async def test_the_ids_already_staged_are_what_the_next_night_skips(session):
    book = kbs.parse_page(book_page(), BOOK_URL, 1007620)
    await intake_service.record(session, [book], source=kbs.SOURCE)
    await intake_service.record(
        session, [kbs.parse_page("", "https://keralabookstore.com/book/x/9/", 9)], source=kbs.SOURCE
    )
    assert await kbs.staged_ids(session) == {1007620, 9}
    # Another source's rows are not this shop's pages, whatever their keys look like.
    other = kbs.parse_page(book_page(), BOOK_URL, 42)
    from dataclasses import replace

    await intake_service.record(
        session, [replace(other, source="mathrubhumi")], source="mathrubhumi"
    )
    assert await kbs.staged_ids(session) == {1007620, 9}


# --------------------------------------------------------------------------
# the job: off unless asked
# --------------------------------------------------------------------------


def _shop_transport(seen: list[str]):
    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        seen.append(url)
        if request.url.host != "keralabookstore.com":
            raise AssertionError(f"the job reached a host nobody expected: {request.url.host}")
        if url.endswith("/robots.txt"):
            return httpx.Response(200, text="User-agent: SemrushBot\nDisallow: /\n")
        if url == kbs.SITEMAP_URL:
            return httpx.Response(200, text=sitemap())
        if url.endswith("/1007625/") or url.endswith("/1007624/"):
            return httpx.Response(200, text=book_page())
        return httpx.Response(404)

    return httpx.MockTransport(handler)


async def test_the_job_reads_nothing_from_the_shop_until_it_is_switched_on(
    session,
):
    settings = get_settings().model_copy(update={"catalog_intake_keralabookstore_pages": 0})
    assert settings.catalog_intake_keralabookstore_pages == 0
    seen: list[str] = []
    async with httpx.AsyncClient(transport=_shop_transport(seen)) as client:
        await intake_job._keralabookstore(session, client, settings)
    assert seen == [], "not even robots.txt"
    assert get_settings().catalog_intake_keralabookstore_pages == 0, "the shipped default is off"


async def test_switched_on_the_job_stages_the_newest_pages_and_no_more_than_asked(
    monkeypatch, session
):
    monkeypatch.setattr(kbs, "PAUSE_SECONDS", 0)
    settings = get_settings().model_copy(update={"catalog_intake_keralabookstore_pages": 2})
    seen: list[str] = []
    async with httpx.AsyncClient(transport=_shop_transport(seen)) as client:
        await intake_job._keralabookstore(session, client, settings)

    pages = [u for u in seen if "/book/" in u]
    assert pages == [
        "https://keralabookstore.com/book/dhanushkodi-when-the-sea-came-ashore/1007625/",
        "https://keralabookstore.com/book/anu-anandam-2/1007624/",
    ], "the two newest, in order"
    keys = (await session.execute(select(CatalogIntake.source_key))).scalars().all()
    assert sorted(keys) == ["1007624", "1007625"]


async def test_a_second_night_goes_on_where_the_first_stopped(monkeypatch, session):
    monkeypatch.setattr(kbs, "PAUSE_SECONDS", 0)
    settings = get_settings().model_copy(update={"catalog_intake_keralabookstore_pages": 1})
    for _ in range(2):
        seen: list[str] = []
        async with httpx.AsyncClient(transport=_shop_transport(seen)) as client:
            await intake_job._keralabookstore(session, client, settings)
    keys = (await session.execute(select(CatalogIntake.source_key))).scalars().all()
    assert sorted(keys) == ["1007624", "1007625"], "the next-newest, not the same one again"


async def test_a_night_cut_short_keeps_the_pages_already_read(monkeypatch, session):
    """Reading 150 pages at ten seconds each is twenty-five minutes, and a push
    to main restarts this process in the middle of it. Staged only at the end,
    that deploy would throw the whole night away; staged as it goes it costs the
    batch in flight."""
    monkeypatch.setattr(kbs, "PAUSE_SECONDS", 0)
    monkeypatch.setattr(kbs, "STAGE_EVERY", 2)
    settings = get_settings().model_copy(update={"catalog_intake_keralabookstore_pages": 4})
    reads = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        if url.endswith("/robots.txt"):
            return httpx.Response(200, text="")
        if url == kbs.SITEMAP_URL:
            return httpx.Response(200, text=sitemap())
        reads["n"] += 1
        if reads["n"] == 3:
            raise RuntimeError("the process was killed here")
        return httpx.Response(200, text=book_page())

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        await intake_job._keralabookstore(session, client, settings)

    keys = (await session.execute(select(CatalogIntake.source_key))).scalars().all()
    assert sorted(keys) == ["1007624", "1007625"], "the first batch of two was already staged"


def test_production_switches_it_on_through_the_environment(monkeypatch):
    """`ENV CATALOG_INTAKE_KERALABOOKSTORE_PAGES=150` in api/Dockerfile is how the
    owner's decision reaches the setting; the code default stays off."""
    from app.core.config import Settings

    monkeypatch.delenv("CATALOG_INTAKE_KERALABOOKSTORE_PAGES", raising=False)
    assert Settings(_env_file=None).catalog_intake_keralabookstore_pages == 0
    monkeypatch.setenv("CATALOG_INTAKE_KERALABOOKSTORE_PAGES", "150")
    assert Settings(_env_file=None).catalog_intake_keralabookstore_pages == 150


async def test_a_shop_whose_robots_txt_says_no_costs_only_itself(monkeypatch, session):
    settings = get_settings().model_copy(update={"catalog_intake_keralabookstore_pages": 5})
    seen: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(str(request.url))
        if str(request.url).endswith("/robots.txt"):
            return httpx.Response(200, text="User-agent: *\nDisallow: /\n")
        raise AssertionError("nothing is read from a shop that has said no")

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        await intake_job._keralabookstore(session, client, settings)
    assert seen == ["https://keralabookstore.com/robots.txt"]
    assert (await session.execute(select(CatalogIntake))).first() is None
