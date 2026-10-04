"""The nightly intake's screen: the nights, then one night's books.

The job publishes up to 150 books a night with nobody watching, so this page
is the only place a person sees what it did. Three things are pinned here:

- **the arithmetic** (`fold_days`) — a night's total is the sum of its
  sources, a night that found books and published none still gets a row, and
  the list is newest-first. Pure, so it is tested without a database.
- **the pages render what they are handed** — rendered through the real router
  and the real templates with `StrictUndefined`, because a template that reads
  a field the row doesn't carry compiles perfectly and then shows a blank cell.
- **the fixtures are the router's own row shape** — `BOOK` carries exactly the
  keys `_books` returns, and a test asserts that against the source, so the
  template and the query cannot drift apart behind a fixture that agrees with
  only one of them (CLAUDE.md, 9 Aug 2026).

No database: the three queries are patched out, so these cover the page and
its rules, not the SQL.
"""

import inspect
import re
import sys
import uuid
from datetime import UTC, date, datetime
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from jinja2 import StrictUndefined

from console import deps, queries
from console.routers import intake
from console.templating import templates

NIGHT = date(2026, 10, 4)
WORK_ID = uuid.UUID("33333333-3333-3333-3333-333333333333")

BOOK = {
    "source": "Mathrubhumi",
    "at": datetime(2026, 10, 4, 2, 47, tzinfo=UTC),
    "printing": False,
    "work_id": WORK_ID,
    "title": "കുടിയേറ്റം സംസ്കാരം രാഷ്ട്രീയം",
    "subtitle": None,
    "slug": "kudiyettam-samskaram-rashtreeyam",
    "language": "Malayalam",
    "removed": False,
    "isbn": "9789376881192",
    "cover_url": "https://covers.kitabi.in/catalog/df26d0ad1b003f7544ae15973ecc49c5.jpg",
    "pages": 136,
    "format": "Paperback",
    "publisher": "Mathrubhumi Books",
    "authors": "Dines",
}

QUEUE = {
    "published": 142,
    "ready": 656,
    "held": 757,
    "refused": 52,
    "duplicate": 0,
    "waiting": [
        {"label": "No author found yet", "count": 468},
        {"label": "Title is not in the book's own script", "count": 77},
    ],
}


# --- the arithmetic ---------------------------------------------------------


def test_a_nights_total_is_the_sum_of_its_sources():
    days = intake.fold_days(
        [
            (NIGHT, "harpercollins_in", 45),
            (NIGHT, "mathrubhumi", 46),
            (NIGHT, "speakingtiger", 51),
        ],
        [(NIGHT, 1607)],
    )
    assert len(days) == 1
    assert days[0]["published"] == 142
    assert days[0]["by_source"] == {
        "harpercollins_in": 45,
        "mathrubhumi": 46,
        "speakingtiger": 51,
    }
    assert days[0]["found"] == 1607


def test_nights_are_listed_newest_first():
    days = intake.fold_days(
        [
            (date(2026, 10, 4), "mathrubhumi", 150),
            (date(2026, 10, 6), "mathrubhumi", 75),
            (date(2026, 10, 5), "mathrubhumi", 150),
        ],
        [],
    )
    assert [d["day"].day for d in days] == [6, 5, 4]


def test_a_night_that_found_books_and_published_none_still_has_a_row():
    """The night worth noticing: the crawl ran and nothing came out of it."""
    days = intake.fold_days([(date(2026, 10, 4), "mathrubhumi", 150)], [(date(2026, 10, 5), 90)])
    quiet = days[0]
    assert quiet["day"] == date(2026, 10, 5)
    assert quiet["published"] == 0
    assert quiet["found"] == 90
    assert quiet["share"] == 0


def test_the_bar_is_scaled_to_the_busiest_night_shown():
    days = intake.fold_days(
        [(date(2026, 10, 4), "mathrubhumi", 150), (date(2026, 10, 5), "mathrubhumi", 75)], []
    )
    assert [d["share"] for d in days] == [50, 100]


def test_no_nights_at_all_is_an_empty_list_not_a_division_by_zero():
    assert intake.fold_days([], []) == []


def test_only_the_newest_nights_are_kept():
    published = [(date(2026, 1, 1 + n), "mathrubhumi", 1) for n in range(10)]
    days = intake.fold_days(published, [], limit=3)
    assert [d["day"].day for d in days] == [10, 9, 8]


def test_a_day_in_the_address_is_a_date_or_nothing():
    assert intake.parse_day("2026-10-04") == NIGHT
    assert intake.parse_day("yesterday") is None
    assert intake.parse_day("2026-13-40") is None


def test_an_adapter_nobody_named_shows_under_its_own_name():
    """A fourth shop added to the job must not vanish from the screen because
    this file was not updated in the same commit."""
    assert intake.source_label("mathrubhumi") == "Mathrubhumi"
    assert intake.source_label("roli_books") == "roli_books"


def test_a_reason_nobody_translated_is_still_readable():
    assert intake.waiting_label("title_script") == "Title is not in the book's own script"
    assert intake.waiting_label("some_new_rule") == "some new rule"


# --- the pages --------------------------------------------------------------


def _admin(role: str = "editor") -> SimpleNamespace:
    return SimpleNamespace(
        id=uuid.UUID("99999999-9999-9999-9999-999999999999"), role=role, email="op@kitabi.in"
    )


@pytest.fixture
def client(monkeypatch):
    """The intake router on a bare app, its three queries patched."""
    state = {
        "days": intake.fold_days(
            [
                (NIGHT, "harpercollins_in", 45),
                (NIGHT, "mathrubhumi", 46),
                (NIGHT, "speakingtiger", 51),
            ],
            [(NIGHT, 1607)],
        ),
        "books": [BOOK],
        "asked": [],
        "role": "editor",
    }

    async def days(db):  # noqa: ANN001
        return state["days"]

    async def queue(db):  # noqa: ANN001
        return QUEUE

    async def books(db, day, source):  # noqa: ANN001
        state["asked"].append((day, source))
        return state["books"]

    async def badges(db):  # noqa: ANN001
        return {"claims": 0, "revisions": 0, "reports": 0, "merges": 0, "promotions_live": 0}

    monkeypatch.setattr(intake, "_days", days)
    monkeypatch.setattr(intake, "_queue", queue)
    monkeypatch.setattr(intake, "_books", books)
    monkeypatch.setattr(queries, "nav_badges", badges)
    # A template that reads a field the row doesn't carry must fail the test,
    # not render a blank cell in production.
    monkeypatch.setattr(templates.env, "undefined", StrictUndefined)

    app = FastAPI()
    app.include_router(intake.router)
    app.dependency_overrides[deps.current_admin] = lambda: _admin(state["role"])
    app.dependency_overrides[deps.get_db] = lambda: object()
    c = TestClient(app)
    c.state = state
    return c


def test_the_nights_page_shows_each_nights_count_and_links_to_its_books(client):
    page = client.get("/intake")
    assert page.status_code == 200
    html = page.text
    assert 'href="/intake/2026-10-04"' in html
    assert "See the books" in html
    assert ">142<" in html
    # One column per shop that published something, under the name a person
    # would call it — and none for a source that published nothing.
    for name in ("HarperCollins India", "Mathrubhumi", "Speaking Tiger"):
        assert name in html
    assert "OpenLibrary" not in html
    assert "1,607" in html


def test_the_nights_page_says_what_the_waiting_books_wait_for(client):
    html = client.get("/intake").text
    assert "No author found yet" in html
    assert "468" in html
    assert "656" in html  # ready for coming nights
    assert "757" in html  # waiting


def test_the_nights_page_before_the_first_night(client):
    client.state["days"] = []
    page = client.get("/intake")
    assert page.status_code == 200
    assert "has not published anything yet" in page.text


def test_a_night_lists_its_books_with_cover_title_and_where_to_go_next(client):
    page = client.get("/intake/2026-10-04")
    assert page.status_code == 200
    html = page.text
    assert BOOK["title"] in html
    assert f'src="{BOOK["cover_url"]}"' in html
    assert f'href="/catalog/works/{WORK_ID}"' in html
    assert f'href="https://kitabi.in/book/{BOOK["slug"]}"' in html
    assert "9789376881192" in html
    assert "Dines" in html
    assert "136 pages" in html
    assert "1 book published that night" in html
    assert client.state["asked"] == [(NIGHT, None)]


def test_a_night_can_be_narrowed_to_one_shop(client):
    page = client.get("/intake/2026-10-04?source=mathrubhumi")
    assert page.status_code == 200
    assert client.state["asked"] == [(NIGHT, "mathrubhumi")]
    assert "from Mathrubhumi" in page.text
    assert '<option value="mathrubhumi" selected>' in page.text


def test_a_source_nobody_has_heard_of_is_ignored_not_trusted(client):
    """The filter value comes from the address bar; only a known adapter name
    is ever handed to the query, and anything else reads as "every source"."""
    page = client.get("/intake/2026-10-04?source=%3Cb%3Enobody%3C%2Fb%3E")
    assert page.status_code == 200
    assert client.state["asked"] == [(NIGHT, None)]
    assert "nobody" not in page.text
    assert '<option value="" selected>' in page.text


def test_a_night_with_nothing_published_says_so(client):
    client.state["books"] = []
    page = client.get("/intake/2026-10-03")
    assert page.status_code == 200
    assert "Nothing was published on this night" in page.text
    assert "0 books published that night" in page.text


def test_a_book_without_a_cover_or_an_edition_still_renders(client):
    """`_books` outer-joins the Edition, so every edition field can be None."""
    client.state["books"] = [
        {
            **BOOK,
            "cover_url": None,
            "isbn": None,
            "pages": None,
            "format": None,
            "publisher": None,
            "authors": "",
            "language": None,
        }
    ]
    page = client.get("/intake/2026-10-04")
    assert page.status_code == 200
    assert 'class="covthumb none"' in page.text
    assert "<img" not in page.text.split("<table>")[1]


def test_a_printing_and_a_removed_book_are_marked(client):
    client.state["books"] = [{**BOOK, "printing": True, "removed": True}]
    html = client.get("/intake/2026-10-04").text
    assert ">printing<" in html
    assert ">removed<" in html
    # A removed book has no public page to send anyone to.
    assert "kitabi.in/book/" not in html
    # It can still be opened in the console.
    assert f'href="/catalog/works/{WORK_ID}"' in html


def test_something_that_is_not_a_date_goes_back_to_the_nights(client):
    page = client.get("/intake/not-a-date", follow_redirects=False)
    assert page.status_code == 303
    assert page.headers["location"] == "/intake"


def test_today_has_no_night_after(client):
    today = datetime.now(UTC).date()
    assert "Night after" not in client.get(f"/intake/{today.isoformat()}").text
    assert "Night after" in client.get("/intake/2026-10-01").text


def test_a_moderator_cannot_open_it(client):
    """The role check turns a too-junior admin away before any query runs
    (the console's own handler makes the exception a redirect to `/?denied=1`)."""
    client.state["role"] = "moderator"
    for address in ("/intake", "/intake/2026-10-04"):
        with pytest.raises(deps.RedirectException):
            client.get(address)
    assert client.state["asked"] == []


# --- the fixture is the query's shape ---------------------------------------


def test_the_fixture_carries_exactly_the_keys_the_query_returns():
    """`BOOK` is a claim about what `_books` hands the template. Read the keys
    out of the function itself, so a column added or renamed there fails here
    instead of rendering blank."""
    source = inspect.getsource(intake._books)
    returned = set(re.findall(r'^\s+"(\w+)":', source, flags=re.MULTILINE))
    assert returned == set(BOOK)


def test_the_page_is_reachable_from_the_menu_and_the_handbook():
    base = (Path(intake.__file__).resolve().parents[1] / "templates" / "base.html").read_text()
    assert "navlink('/intake'" in base
    from console import handbook

    topic = next(t for t in handbook.TOPICS if t.slug == "intake")
    assert topic.screen == "/intake"
