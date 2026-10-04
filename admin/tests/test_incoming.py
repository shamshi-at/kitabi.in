"""New in catalog shows the picture that came with each row, and the book page
can hand out the book's public link.

**The thumbnails.** This screen exists so a wrong addition is caught by a
person before a reader reports it, and a title says nothing about a cover: the
nightly intake alone adds 150 editions a day, each with a picture nobody has
looked at. Three things are pinned — a work's thumbnail is the cover its public
page shows (the oldest edition that has one, the API's own rule), a book with
no cover says so instead of leaving a gap, and the rows the template is tested
with carry exactly the keys the queries build.

**Share.** The button carries the address a *reader* would be sent — the
public page — never the console's own, which nobody outside can open.

No database: the feed is patched out, so these cover the page and its rules,
not the SQL.
"""

import inspect
import re
import sys
import uuid
from datetime import UTC, datetime
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from jinja2 import StrictUndefined

from console import deps, queries
from console.routers import incoming
from console.templating import templates

NOW = datetime(2026, 10, 4, 2, 50, tzinfo=UTC)
WORK_ID = uuid.UUID("33333333-3333-3333-3333-333333333333")
COVER = "https://covers.kitabi.in/catalog/df26d0ad1b003f7544ae15973ecc49c5.jpg"
LOGO = "https://example.supabase.co/storage/v1/object/public/covers/publishers/logo.png"


def _row(kind: str, name: str, image: str | None, **extra) -> dict:
    """One feed row, in the shape `_feed` hands the template."""
    prefix = {"work": "works", "edition": "works", "author": "authors", "publisher": "publishers"}
    row_id = uuid.uuid4()
    return {
        "kind": kind,
        "label": kind.title(),
        "id": row_id,
        "name": name,
        "created_at": NOW,
        "adder_id": None,
        "href": f"/catalog/{prefix[kind]}/{row_id}",
        "image": image,
        # Attached after the queries, by `insights.attach_adders` and the
        # reviewed-ids lookup.
        "adder_label": "Imported",
        "reviewed": False,
        **extra,
    }


# --- which cover stands for a work ------------------------------------------


def test_a_works_thumbnail_is_its_oldest_edition_that_has_a_cover():
    """Rows arrive oldest edition first. The first *with a cover* wins — the
    same pick as the public book page, so the operator sees what readers see."""
    other = uuid.uuid4()
    covers = incoming.first_cover_per_work(
        [
            (WORK_ID, None),
            (WORK_ID, "https://covers.kitabi.in/catalog/first.jpg"),
            (WORK_ID, "https://covers.kitabi.in/catalog/reprint.jpg"),
            (other, "https://covers.kitabi.in/catalog/other.jpg"),
        ]
    )
    assert covers == {
        WORK_ID: "https://covers.kitabi.in/catalog/first.jpg",
        other: "https://covers.kitabi.in/catalog/other.jpg",
    }


def test_a_work_with_no_cover_anywhere_has_no_thumbnail():
    assert incoming.first_cover_per_work([(WORK_ID, None), (WORK_ID, "")]) == {}
    assert incoming.first_cover_per_work([]) == {}


# --- the page ---------------------------------------------------------------


@pytest.fixture
def client(monkeypatch):
    state = {"rows": []}

    async def feed(db, window, kind, unreviewed_only):  # noqa: ANN001
        return state["rows"]

    async def badges(db):  # noqa: ANN001
        return {"claims": 0, "revisions": 0, "reports": 0, "merges": 0, "promotions_live": 0}

    monkeypatch.setattr(incoming, "_feed", feed)
    monkeypatch.setattr(queries, "nav_badges", badges)
    # A template that reads a field the row doesn't carry must fail the test,
    # not render a blank cell in production.
    monkeypatch.setattr(templates.env, "undefined", StrictUndefined)

    app = FastAPI()
    app.include_router(incoming.router)
    app.dependency_overrides[deps.current_admin] = lambda: SimpleNamespace(
        id=uuid.UUID("99999999-9999-9999-9999-999999999999"), role="editor", email="op@kitabi.in"
    )
    app.dependency_overrides[deps.get_db] = lambda: object()
    c = TestClient(app)
    c.state = state
    return c


def test_an_edition_row_shows_its_cover_and_the_cover_opens_the_book(client):
    row = _row("edition", "ആനന്ദരാമായണം · ISBN 9789376880553", COVER)
    client.state["rows"] = [row]
    html = client.get("/moderation/incoming").text
    assert f'<a href="{row["href"]}" tabindex="-1"><img class="covthumb" src="{COVER}"' in html
    assert 'loading="lazy"' in html


def test_a_book_without_a_cover_says_so(client):
    client.state["rows"] = [_row("work", "Chemmeen", None), _row("edition", "Kayar", None)]
    html = client.get("/moderation/incoming").text
    assert html.count('class="covthumb none"') == 2
    assert '<img class="covthumb' not in html


def test_an_author_or_publisher_without_a_picture_is_left_blank(client):
    """Most have none, and nothing is drawn in its place — a column of "none"
    boxes would bury the books' ones, which are the ones that mean something."""
    client.state["rows"] = [_row("author", "Thakazhi", None), _row("publisher", "DC Books", None)]
    html = client.get("/moderation/incoming").text
    assert "covthumb" not in html


def test_a_publishers_logo_is_shown_whole_not_cropped_to_a_books_shape(client):
    client.state["rows"] = [_row("publisher", "DC Books", LOGO)]
    html = client.get("/moderation/incoming").text
    assert f'<img class="covthumb fit" src="{LOGO}"' in html


def test_the_empty_message_spans_the_new_column(client):
    html = client.get("/moderation/incoming").text
    assert "Nothing new in this period" in html
    table = html.split("<table>")[1].split("</table>")[0]
    assert table.count("<th") == 5
    assert 'colspan="5"' in table


def test_the_rows_here_carry_exactly_the_keys_the_queries_build():
    """`_row` is a claim about what the feed hands the template. Read the keys
    out of the two functions that build rows, so a key added or renamed there
    fails here instead of rendering blank (CLAUDE.md, 9 Aug 2026)."""
    built = _row("work", "x", None)
    attached_later = {"adder_label", "reviewed"}
    for fn in (incoming._feed, incoming._editions_since):
        keys = set(re.findall(r'^\s+"(\w+)":', inspect.getsource(fn), flags=re.MULTILINE))
        assert keys == set(built) - attached_later, fn.__name__


# --- share, on the book page -------------------------------------------------


def _top_bar(work: SimpleNamespace) -> str:
    """The book page's top-bar block alone — the share button lives there, and
    the rest of the page needs a database's worth of context."""
    env = templates.env
    old = env.undefined
    env.undefined = StrictUndefined
    try:
        template = env.get_template("book_detail.html")
        return "".join(template.blocks["topactions"](template.new_context({"w": work})))
    finally:
        env.undefined = old


def test_share_hands_out_the_public_page_not_the_consoles_address():
    html = _top_bar(SimpleNamespace(id=WORK_ID, title="Chemmeen", slug="chemmeen"))
    assert 'data-share="https://kitabi.in/book/chemmeen"' in html
    assert "admin.kitabi.in" not in html
    assert "/catalog/works/" not in html
    # A real button, so it is reachable by keyboard and never submits a form.
    assert '<button type="button"' in html
    assert "aria-label=" in html


def test_a_book_without_a_slug_shares_the_link_that_redirects_to_it():
    """Slugs are backfilled by a job; a book minutes old may not have one. The
    `/b/<id>` link works from the first second and follows the book after."""
    html = _top_bar(SimpleNamespace(id=WORK_ID, title="Chemmeen", slug=None))
    assert f'data-share="https://kitabi.in/b/{WORK_ID}"' in html


def test_a_title_with_quotes_cannot_break_out_of_the_attribute():
    html = _top_bar(SimpleNamespace(id=WORK_ID, title='The "Real" <Story>', slug="the-real-story"))
    assert 'data-share-title="The &#34;Real&#34; &lt;Story&gt;"' in html


def test_the_script_copies_the_link_when_there_is_no_share_sheet():
    """The button is inert without its handler, and the handler has to exist
    for every browser: share sheet where there is one, the clipboard elsewhere,
    and a visible confirmation — a copy that says nothing reads as a dead
    button. Read from the source; the behaviour itself is checked in a browser."""
    js = (Path(incoming.__file__).resolve().parents[1] / "static" / "admin.js").read_text()
    handler = js[js.index('closest("[data-share]")') :]
    assert "navigator.share" in handler
    assert "navigator.clipboard.writeText(url)" in handler
    assert "AbortError" in handler, "closing the share sheet is not a failure"
    assert "Link copied" in handler
