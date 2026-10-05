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
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "api"))

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from jinja2 import StrictUndefined
from PIL import Image

from console import assets, deps, queries
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
    )
    for key in ("cover_url", "isbn", "publisher", "format", "language"):
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
    """Answers the cover route's one question: an edition's stored cover URL."""

    def __init__(self):
        self.cover = COVER

    async def scalar(self, _stmt):  # noqa: ANN001, ANN202
        return self.cover


@pytest.fixture
def client(monkeypatch):
    state = {"rows": [_row()], "total": 1, "asked": [], "role": "editor"}
    db = _DB()

    async def page(db_, **kw):  # noqa: ANN001
        state["asked"].append(kw)
        return {
            "rows": state["rows"],
            "total": state["total"],
            "langs": [{"value": "Malayalam", "label": "Malayalam", "count": 100}],
        }

    async def badges(db_):  # noqa: ANN001
        return {"claims": 0, "revisions": 0, "reports": 0, "merges": 0, "promotions_live": 0}

    async def forms(db_):  # noqa: ANN001
        return ["Novel", "Poetry"]

    monkeypatch.setattr(catalog, "_bl_page", page)
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


def test_the_filters_reach_the_query_and_keep_their_selection(client):
    html = client.get(
        "/catalog/buy-links?q=kaalam&lang=Malayalam&form=Novel&filter=no_isbn&sort=added"
    ).text
    assert client.state["asked"][-1] == {
        "q": "kaalam",
        "lang": "Malayalam",
        "form": "Novel",
        "gap": "no_isbn",
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


def test_a_cover_is_a_button_that_copies_the_picture(client):
    html = client.get("/catalog/buy-links").text
    assert f'data-copy-image="/catalog/editions/{EDITION_ID}/cover.png"' in html
    assert f'<img src="{COVER}"' in html, "it still shows the cover it has"
    assert 'type="button" class="bl-cover"' in html, "a real button: reachable by keyboard"


def test_a_row_without_a_cover_offers_nothing_to_copy(client):
    client.state["rows"] = [_row(cover_url=None)]
    html = client.get("/catalog/buy-links").text
    assert "data-copy-image" not in html
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


def test_copying_says_what_it_did_including_when_it_could_not():
    js = _script()
    assert '"Cover image copied"' in js
    assert "its link was copied instead" in js, "a failed picture copy is not reported as a success"
    assert '"image/png"' in js


def test_the_console_has_the_jump_button_on_every_page():
    js, css = _script(), (STATIC / "admin.css").read_text()
    assert 'jmp.className = "jmp"' in js
    assert '"Back to the top"' in js and '"Jump to the end of the page"' in js
    assert ".jmp{" in css and ".toast{" in css
    base = (STATIC.parent / "templates" / "base.html").read_text()
    assert "admin.js?v=" in base
