"""The Buy links worklist: filters, copy buttons, and a saved row that leaves.

Owner requests, 5 Oct 2026, on a list of ~1,500 editions worked through on a
phone:

- **the works list's filters** — search, language, Type, what is missing, order
  — and paging that keeps them;
- **tap a cover to copy the picture** (to paste into a shop's image search) and
  **a button to copy the title**;
- **a saved row counts down and leaves the list**, with the countdown itself
  the button that stops it.

The copy-the-picture half has a server in it, and that is where the care is: a
browser's clipboard takes PNG only and will not read an image from another
origin, so the console fetches the cover itself. What is pinned is that the
route takes an *edition id and nothing else* — it cannot be pointed at a URL —
and that the stored address is still vetted before anything is fetched.

No database and no network: the page query, the fetch and the audit are patched
out; Pillow is real.
"""

import asyncio
import io
import sys
import uuid
from datetime import UTC, datetime
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "api"))

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from jinja2 import StrictUndefined
from PIL import Image

from console import assets, deps, queries, security
from console.routers import catalog
from console.templating import templates

STATIC = Path(catalog.__file__).resolve().parents[1] / "static"
WORK_ID = uuid.UUID("33333333-3333-3333-3333-333333333333")
EDITION_ID = uuid.UUID("44444444-4444-4444-4444-444444444444")
COVER = "https://covers.kitabi.in/catalog/df26d0ad1b003f7544ae15973ecc49c5.jpg"


def _row(**over) -> dict:
    """One worklist row, in the shape `_bl_page` hands the template."""
    edition = SimpleNamespace(
        id=EDITION_ID,
        cover_url=COVER,
        language="Malayalam",
        format="Paperback",
        isbn="9789376881192",
        publisher=SimpleNamespace(name="Mathrubhumi Books"),
        amazon_not_found_at=None,
    )
    for key in ("cover_url", "isbn", "publisher", "format", "language", "amazon_not_found_at"):
        if key in over:
            setattr(edition, key, over.pop(key))
    return {
        "e": edition,
        "w": SimpleNamespace(id=WORK_ID, title=over.pop("title", "കാലം മഹാകാലം")),
        "author": "Suraj N",
        "search": "https://www.amazon.in/s?k=9789376881192",
        **over,
    }


def _image(fmt: str = "JPEG", size: tuple[int, int] = (1200, 1800), mode: str = "RGB") -> bytes:
    out = io.BytesIO()
    Image.new(mode, size, (120, 40, 50) if mode == "RGB" else (120, 40, 50, 128)).save(out, fmt)
    return out.getvalue()


# --------------------------------------------------------------------------
# paging keeps the filters
# --------------------------------------------------------------------------


def test_a_page_link_carries_every_filter_in_effect():
    params = {"q": "kaalam", "lang": "Malayalam", "form": "Novel", "filter": "no_cover", "sort": ""}
    assert (
        catalog.bl_page_url(params, 2)
        == "/catalog/buy-links?q=kaalam&lang=Malayalam&form=Novel&filter=no_cover&page=2"
    )


def test_the_plain_worklist_keeps_its_plain_address():
    empty = {"q": "", "lang": "", "form": "", "filter": "", "sort": ""}
    assert catalog.bl_page_url(empty, 1) == "/catalog/buy-links"
    assert catalog.bl_page_url(empty, 3) == "/catalog/buy-links?page=3"
    assert catalog.bl_page_url({**empty, "lang": "Malayalam"}, 1) == (
        "/catalog/buy-links?lang=Malayalam"
    )


def test_a_page_link_keeps_which_side_of_the_list_is_open():
    params = {"q": "", "lang": "", "form": "", "filter": "", "show": "not_found", "sort": ""}
    assert catalog.bl_page_url(params, 1) == "/catalog/buy-links?show=not_found"
    assert catalog.bl_page_url(params, 2) == "/catalog/buy-links?show=not_found&page=2"


def test_a_filter_value_cannot_add_parameters_of_its_own():
    url = catalog.bl_page_url({"q": "a&page=99#x", "lang": "", "form": "", "filter": ""}, 2)
    assert url == "/catalog/buy-links?q=a%26page%3D99%23x&page=2"


# --------------------------------------------------------------------------
# a cover the clipboard will take
# --------------------------------------------------------------------------


def test_a_jpeg_cover_becomes_a_png_no_bigger_than_it_needs_to_be():
    png = assets.to_clipboard_png(_image("JPEG", (1200, 1800)))
    picture = Image.open(io.BytesIO(png))
    assert picture.format == "PNG", "the clipboard takes PNG and nothing else"
    assert max(picture.size) == assets.CLIPBOARD_MAX_EDGE
    assert picture.size == (533, 800), "shrunk, not squashed"


def test_a_small_or_odd_shaped_cover_is_still_worth_copying():
    """The intake refuses these as *covers to publish*. Copying is not
    publishing: if it is what the catalogue has, it is what gets copied."""
    assert Image.open(io.BytesIO(assets.to_clipboard_png(_image("JPEG", (90, 140))))).size == (
        90,
        140,
    )
    assert assets.to_clipboard_png(_image("PNG", (900, 120))) is not None


def test_a_transparent_cover_is_put_on_white_not_black():
    png = assets.to_clipboard_png(_image("PNG", (40, 60), mode="RGBA"))
    picture = Image.open(io.BytesIO(png))
    assert picture.mode == "RGB"
    r, g, b = picture.getpixel((5, 5))
    assert min(r, g, b) > 100, "half-transparent oxblood over white, not over black"


def test_something_that_is_not_a_picture_is_refused(monkeypatch):
    assert assets.to_clipboard_png(b"<html>not found</html>") is None
    assert assets.to_clipboard_png(b"") is None
    # A decompression bomb: more pixels than we will ever decode.
    monkeypatch.setattr(assets.cover_ingest, "MAX_PIXELS", 100)
    assert assets.to_clipboard_png(_image("PNG", (50, 50))) is None


@pytest.mark.parametrize(
    "url",
    [
        None,
        "",
        "http://covers.kitabi.in/a.jpg",
        "https://localhost/a.jpg",
        "https://10.0.0.5/a.jpg",
        "https://printer.internal/a.jpg",
        "file:///etc/passwd",
    ],
)
def test_an_address_the_console_should_not_fetch_is_never_fetched(monkeypatch, url):
    """The address comes from the catalogue, and a cover URL there may have
    been typed by a reader years ago. Vetted before anything goes out."""

    async def fetch(client, target):  # noqa: ANN001
        raise AssertionError(f"fetched {target}")

    monkeypatch.setattr(assets.cover_ingest, "_fetch", fetch)
    with pytest.raises(assets.CoverError):
        asyncio.run(assets.cover_png(url))


def test_a_cover_that_cannot_be_fetched_or_decoded_says_so(monkeypatch):
    async def nothing(client, target):  # noqa: ANN001
        return SimpleNamespace(body=None, gone=False)

    async def junk(client, target):  # noqa: ANN001
        return SimpleNamespace(body=b"<html>", gone=False)

    monkeypatch.setattr(assets.cover_ingest, "_fetch", nothing)
    with pytest.raises(assets.CoverError, match="fetch"):
        asyncio.run(assets.cover_png(COVER))
    monkeypatch.setattr(assets.cover_ingest, "_fetch", junk)
    with pytest.raises(assets.CoverError, match="image"):
        asyncio.run(assets.cover_png(COVER))


# --------------------------------------------------------------------------
# the page
# --------------------------------------------------------------------------


class _DB:
    """Answers the cover route's one question (an edition's stored cover URL)
    and holds the one edition the mark/link routes load and commit."""

    def __init__(self):
        self.cover = COVER
        self.commits = 0
        self.edition = SimpleNamespace(
            id=EDITION_ID,
            work_id=WORK_ID,
            deleted_at=None,
            isbn="9789376881192",
            buy_links=None,
            amazon_not_found_at=None,
        )

    async def execute(self, _stmt):  # noqa: ANN001, ANN202
        """The cover route's one query: `(cover_url, isbn)` of the edition."""
        row = (self.cover, self.edition.isbn)
        return SimpleNamespace(first=lambda: row)

    async def get(self, _model, edition_id):  # noqa: ANN001, ANN202
        return self.edition if edition_id == EDITION_ID else None

    async def commit(self):  # noqa: ANN202
        self.commits += 1


@pytest.fixture
def client(monkeypatch):
    state = {"rows": [_row()], "total": 1, "asked": [], "role": "editor", "audits": []}
    db = _DB()

    async def page(db_, **kw):  # noqa: ANN001
        state["asked"].append(kw)
        return {
            "rows": state["rows"],
            "total": state["total"],
            "shows": {"": 118, "not_found": 5},
            "langs": [{"value": "Malayalam", "label": "Malayalam", "count": 100}],
        }

    async def audit(db_, action, **kw):  # noqa: ANN001
        state["audits"].append({"action": action, **kw})

    async def badges(db_):  # noqa: ANN001
        return {"claims": 0, "revisions": 0, "reports": 0, "merges": 0, "promotions_live": 0}

    async def forms(db_):  # noqa: ANN001
        return ["Novel", "Poetry"]

    monkeypatch.setattr(catalog, "_bl_page", page)
    monkeypatch.setattr(security, "audit", audit)
    monkeypatch.setattr(queries, "nav_badges", badges)
    monkeypatch.setattr(catalog.catalog_service, "catalog_forms", forms)
    monkeypatch.setattr(templates.env, "undefined", StrictUndefined)

    app = FastAPI()
    app.include_router(catalog.router)
    app.dependency_overrides[deps.current_admin] = lambda: SimpleNamespace(
        id=uuid.UUID("99999999-9999-9999-9999-999999999999"),
        role=state["role"],
        email="op@kitabi.in",
    )
    app.dependency_overrides[deps.get_db] = lambda: db
    c = TestClient(app)
    c.state = state
    c.db = db
    return c


def test_the_worklist_has_the_works_lists_filters(client):
    html = client.get("/catalog/buy-links").text
    for control in ('name="q"', 'name="lang"', 'name="form"', 'name="filter"', 'name="sort"'):
        assert control in html, control
    for option in ("Novel", "No cover", "No ISBN", "No description", "Recently added"):
        assert f">{option}</option>" in html, option
    assert "Malayalam (100)" in html, "language keeps its counts — they say how much work it is"
    assert "Clear filters" not in html, "nothing to clear yet"


def test_there_is_no_apply_button_because_every_control_submits_itself(client):
    """The selects submit on change and the search box on Enter, so a visible
    Apply did nothing a control did not already do (owner, 5 Oct 2026). What is
    kept: the <noscript> button the works list has, and the keyboard hint that
    makes a phone's Enter key read "Search" — which is what stands in for it."""
    html = client.get("/catalog/buy-links").text
    form = html[html.index('<form method="get" action="/catalog/buy-links"') :]
    form = form[: form.index("</form>")]
    assert form.count('onchange="this.form.requestSubmit()"') == 5, "every select"
    assert 'enterkeyhint="search"' in form
    visible = form.replace('<noscript><button class="btn s">Apply</button></noscript>', "")
    assert "Apply" not in visible, "no button is on screen"
    assert "<noscript><button" in form, "and a browser with no script still has one"


def test_the_filters_reach_the_query_and_keep_their_selection(client):
    html = client.get(
        "/catalog/buy-links?q=kaalam&lang=Malayalam&form=Novel&filter=no_isbn&sort=added"
    ).text
    assert client.state["asked"][-1] == {
        "q": "kaalam",
        "lang": "Malayalam",
        "form": "Novel",
        "gap": "no_isbn",
        "show": "",
        "sort": "added",
        "page": 1,
    }
    assert 'value="kaalam"' in html
    assert '<option value="Novel" selected>' in html
    assert '<option value="no_isbn" selected>' in html
    assert '<option value="added" selected>' in html
    assert "Clear filters" in html


def test_the_list_still_opens_a_to_z(client):
    """The works list opens newest-first; this one always opened A–Z and
    people have a place in it. The other orders are offered, not imposed."""
    html = client.get("/catalog/buy-links").text
    assert client.state["asked"][-1]["sort"] == "title"
    assert '<option value="title" selected>' in html


def test_a_filter_nobody_offers_is_ignored_not_trusted(client):
    client.get("/catalog/buy-links?filter=%27;drop&sort=shelved")
    assert client.state["asked"][-1]["gap"] == ""
    assert client.state["asked"][-1]["sort"] == "title"


def test_paging_keeps_the_filters(client):
    client.state["total"] = 120
    html = client.get("/catalog/buy-links?lang=Malayalam&filter=no_cover&page=2").text
    assert 'href="/catalog/buy-links?lang=Malayalam&amp;filter=no_cover"' in html, "previous"
    assert 'href="/catalog/buy-links?lang=Malayalam&amp;filter=no_cover&amp;page=3"' in html
    assert "page 2 of 3" in html


def test_a_cover_is_a_link_that_downloads_the_picture(client):
    """Owner request, 6 Oct 2026: tapping a cover downloads it (it used to copy
    it to the clipboard). A plain link, so every browser does it the same way and
    a keyboard reaches it."""
    html = client.get("/catalog/buy-links").text
    assert (
        f'<a class="bl-cover" href="/catalog/editions/{EDITION_ID}/cover.png?download=1" download'
        in html
    )
    assert "data-download-image" in html
    assert f'<img src="{COVER}"' in html, "it still shows the cover it has"
    assert "data-copy-image" not in html, "nothing copies the picture any more"
    assert 'type="button" class="bl-cover"' not in html


def test_a_row_without_a_cover_offers_nothing_to_download(client):
    client.state["rows"] = [_row(cover_url=None)]
    html = client.get("/catalog/buy-links").text
    assert "data-download-image" not in html and "cover.png" not in html
    assert '<div class="bl-cover" title="No cover">' in html


def test_the_title_has_a_copy_button_that_cannot_be_broken_by_the_title(client):
    client.state["rows"] = [_row(title='The "Real" <Story> & Co')]
    html = client.get("/catalog/buy-links").text
    assert 'data-copy="The &#34;Real&#34; &lt;Story&gt; &amp; Co"' in html
    assert 'data-copied="Title copied"' in html


def test_a_row_is_marked_to_leave_once_saved_and_can_say_the_page_is_done(client):
    html = client.get("/catalog/buy-links?lang=Malayalam&page=2").text
    assert '<div class="bl-row" data-row data-autoremove>' in html
    assert 'data-bl-count="1"' in html
    # The "page done" note is there, hidden, and points at page 1 of the same
    # filters — the rows that got links are gone, so the next ones moved up.
    assert "data-bl-cleared hidden" in html
    assert 'href="/catalog/buy-links?lang=Malayalam">Load the next ones' in html


def test_an_empty_worklist_says_so(client):
    client.state["rows"], client.state["total"] = [], 0
    html = client.get("/catalog/buy-links?lang=Tamil").text
    assert "matching these filters" in html
    assert "data-bl-cleared" not in html


# --------------------------------------------------------------------------
# "no Amazon link found" — owner request, 5 Oct 2026
#
# Some books are simply not on Amazon, so "editions with no link" never ends for
# them and they bury the ones that can be finished. The mark takes a row off the
# list; a filter shows the marked ones; and nothing public reads it.
# --------------------------------------------------------------------------

MARK_URL = f"/catalog/works/{WORK_ID}/editions/{EDITION_ID}/amazon-not-found"
FETCH = {"X-Requested-With": "fetch"}


def test_the_worklist_offers_a_filter_for_the_marked_ones_with_both_counts(client):
    html = client.get("/catalog/buy-links").text
    assert 'name="show"' in html
    assert '<option value="" selected>Still to find (118)</option>' in html
    assert '<option value="not_found">No Amazon link found (5)</option>' in html


def test_opening_the_marked_side_reaches_the_query_and_keeps_its_selection(client):
    html = client.get("/catalog/buy-links?show=not_found").text
    assert client.state["asked"][-1]["show"] == "not_found"
    assert '<option value="not_found" selected>' in html
    assert "Clear filters" in html, "a side that is not the default is a filter in effect"
    assert "marked no Amazon link found" in html and "missing a link" not in html


def test_a_side_nobody_offers_is_ignored_not_trusted(client):
    client.get("/catalog/buy-links?show=%27;drop")
    assert client.state["asked"][-1]["show"] == ""


def test_a_row_still_to_find_offers_to_be_marked_and_says_what_that_means(client):
    html = client.get("/catalog/buy-links").text
    assert f'action="{MARK_URL}"' in html
    assert '<input type="hidden" name="state" value="set">' in html
    assert ">No link found</button>" in html
    assert 'data-done="Marked ✓"' in html, "the button says what it did, not 'Saved'"
    assert ">Put back</button>" not in html, "nothing to undo on an unmarked row"
    assert 'class="bl-none" data-inline' in html, "saves in place, like Save, and counts down"


def test_a_marked_row_says_when_and_offers_to_be_put_back(client):
    when = datetime(2026, 10, 5, 20, 0, tzinfo=UTC)  # 01:30 on the 6th, in India
    client.state["rows"] = [_row(amazon_not_found_at=when)]
    html = client.get("/catalog/buy-links?show=not_found").text
    assert "No Amazon link found · 6 Oct 2026" in html, "drawn on the console's clock (IST)"
    assert '<input type="hidden" name="state" value="clear">' in html
    assert ">Put back</button>" in html and 'data-done="Put back ✓"' in html
    assert ">No link found</button>" not in html
    assert "Search Amazon" in html and 'name="url"' in html, "a link found later can still be saved"


def test_an_empty_marked_side_says_so(client):
    client.state["rows"], client.state["total"] = [], 0
    html = client.get("/catalog/buy-links?show=not_found").text
    assert "Nothing is marked" in html
    assert "every edition" not in html, "not the 'all done' message — that would be a lie here"
    html = client.get("/catalog/buy-links?show=not_found&lang=Tamil").text
    assert "under these filters" in html


def test_marking_stamps_the_edition_and_leaves_a_line_in_the_audit(client):
    resp = client.post(MARK_URL, data={"state": "set"}, headers=FETCH)
    assert resp.status_code == 204
    assert client.db.edition.amazon_not_found_at is not None
    assert client.db.commits >= 1
    (line,) = client.state["audits"]
    assert line["action"] == "catalog.amazon_link.not_found"
    assert line["target_type"] == "edition" and line["target_id"] == str(EDITION_ID)


def test_marking_twice_keeps_the_first_time(client):
    client.post(MARK_URL, data={"state": "set"}, headers=FETCH)
    first = client.db.edition.amazon_not_found_at
    client.post(MARK_URL, data={"state": "set"}, headers=FETCH)
    assert client.db.edition.amazon_not_found_at == first


def test_putting_back_clears_the_mark_and_says_so_in_the_audit(client):
    client.db.edition.amazon_not_found_at = datetime(2026, 10, 5, tzinfo=UTC)
    resp = client.post(MARK_URL, data={"state": "clear"}, headers=FETCH)
    assert resp.status_code == 204
    assert client.db.edition.amazon_not_found_at is None
    assert client.state["audits"][-1]["action"] == "catalog.amazon_link.not_found_clear"


def test_an_edition_that_already_has_an_amazon_link_cannot_be_marked(client):
    """The mark would say "there is no listing" about a book whose listing is
    right there on its own row."""
    client.db.edition.buy_links = [{"retailer": "Amazon", "url": "https://www.amazon.in/dp/X"}]
    resp = client.post(MARK_URL, data={"state": "set"}, headers=FETCH)
    assert resp.status_code == 400 and "already has an Amazon link" in resp.text
    assert client.db.edition.amazon_not_found_at is None
    assert client.state["audits"] == []
    # Another shop's link is not an Amazon link.
    client.db.edition.buy_links = [{"retailer": "Flipkart", "url": "https://flipkart.com/x"}]
    assert client.post(MARK_URL, data={"state": "set"}, headers=FETCH).status_code == 204


@pytest.mark.parametrize("data", [{}, {"state": ""}, {"state": "maybe"}, {"state": "SET"}])
def test_a_state_nobody_offers_changes_nothing(client, data):
    """Including none at all: a bare POST must not quietly mean "mark it"."""
    resp = client.post(MARK_URL, data=data, headers=FETCH)
    assert resp.status_code in (400, 422)
    assert client.db.edition.amazon_not_found_at is None and client.state["audits"] == []


def test_the_edition_must_belong_to_the_work_in_the_address(client):
    other = uuid.uuid4()
    url = f"/catalog/works/{other}/editions/{EDITION_ID}/amazon-not-found"
    assert client.post(url, data={"state": "set"}, headers=FETCH).status_code == 400
    gone = f"/catalog/works/{WORK_ID}/editions/{uuid.uuid4()}/amazon-not-found"
    assert client.post(gone, data={"state": "set"}, headers=FETCH).status_code == 400
    client.db.edition.deleted_at = datetime(2026, 10, 1, tzinfo=UTC)
    assert client.post(MARK_URL, data={"state": "set"}, headers=FETCH).status_code == 400
    assert client.db.edition.amazon_not_found_at is None


def test_without_script_it_redirects_back_and_never_to_somewhere_else(client):
    ok = client.post(
        MARK_URL,
        data={"state": "set", "next": "/catalog/buy-links?lang=Malayalam"},
        follow_redirects=False,
    )
    assert ok.status_code == 303 and ok.headers["location"] == "/catalog/buy-links?lang=Malayalam"
    away = client.post(
        MARK_URL,
        data={"state": "set", "next": "https://evil.example/"},
        follow_redirects=False,
    )
    assert away.headers["location"] == "/catalog/buy-links", "a console-local path or nothing"


def test_a_moderator_cannot_mark_an_edition(client):
    client.state["role"] = "moderator"
    with pytest.raises(deps.RedirectException):
        client.post(MARK_URL, data={"state": "set"}, headers=FETCH)
    assert client.db.edition.amazon_not_found_at is None


SAVE_URL = f"/catalog/works/{WORK_ID}/editions/{EDITION_ID}/amazon-link"
HAS_LINK = [{"retailer": "Amazon", "url": "https://amzn.in/d/FIRST"}]


def test_the_worklist_saves_only_if_the_row_is_still_empty(client):
    html = client.get("/catalog/buy-links").text
    assert '<input type="hidden" name="if_empty" value="1">' in html


def test_a_stale_row_does_not_overwrite_the_link_that_was_saved_since(client):
    """6 Oct 2026: editions were saved two and three times over, each later link
    replacing the earlier, because a stale copy of the list still showed the row.
    From the worklist (`if_empty`) a different link is refused and nothing moves."""
    client.db.edition.buy_links = list(HAS_LINK)
    resp = client.post(
        SAVE_URL, data={"url": "https://amzn.in/d/SECOND", "if_empty": "1"}, headers=FETCH
    )
    assert resp.status_code == 409
    assert "Already has an Amazon link (https://amzn.in/d/FIRST)" in resp.text
    assert client.db.edition.buy_links == HAS_LINK, "the first link is still the link"
    assert client.state["audits"] == [], "nothing was changed, so nothing is recorded"
    assert client.db.commits == 0


def test_saving_the_same_link_again_is_a_plain_success(client):
    client.db.edition.buy_links = list(HAS_LINK)
    resp = client.post(
        SAVE_URL, data={"url": "https://amzn.in/d/FIRST", "if_empty": "1"}, headers=FETCH
    )
    assert resp.status_code == 204
    assert client.db.edition.buy_links == HAS_LINK and client.db.commits == 0


def test_the_book_page_can_still_change_a_link_that_is_there(client):
    """`if_empty` is the worklist's promise, not the route's: the book page
    exists to replace a link that landed wrong."""
    client.db.edition.buy_links = list(HAS_LINK)
    resp = client.post(SAVE_URL, data={"url": "https://amzn.in/d/SECOND"}, headers=FETCH)
    assert resp.status_code == 204
    assert client.db.edition.buy_links == [
        {"retailer": "Amazon", "url": "https://amzn.in/d/SECOND"}
    ]


def test_an_empty_row_still_saves_through_the_guard(client):
    resp = client.post(
        SAVE_URL, data={"url": "https://amzn.in/d/FIRST", "if_empty": "1"}, headers=FETCH
    )
    assert resp.status_code == 204
    assert client.db.edition.buy_links == HAS_LINK


def test_another_shops_link_is_not_an_amazon_link_for_the_guard(client):
    client.db.edition.buy_links = [{"retailer": "Flipkart", "url": "https://flipkart.com/x"}]
    resp = client.post(
        SAVE_URL, data={"url": "https://amzn.in/d/FIRST", "if_empty": "1"}, headers=FETCH
    )
    assert resp.status_code == 204
    assert {"retailer": "Flipkart", "url": "https://flipkart.com/x"} in client.db.edition.buy_links


def test_saving_a_link_takes_the_mark_off_but_clearing_the_override_does_not(client):
    """Found one after all: "no Amazon link found" is no longer true. But an
    emptied override says nothing about whether Amazon has the book."""
    save = f"/catalog/works/{WORK_ID}/editions/{EDITION_ID}/amazon-link"
    client.db.edition.amazon_not_found_at = datetime(2026, 10, 5, tzinfo=UTC)

    assert client.post(save, data={"url": ""}, headers=FETCH).status_code == 204
    assert client.db.edition.amazon_not_found_at is not None

    resp = client.post(save, data={"url": "https://www.amazon.in/dp/B0TEST"}, headers=FETCH)
    assert resp.status_code == 204
    assert client.db.edition.amazon_not_found_at is None
    assert client.db.edition.buy_links == [
        {"retailer": "Amazon", "url": "https://www.amazon.in/dp/B0TEST"}
    ]


# --------------------------------------------------------------------------
# the cover route
# --------------------------------------------------------------------------


def test_the_cover_route_serves_a_png_of_the_editions_own_cover(client, monkeypatch):
    fetched = []

    async def fetch(http, url):  # noqa: ANN001
        fetched.append(url)
        return SimpleNamespace(body=_image("JPEG", (600, 900)), gone=False)

    monkeypatch.setattr(assets.cover_ingest, "_fetch", fetch)

    resp = client.get(f"/catalog/editions/{EDITION_ID}/cover.png")

    assert resp.status_code == 200
    assert resp.headers["content-type"] == "image/png"
    assert Image.open(io.BytesIO(resp.content)).format == "PNG"
    assert fetched == [COVER], "the address fetched is the one on the edition's row"
    assert "private" in resp.headers["cache-control"]


def test_the_download_is_an_attachment_named_for_the_isbn(client, monkeypatch):
    async def fetch(http, url):  # noqa: ANN001
        return SimpleNamespace(body=_image("JPEG", (600, 900)), gone=False)

    monkeypatch.setattr(assets.cover_ingest, "_fetch", fetch)

    plain = client.get(f"/catalog/editions/{EDITION_ID}/cover.png")
    assert "content-disposition" not in plain.headers, "without the flag it is just a picture"

    resp = client.get(f"/catalog/editions/{EDITION_ID}/cover.png?download=1")
    assert resp.status_code == 200 and resp.headers["content-type"] == "image/png"
    assert resp.headers["content-disposition"] == 'attachment; filename="9789376881192.png"'
    assert Image.open(io.BytesIO(resp.content)).format == "PNG"


def test_the_downloads_file_name_can_only_be_digits_or_the_start_of_an_id(client, monkeypatch):
    """The name is built from the edition's ISBN column. Whatever is in it, a
    header gets digits (and an X) or a fallback — never a quote or a newline."""

    async def fetch(http, url):  # noqa: ANN001
        return SimpleNamespace(body=_image(), gone=False)

    monkeypatch.setattr(assets.cover_ingest, "_fetch", fetch)
    client.db.edition.isbn = '97"; filename="evil.exe\r\nX: y'
    header = client.get(f"/catalog/editions/{EDITION_ID}/cover.png?download=1").headers[
        "content-disposition"
    ]
    import re

    assert re.fullmatch(r'attachment; filename="[0-9Xx]+\.png"', header), header
    assert "\r" not in header and "\n" not in header and "evil" not in header
    client.db.edition.isbn = None
    header = client.get(f"/catalog/editions/{EDITION_ID}/cover.png?download=1").headers[
        "content-disposition"
    ]
    assert header == f'attachment; filename="cover-{str(EDITION_ID)[:8]}.png"'


def test_the_cover_route_cannot_be_pointed_at_a_url(client, monkeypatch):
    """It takes an edition id. Anything else in the address is not an id, and
    a query string is not read at all."""

    async def fetch(http, url):  # noqa: ANN001
        assert url == COVER, f"fetched {url}"
        return SimpleNamespace(body=_image(), gone=False)

    monkeypatch.setattr(assets.cover_ingest, "_fetch", fetch)
    assert client.get(
        "/catalog/editions/https%3A%2F%2Fevil.example%2Fx.png/cover.png"
    ).status_code in (
        404,
        422,
    )
    ok = client.get(f"/catalog/editions/{EDITION_ID}/cover.png?u=https://evil.example/x.png")
    assert ok.status_code == 200


def test_an_edition_with_no_cover_or_a_bad_address_is_a_plain_404(client):
    client.db.cover = None
    resp = client.get(f"/catalog/editions/{EDITION_ID}/cover.png")
    assert resp.status_code == 404 and "no cover" in resp.text
    client.db.cover = "http://169.254.169.254/latest/meta-data/"
    assert client.get(f"/catalog/editions/{EDITION_ID}/cover.png").status_code == 404


def test_a_moderator_cannot_use_the_worklist_or_fetch_covers_through_it(client):
    client.state["role"] = "moderator"
    with pytest.raises(deps.RedirectException):
        client.get("/catalog/buy-links")
    with pytest.raises(deps.RedirectException):
        client.get(f"/catalog/editions/{EDITION_ID}/cover.png")


# --------------------------------------------------------------------------
# what the script promises (its behaviour is checked in a browser)
# --------------------------------------------------------------------------


def _script() -> str:
    return (STATIC / "admin.js").read_text()


def test_a_saved_row_counts_down_from_five_and_the_countdown_is_the_way_to_stop_it():
    js = _script()
    assert "const SECONDS = 5;" in js
    assert '"inline:saved"' in js and 'new CustomEvent("inline:saved"' in js
    assert 'e.target.closest("[data-keep]")' in js, "pressing the countdown is handled"
    assert '"inline:edited"' in js, "changing the link again stops it too"
    # The row is removed from the page, and nothing asks the server to delete.
    removal = js[
        js.index("function leave(row)") : js.index('document.addEventListener("inline:saved"')
    ]
    assert "row.remove()" in removal
    assert "fetch(" not in removal


def test_a_form_can_name_its_own_done_state_and_the_countdown_sits_beside_it():
    js = _script()
    assert 'btn.dataset.done || "Saved ✓"' in js, "'Marked ✓' for a mark, 'Saved ✓' for a link"
    assert (
        "detail: { button: btn }" in js and "e.detail.button" in js
    ), "the countdown follows the button that was pressed, not the first form in the row"
    assert "count.dataset.blSuffix" in js, "recounting says the same words as the heading"


def test_typing_in_a_row_stops_its_countdown_whichever_button_was_pressed():
    """Mark a row, then start pasting a link: it must not leave from under you."""
    js = _script()
    start = js.index("// Retyping after a save re-arms the button.")
    handler = js[start : js.index("})();", start)]
    assert 'new CustomEvent("inline:edited"' in handler
    assert handler.index('new CustomEvent("inline:edited"') > handler.index("if (btn.textContent")
    assert (
        "inline:edited" not in handler.split("if (btn.textContent", 1)[1].split("}", 1)[0]
    ), "dispatched outside the 'was Saved' branch, or a marked row would still leave"


def test_the_title_still_copies_and_says_so_and_the_cover_no_longer_does():
    js = _script()
    assert '"Copied"' in js and "Couldn't copy" in js, "title copy keeps its messages"
    assert (
        "ClipboardItem" not in js and "dataset.copyImage" not in js
    ), "no picture goes on the clipboard"


def test_a_cover_download_says_it_has_started():
    """On a phone a download changes nothing on the page; the toast is the only
    sign that the tap did something."""
    js = _script()
    assert 'e.target.closest("[data-download-image]")' in js
    assert '"Downloading the cover…"' in js


def test_a_row_that_was_already_linked_is_treated_as_done_and_says_why():
    js = _script()
    assert "res.status === 409" in js
    assert '"Already linked ✓"' in js
    block = js[js.index("res.status === 409") : js.index("res.status === 409") + 900]
    assert (
        'new CustomEvent("inline:saved"' in block
    ), "so it counts down and leaves like any saved row"


def test_a_page_restored_from_the_browsers_cache_reloads_itself():
    js = _script()
    assert 'window.addEventListener("pageshow"' in js
    assert "e.persisted" in js and "data-reload-on-restore" in js


def test_the_worklist_asks_to_be_reloaded_when_restored(client):
    html = client.get("/catalog/buy-links").text
    assert "data-reload-on-restore" in html


def test_the_console_has_the_jump_button_on_every_page():
    js, css = _script(), (STATIC / "admin.css").read_text()
    assert 'jmp.className = "jmp"' in js
    assert '"Back to the top"' in js and '"Jump to the end of the page"' in js
    assert ".jmp{" in css and ".toast{" in css
    base = (STATIC.parent / "templates" / "base.html").read_text()
    assert "admin.js?v=" in base
