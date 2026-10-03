"""Publishers' storefronts: reading a shop's feed and a book's own page.

**Every fixture here is a real payload**, trimmed — feed rows and product-page
markup saved from the three shops on 3 Oct 2026 (`tests/fixtures/storefront/`).
That is the point of them: a parser tested against markup written from the
parser proves only that the code agrees with itself (CLAUDE.md, 9 Aug 2026 —
the review `body`/`text` fixture). If a shop changes its theme these will keep
passing while production stops finding authors; the signal for that is the
`author_roles`/`authors` share of the intake queue, not this file.

What is pinned: what each shop's fields *mean*, that a book whose credits are
ambiguous is held rather than guessed at, and that a product page is read once
and only from the shop it belongs to.
"""

import json
from pathlib import Path

import httpx
import pytest
from sqlalchemy import select

from app.models import CatalogIntake
from app.models.catalog_intake import STATE_COMPLETE, STATE_INCOMPLETE, STATE_REJECTED
from app.services import intake_gate, intake_service
from app.services import intake_storefront as sf
from app.services.intake_gate import Candidate, screen

FIXTURES = Path(__file__).parent / "fixtures" / "storefront"
UA = "Kitabi/1.0 (+https://kitabi.in; catalogue intake)"


def feed(name: str) -> dict[str, dict]:
    """A shop's fixture feed, keyed by the start of each product's name."""
    rows = json.loads((FIXTURES / f"{name}_feed.json").read_text())
    return {row["name"]: row for row in rows}


def row(name: str, starts: str) -> dict:
    return next(r for n, r in feed(name).items() if n.startswith(starts))


def page(name: str) -> str:
    return (FIXTURES / f"{name}.html").read_text()


def with_page(candidate: Candidate, facts: dict) -> intake_gate.Screened:
    return screen(intake_service._with_page_facts(candidate, facts))


@pytest.fixture
async def session(db_sessionmaker):
    async with db_sessionmaker() as s:
        yield s


# --------------------------------------------------------------------------
# Speaking Tiger — the feed is enough
# --------------------------------------------------------------------------


def test_speaking_tiger_is_complete_from_its_feed_alone():
    candidate = sf.SPEAKING_TIGER.from_feed(row("speakingtiger", "Beetles"), sf.SPEAKING_TIGER)
    result = screen(candidate)

    assert result.ok
    book = result.candidate
    assert book.title == "Beetles and Other Friends"
    assert book.authors == ("Ruskin Bond",)
    assert book.isbn == "9789363360167"
    # The imprint on the spine, not the house that owns it.
    assert book.publisher == "Talking Cub"
    assert book.page_count == 112
    assert book.format == "Hardback PLC"
    assert book.language == "English"
    assert book.cover_url.startswith("https://speakingtigerbooks.com/wp-content/uploads/")
    assert book.source_url == "https://speakingtigerbooks.com/product/beetles-and-other-friends/"
    assert (book.source, book.source_key) == ("speakingtiger", "13553")
    # A blurb, not markup.
    assert "<" not in book.description


def test_two_credited_names_are_not_assumed_to_be_two_authors():
    """`The Red Wind Howls` lists its author and its translator in one
    attribute, alphabetically, with nothing to tell them apart. Recording the
    translator as an author is wrong data; the book waits for a person."""
    candidate = sf.SPEAKING_TIGER.from_feed(row("speakingtiger", "The Red Wind"), sf.SPEAKING_TIGER)
    result = screen(candidate)

    assert not result.ok and not result.rejected
    assert result.missing == (intake_gate.MISSING_AUTHOR_ROLES,)
    assert result.candidate.authors == ()
    # The names are kept, so whoever resolves it can see who they are choosing between.
    assert result.candidate.contributors == ("Christopher Peacock", "Tsering Dondrup")


def test_a_page_count_with_a_note_after_it_is_still_a_page_count():
    candidate = sf.SPEAKING_TIGER.from_feed(
        row("speakingtiger", "The World Was"), sf.SPEAKING_TIGER
    )
    assert candidate.page_count == 528  # "528 + 40-page photo insert"


def test_a_boxset_in_the_feed_is_refused():
    candidate = sf.SPEAKING_TIGER.from_feed(
        row("speakingtiger", "The Poetry of"), sf.SPEAKING_TIGER
    )
    assert screen(candidate).fatal == (intake_gate.FATAL_NOT_A_BOOK,)


# --------------------------------------------------------------------------
# HarperCollins India — ISBN in the SKU, the rest on the page
# --------------------------------------------------------------------------


def hc(starts: str) -> Candidate:
    return sf.HARPERCOLLINS_IN.from_feed(row("harpercollins", starts), sf.HARPERCOLLINS_IN)


def test_harpercollins_feed_has_the_isbn_and_waits_for_the_page():
    result = screen(hc("Thriving"))
    assert result.candidate.isbn == "9789373074665"
    assert result.candidate.publisher == "HarperCollins India"
    assert set(result.missing) == {intake_gate.MISSING_AUTHORS, intake_gate.MISSING_LANGUAGE}


def test_harpercollins_page_supplies_author_pages_and_language():
    result = with_page(
        hc("Thriving"), sf.HARPERCOLLINS_IN.from_page(page("harpercollins_thriving"))
    )
    assert result.ok
    assert result.candidate.authors == ("David Reid",)
    assert result.candidate.page_count == 352
    assert result.candidate.language == "English"  # the page says "eng"


def test_a_harpercollins_byline_of_two_is_held_for_roles():
    """Deepa Mandlik wrote it; Aboli Mandlik translated it. The byline lists
    both the same way."""
    result = with_page(
        hc("Dynasties"), sf.HARPERCOLLINS_IN.from_page(page("harpercollins_dynasties"))
    )
    assert result.missing == (intake_gate.MISSING_AUTHOR_ROLES,)
    assert result.candidate.contributors == ("Deepa Mandlik", "Aboli Mandlik")


def test_a_hindi_edition_under_a_latin_title_is_held():
    """The shop lists its Hindi books under romanized names. The book's title
    is in Devanagari; this is not it."""
    result = with_page(hc("Somnath"), sf.HARPERCOLLINS_IN.from_page(page("harpercollins_somnath")))
    assert result.candidate.language == "Hindi"
    assert result.missing == (intake_gate.MISSING_NATIVE_TITLE,)


def test_the_shops_tagline_is_cut_and_its_capitals_are_undone():
    assert hc("Showtime!").title == "Showtime!: A Rita Ferreira Thriller"
    assert hc("LAUGH WITH ME").title == "Laugh with Me"


def test_a_coming_soon_book_with_no_cover_yet_waits_for_one():
    assert intake_gate.MISSING_COVER in screen(hc("Sakhis")).missing


def test_a_toy_listing_is_refused_and_so_never_costs_a_page_fetch():
    assert screen(hc("Booktopus")).rejected


# --------------------------------------------------------------------------
# Mathrubhumi — romanized capitals in the feed, Malayalam on the page
# --------------------------------------------------------------------------


def mbi(starts: str) -> Candidate:
    return sf.MATHRUBHUMI.from_feed(row("mathrubhumi", starts), sf.MATHRUBHUMI)


def test_mathrubhumi_feed_gives_a_provisional_title_and_both_covers():
    candidate = mbi("SPINOSAURUS")
    assert candidate.title == "Spinosaurus"  # provisional — see the next test
    assert candidate.cover_url.endswith("Spinosorus-Cover-Front.jpg")
    assert candidate.back_cover_url.endswith("Spinosorus-Cover-Back.jpg")
    assert not screen(candidate).ok and not screen(candidate).rejected


def test_mathrubhumi_page_gives_the_title_in_malayalam():
    """The whole reason this shop is worth a page fetch per book: the feed has
    `SPINOSAURUS`, the page has the name on the cover."""
    result = with_page(
        mbi("SPINOSAURUS"), sf.MATHRUBHUMI.from_page(page("mathrubhumi_spinosaurus"))
    )
    assert result.ok
    book = result.candidate
    assert book.title == "സ്‌പൈനോസോറസ്"
    assert book.authors == ("Aravindakshan K",)  # ARAVINDAKSHAN K on the page
    assert book.language == "Malayalam"
    assert book.isbn == "9789376881338"
    assert book.publisher == "Mathrubhumi Books"  # the shop says "Mathrubhumi"
    assert book.page_count == 103


def test_without_its_page_a_malayalam_book_under_a_latin_title_would_be_held():
    """What the gate does if the page had no title: a romanization is not
    published as the book's name."""
    facts = sf.MATHRUBHUMI.from_page(page("mathrubhumi_spinosaurus"))
    facts.pop("title")
    assert with_page(mbi("SPINOSAURUS"), facts).missing == (intake_gate.MISSING_NATIVE_TITLE,)


def test_the_isbn_is_found_wherever_the_template_put_it():
    """On some pages the number sits under the page-count label and the ISBN
    label is empty (mbibooks.com/product/ozhivu, 3 Oct 2026)."""
    facts = sf.MATHRUBHUMI.from_page(page("mathrubhumi_ozhivu"))
    assert facts["isbn"] == "9789359627410"
    assert "page_count" not in facts  # and thirteen digits are not a page count
    assert with_page(mbi("OZHIVU"), facts).ok


def test_two_names_the_shop_labels_author_are_two_authors():
    """Unlike the other two shops, this one says "Author:"."""
    result = with_page(
        mbi("BHARATHANADANAM"), sf.MATHRUBHUMI.from_page(page("mathrubhumi_bharathanadanam"))
    )
    assert result.ok
    assert result.candidate.authors == ("Joseph Vyttila", "Joshy George")


def test_old_style_chillu_letters_are_written_the_modern_way():
    """`ന്‍` (three code points) and `ൻ` (one) are the same letter on screen
    and different strings to a search index."""
    facts = sf.MATHRUBHUMI.from_page(page("mathrubhumi_brahmadathan"))
    assert "്‍" not in facts["title"]
    assert "ൻ" in facts["title"] or "ൽ" in facts["title"]


def test_a_combo_is_refused_from_the_feed():
    assert screen(mbi("MAMMOOTTY")).fatal == (intake_gate.FATAL_NOT_A_BOOK,)


# --------------------------------------------------------------------------
# Capitals
# --------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("shouted", "written"),
    [
        ("LAUGH WITH ME", "Laugh with Me"),
        ("THE ART OF WAR", "The Art of War"),
        ("SONG OF THE ASUNAM", "Song of the Asunam"),
        (
            "LIFT-OFF NATION: WHY WE ARE ENTERING THE GOLDEN AGE",
            "Lift-Off Nation: Why We Are Entering the Golden Age",
        ),
        ("M.T: KAALATHINTE KAALPPADUKAL", "M.T: Kaalathinte Kaalppadukal"),
        ("KAALAM SAKSHI 2", "Kaalam Sakshi 2"),
        ("WORLD WAR II STORIES", "World War II Stories"),
    ],
)
def test_a_shouted_title_is_written_as_a_title(shouted, written):
    assert sf.decase(shouted) == written


@pytest.mark.parametrize("title", ["SPQR", "NW", "Laugh with Me", "QB VII", "ആടുജീവിതം"])
def test_a_title_that_is_not_shouting_is_left_alone(title):
    assert sf.decase(title) == title


def test_a_shop_that_always_shouts_is_always_undone():
    assert sf.decase("VEENA", always=True) == "Veena"
    assert sf.decase("VEENA") == "VEENA"  # five letters: as likely a real acronym


def test_a_short_shouted_title_is_undone_at_the_gates_own_threshold():
    """`OTHELLO` reached the first preview of a real night (4 Oct 2026): seven
    letters, under the old threshold of eight, so neither the adapter nor the
    gate touched it."""
    assert sf.decase("OTHELLO") == "Othello"
    assert sf.decase("HAMLET") == "Hamlet"


@pytest.mark.parametrize(
    ("shouted", "written"),
    [
        ("ARAVINDAKSHAN K", "Aravindakshan K"),
        ("HAFIZ MOHAMAD N.P", "Hafiz Mohamad N.P"),
        ("KURUP K K N", "Kurup K K N"),
        ("VELOOR P K RAMACHANDRAN", "Veloor P K Ramachandran"),
        ("Maythil Radhakrishnan", "Maythil Radhakrishnan"),
        # Initials run into the name with full stops (mbibooks.com, 4 Oct 2026).
        ("R.C.KARIPPATH", "R.C.Karippath"),
        ("NOSSITER T.J", "Nossiter T.J"),
    ],
)
def test_a_shouted_name_keeps_its_initials(shouted, written):
    assert sf.name_case(shouted) == written


# --------------------------------------------------------------------------
# The crawl
# --------------------------------------------------------------------------


def _client(handler):
    return httpx.AsyncClient(transport=httpx.MockTransport(handler), timeout=5)


async def test_discover_stages_every_product_on_the_page_including_the_non_books():
    """The count of rows a shop has is how the next night knows where the
    crawl has got to, so nothing the feed lists is dropped here."""
    rows = list(feed("mathrubhumi").values())
    asked = []

    def handler(request):
        asked.append(dict(request.url.params))
        return httpx.Response(200, json=rows if request.url.params["page"] == "1" else [])

    async with _client(handler) as client:
        found = await sf.discover(client, sf.MATHRUBHUMI, pages=[1, 2, 3], pause=0)

    assert len(found) == len(rows)  # the combo too — the gate decides, not the crawl
    assert asked[0] == {"per_page": "100", "page": "1", "orderby": "date", "order": "desc"}
    assert len(asked) == 2, "an empty page is the end of the list"


async def test_a_failed_feed_page_ends_the_pass_without_raising():
    async with _client(lambda r: httpx.Response(503)) as client:
        assert await sf.discover(client, sf.MATHRUBHUMI, pages=[1, 2], pause=0) == []


async def test_one_unreadable_row_does_not_cost_the_page():
    rows = [{"id": 1, "name": None, "images": "not-a-list"}, row("speakingtiger", "Beetles")]
    async with _client(lambda r: httpx.Response(200, json=rows)) as client:
        found = await sf.discover(client, sf.SPEAKING_TIGER, pages=[1], pause=0)
    assert "13553" in {c.source_key for c in found}


@pytest.mark.parametrize(
    ("status", "body", "allowed"),
    [
        (200, "User-agent: *\nDisallow: /wp-admin/\n", True),
        # niyogibooksindia.com, 3 Oct 2026 — which is why it is not a Store.
        (200, "User-agent: *\nDisallow: /wp-json/\n", False),
        (404, "", True),  # no robots.txt permits everything
    ],
)
async def test_robots_txt_decides_whether_the_feed_is_read(status, body, allowed):
    async with _client(lambda r: httpx.Response(status, text=body)) as client:
        rules = await sf.read_robots(client, sf.MATHRUBHUMI)
    assert rules.can_fetch(UA, sf.MATHRUBHUMI.feed_url) is allowed


async def test_a_shop_whose_robots_txt_cannot_be_read_is_left_alone_tonight():
    """Not assumed to agree."""
    async with _client(lambda r: httpx.Response(503)) as client:
        assert await sf.read_robots(client, sf.MATHRUBHUMI) is None


def test_a_page_is_only_ever_fetched_from_the_shops_own_host():
    """The URL came out of the shop's feed and is fetched from inside our
    network."""
    store = sf.MATHRUBHUMI
    assert store.owns("https://www.mbibooks.com/product/spinosaurus/")
    assert store.owns("https://mbibooks.com/product/spinosaurus/")
    assert not store.owns("http://www.mbibooks.com/product/spinosaurus/")
    assert not store.owns("https://www.mbibooks.com.evil.test/product/x/")
    assert not store.owns("https://169.254.169.254/latest/meta-data")
    assert not store.owns(None)


async def test_the_backlist_pass_resumes_from_how_much_is_staged(session):
    store = sf.SPEAKING_TIGER
    assert await sf.backlist_pages(session, store, count=3) == [2, 3, 4]

    await intake_service.record(
        session,
        [Candidate(source=store.source, source_key=str(n), title=f"Book {n}") for n in range(350)],
        source=store.source,
    )
    # 350 staged is three full pages read; start one page back, so a book
    # added to the shop since last night cannot push one out of reach.
    assert await sf.backlist_pages(session, store, count=2) == [3, 4]
    assert await sf.backlist_pages(session, store, count=0) == []


# --------------------------------------------------------------------------
# enrich — reading a book's own page
# --------------------------------------------------------------------------


async def stage(session, store: sf.Store, product: dict) -> CatalogIntake:
    await intake_service.record(session, [store.from_feed(product, store)], source=store.source)
    return (
        await session.execute(
            select(CatalogIntake).where(CatalogIntake.source_key == str(product["id"]))
        )
    ).scalar_one()


async def test_a_held_row_is_completed_from_its_page(session):
    staged = await stage(session, sf.MATHRUBHUMI, row("mathrubhumi", "SPINOSAURUS"))
    assert staged.state == STATE_INCOMPLETE

    async with _client(lambda r: httpx.Response(200, text=page("mathrubhumi_spinosaurus"))) as c:
        counts = await sf.enrich(session, c, limit=10, pause=0)

    assert counts == {STATE_COMPLETE: 1}
    await session.refresh(staged)
    assert staged.state == STATE_COMPLETE
    assert staged.payload["title"] == "സ്‌പൈനോസോറസ്"
    assert staged.isbn == "9789376881338"


async def test_tonights_feed_does_not_undo_what_the_page_supplied(session):
    """The feed is re-read every night and still says `SPINOSAURUS`, no ISBN,
    no author. Without the page's facts being kept apart and laid back over
    it, every enriched row would be thin again by morning — and, its page
    already read, would stay that way."""
    product = row("mathrubhumi", "SPINOSAURUS")
    staged = await stage(session, sf.MATHRUBHUMI, product)
    async with _client(lambda r: httpx.Response(200, text=page("mathrubhumi_spinosaurus"))) as c:
        await sf.enrich(session, c, limit=10, pause=0)

    await stage(session, sf.MATHRUBHUMI, product)  # the next night's crawl

    await session.refresh(staged)
    assert staged.state == STATE_COMPLETE
    assert staged.payload["title"] == "സ്‌പൈനോസോറസ്"
    assert staged.payload["authors"] == ["Aravindakshan K"]


async def test_a_page_is_read_once(session):
    """Whatever it yielded. This row's page leaves it held for author roles,
    and it must not be fetched again every night for as long as it is."""
    await stage(session, sf.HARPERCOLLINS_IN, row("harpercollins", "Dynasties"))
    requests = []

    def handler(request):
        requests.append(str(request.url))
        return httpx.Response(200, text=page("harpercollins_dynasties"))

    async with _client(handler) as c:
        first = await sf.enrich(session, c, limit=10, pause=0)
        second = await sf.enrich(session, c, limit=10, pause=0)

    assert first == {STATE_INCOMPLETE: 1}
    assert second == {}
    assert len(requests) == 1


async def test_a_page_that_is_gone_is_not_asked_for_again(session):
    await stage(session, sf.MATHRUBHUMI, row("mathrubhumi", "SPINOSAURUS"))
    requests = []

    def handler(request):
        requests.append(1)
        return httpx.Response(404)

    async with _client(handler) as c:
        await sf.enrich(session, c, limit=10, pause=0)
        await sf.enrich(session, c, limit=10, pause=0)
    assert len(requests) == 1


async def test_a_page_we_could_not_read_tonight_is_tried_again(session):
    staged = await stage(session, sf.MATHRUBHUMI, row("mathrubhumi", "SPINOSAURUS"))
    async with _client(lambda r: httpx.Response(503)) as c:
        assert await sf.enrich(session, c, limit=10, pause=0) == {"retry": 1}
    async with _client(lambda r: httpx.Response(200, text=page("mathrubhumi_spinosaurus"))) as c:
        assert await sf.enrich(session, c, limit=10, pause=0) == {STATE_COMPLETE: 1}
    await session.refresh(staged)
    assert staged.state == STATE_COMPLETE


async def test_a_refused_row_never_costs_a_page_fetch(session):
    """A combo is not a book, and its page would not make it one."""
    staged = await stage(session, sf.MATHRUBHUMI, row("mathrubhumi", "MAMMOOTTY"))
    assert staged.state == STATE_REJECTED

    def explode(request):
        raise AssertionError("a refused row's page must not be fetched")

    async with _client(explode) as c:
        assert await sf.enrich(session, c, limit=10, pause=0) == {}


async def test_a_product_url_on_another_host_is_never_fetched(session):
    product = {**row("mathrubhumi", "SPINOSAURUS"), "permalink": "https://169.254.169.254/x"}
    await stage(session, sf.MATHRUBHUMI, product)

    def explode(request):
        raise AssertionError("only the shop's own host is ever fetched")

    async with _client(explode) as c:
        assert await sf.enrich(session, c, limit=10, pause=0) == {"no_page": 1}


async def test_robots_txt_is_asked_about_each_page(session):
    await stage(session, sf.MATHRUBHUMI, row("mathrubhumi", "SPINOSAURUS"))

    def explode(request):
        raise AssertionError("robots.txt said no")

    async with _client(explode) as c:
        counts = await sf.enrich(session, c, limit=10, pause=0, may_fetch=lambda store, url: False)
    assert counts == {"no_page": 1}


async def test_a_shop_that_is_down_stops_being_asked_tonight(session):
    products = [
        {
            **row("mathrubhumi", "SPINOSAURUS"),
            "id": n,
            "permalink": f"https://www.mbibooks.com/product/{n}/",
        }
        for n in range(1, 9)
    ]
    for product in products:
        await stage(session, sf.MATHRUBHUMI, product)
    requests = []

    def handler(request):
        requests.append(1)
        return httpx.Response(503)

    async with _client(handler) as c:
        await sf.enrich(session, c, limit=10, pause=0)
    assert len(requests) == sf.MAX_CONSECUTIVE_FAILURES


async def test_a_shop_with_no_page_parser_is_never_enriched(session):
    """Speaking Tiger's feed carries everything; a row of its that is held is
    held for something a page does not have either."""
    await stage(session, sf.SPEAKING_TIGER, row("speakingtiger", "The Red Wind"))

    def explode(request):
        raise AssertionError("this shop has no page parser")

    async with _client(explode) as c:
        assert await sf.enrich(session, c, limit=10, pause=0) == {}


# --------------------------------------------------------------------------
# a whole night, through the job
# --------------------------------------------------------------------------


async def test_a_night_reads_the_newest_page_then_the_book_pages_then_publishes(
    db_sessionmaker, monkeypatch
):
    """Feed → stage → product page → gate → cover into R2 → book. Only the
    remote hosts are stubbed; everything between them is the real code."""
    import io

    from PIL import Image

    from app.core.config import get_settings
    from app.jobs import catalog_intake as job
    from app.models import Edition, Work

    settings = get_settings().model_copy(
        update={
            "catalog_intake_enabled": True,
            "catalog_intake_backlist_pages": 1,
            "r2_account_id": "acct123",
            "r2_access_key_id": "AKID",
            "r2_secret_access_key": "SECRET",
            "r2_covers_bucket": "kitabi-covers",
            "r2_covers_public_url": "https://covers.kitabi.in",
        }
    )
    monkeypatch.setattr(job, "get_settings", lambda: settings)
    monkeypatch.setattr("app.services.intake_service.get_settings", lambda: settings)
    monkeypatch.setattr(job, "SessionLocal", db_sessionmaker)
    monkeypatch.setattr(sf, "STORES", (sf.MATHRUBHUMI,))

    async def instant(_seconds):
        return None

    monkeypatch.setattr(sf.asyncio, "sleep", instant)

    cover = io.BytesIO()
    Image.effect_noise((900, 1350), 64).convert("RGB").save(cover, "JPEG")
    products = [row("mathrubhumi", "SPINOSAURUS"), row("mathrubhumi", "MAMMOOTTY")]
    seen: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        host, path = request.url.host, request.url.path
        seen.append(f"{host}{path}")
        if host == "openlibrary.org":
            return httpx.Response(200, json={"docs": []})
        if host == "acct123.r2.cloudflarestorage.com":
            return httpx.Response(200)
        assert host == "www.mbibooks.com", f"the job reached a host nobody expected: {host}"
        if path == "/robots.txt":
            return httpx.Response(200, text="User-agent: *\nDisallow: /wp-admin/\n")
        if path == sf.FEED_PATH:
            first = request.url.params["page"] == "1"
            return httpx.Response(200, json=products if first else [])
        if path.startswith("/product/"):
            return httpx.Response(200, text=page("mathrubhumi_spinosaurus"))
        if path.startswith("/mbibooks_details/uploads/"):
            return httpx.Response(
                200, content=cover.getvalue(), headers={"content-type": "image/jpeg"}
            )
        raise AssertionError(f"unexpected path {path}")

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        await job.catalog_intake(client)

    async with db_sessionmaker() as db:
        work = (await db.execute(select(Work))).scalar_one()
        edition = (await db.execute(select(Edition))).scalar_one()
        rows = {r.source_key: r for r in (await db.execute(select(CatalogIntake))).scalars()}

    assert work.title == "സ്‌പൈനോസോറസ്"
    assert work.language == "Malayalam"
    assert [a.name for a in work.authors] == ["Aravindakshan K"]
    assert edition.isbn == "9789376881338"
    assert edition.cover_url.startswith("https://covers.kitabi.in/catalog/")
    assert edition.back_cover_url.startswith("https://covers.kitabi.in/catalog/")
    assert (work.external_source, work.external_id) == ("mathrubhumi", "842007")
    # The combo was staged, refused, and never looked at again.
    assert rows["840420"].state == STATE_REJECTED
    assert sum(1 for s in seen if s.startswith("www.mbibooks.com/product/")) == 1
