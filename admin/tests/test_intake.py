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
        [
            (date(2026, 10, 4), "mathrubhumi", 150),
            (date(2026, 10, 5), "mathrubhumi", 75),
        ],
        [],
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


# --- a night that fell short says so ----------------------------------------

MORNING = datetime(2026, 10, 5, 4, 30, tzinfo=UTC)  # two hours after the run


def _nights(*published: tuple[date, int]) -> list[dict]:
    return intake.fold_days(
        [(d, "speakingtiger", n) for d, n in published if n],
        [(d, 600) for d, _ in published],
    )


def test_the_night_of_5_oct_is_reported_as_stopped_early():
    """One book out, 1,070 ready, a limit of 150 — found by the owner noticing
    the number. The screen has to notice it first."""
    days = _nights((date(2026, 10, 5), 1), (date(2026, 10, 4), 142))
    short = intake.short_night(days, ready=1070, limit=150, now=MORNING)
    assert short == {
        "day": date(2026, 10, 5),
        "kind": "short",
        "published": 1,
        "ready": 1070,
        "limit": 150,
    }


def test_a_full_night_is_not_a_warning():
    days = _nights((date(2026, 10, 5), 150), (date(2026, 10, 4), 142))
    assert intake.short_night(days, ready=920, limit=150, now=MORNING) is None


def test_a_night_a_little_short_is_ordinary():
    """A cover that would not load, a book that was here already: every night
    loses a few, and a warning that fires every morning is one nobody reads."""
    days = _nights((date(2026, 10, 5), 131))
    assert intake.short_night(days, ready=900, limit=150, now=MORNING) is None


def test_a_small_night_is_fine_when_the_queue_was_small():
    """Publishing 40 is not a failure when 40 is what there was."""
    days = _nights((date(2026, 10, 5), 40))
    assert intake.short_night(days, ready=0, limit=150, now=MORNING) is None


def test_a_night_with_no_trace_at_all_is_reported():
    days = _nights((date(2026, 10, 4), 142))
    short = intake.short_night(days, ready=1070, limit=150, now=MORNING)
    assert short["kind"] == "missing" and short["day"] == date(2026, 10, 5)


def test_tonights_run_is_not_judged_before_it_has_had_time_to_finish():
    """The run is at 02:30 IST (21:00 UTC the evening before). At 03:00 IST it is
    mid-flight: the night to judge is still yesterday's."""
    days = _nights((date(2026, 10, 4), 142))
    mid_run = datetime(2026, 10, 4, 21, 30, tzinfo=UTC)  # 03:00 IST on the 5th
    assert intake.short_night(days, ready=1070, limit=150, now=mid_run) is None
    before_run = datetime(2026, 10, 4, 19, 30, tzinfo=UTC)  # 01:00 IST on the 5th
    assert intake.short_night(days, ready=1070, limit=150, now=before_run) is None


def test_a_night_is_judged_once_it_has_had_its_hour():
    """03:45 IST is past the run and its hour: the 5th has no row, so it is the
    5th that is missing — read on the IST clock, not the UTC one (at 22:15 UTC
    on the 4th it is still "the 4th" by the calendar of the server)."""
    days = _nights((date(2026, 10, 4), 142))
    judged = datetime(2026, 10, 4, 22, 15, tzinfo=UTC)  # 03:45 IST on the 5th
    short = intake.short_night(days, ready=1070, limit=150, now=judged)
    assert short is not None and short["kind"] == "missing" and short["day"] == date(2026, 10, 5)


def test_the_screen_runs_its_clock_off_the_schedules_own_settings():
    """One decision, two places: the cron registers from these settings and the
    screen reads them, so moving the job moves what is judged. 21:00 UTC is
    02:30 IST."""
    assert intake.run_at() == (2, 30)


def test_moving_the_run_moves_the_night_the_screen_judges(monkeypatch):
    from types import SimpleNamespace

    import app.core.config as config

    monkeypatch.setattr(
        config,
        "get_settings",
        lambda: SimpleNamespace(catalog_intake_run_hour_utc=2, catalog_intake_run_minute_utc=30),
    )
    assert intake.run_at() == (
        8,
        0,
    ), "02:30 UTC — where the job used to run — is 08:00 IST"


def test_an_intake_that_has_never_run_is_not_late():
    assert intake.short_night([], ready=0, limit=150, now=MORNING) is None


# --- the pages --------------------------------------------------------------


def _admin(role: str = "editor") -> SimpleNamespace:
    return SimpleNamespace(
        id=uuid.UUID("99999999-9999-9999-9999-999999999999"),
        role=role,
        email="op@kitabi.in",
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
        return {
            "claims": 0,
            "revisions": 0,
            "reports": 0,
            "merges": 0,
            "promotions_live": 0,
        }

    monkeypatch.setattr(intake, "_days", days)
    monkeypatch.setattr(intake, "daily_limit", lambda: 150)
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


def test_kerala_book_store_has_a_column_and_its_count(client):
    """Owner, 7 Oct 2026: *"add keralabookstore in admin panel — currently I can't
    see the count from them."* It had published 16 books the night before and the
    screen had no column for it."""
    client.state["days"] = intake.fold_days(
        [
            (NIGHT, "mathrubhumi", 33),
            (NIGHT, "keralabookstore", 16),
            (NIGHT, "speakingtiger", 29),
        ],
        [(NIGHT, 750)],
    )
    html = client.get("/intake").text
    assert "Kerala Book Store" in html
    assert ">16<" in html, "its count is on the night's row"
    assert "keralabookstore" not in html.replace(
        'href="/intake/', ""
    ), "under its name, not its key"


def test_a_source_the_table_has_not_heard_of_still_gets_a_column(client):
    """An adapter added without touching this file published books that no column
    counted. It now shows under its own name."""
    client.state["days"] = intake.fold_days(
        [(NIGHT, "mathrubhumi", 30), (NIGHT, "someshop", 12)], [(NIGHT, 100)]
    )
    html = client.get("/intake").text
    assert "someshop" in html and ">12<" in html


def test_the_columns_come_in_a_stable_order_known_shops_first():
    days = intake.fold_days(
        [
            (NIGHT, "zzz_new", 1),
            (NIGHT, "keralabookstore", 2),
            (NIGHT, "aaa_new", 3),
            (NIGHT, "mathrubhumi", 4),
        ],
        [(NIGHT, 10)],
    )
    assert intake.source_columns(days) == ["mathrubhumi", "keralabookstore", "aaa_new", "zzz_new"]
    assert intake.source_columns([]) == []


def test_every_source_the_job_can_run_has_a_name_here():
    """The job's adapters live in the API; this table names them. A new adapter
    fails here until someone adds its label — the column would appear anyway, but
    under its key."""
    from app.services import intake_keralabookstore, intake_openlibrary, intake_storefront

    running = {
        intake_openlibrary.SOURCE,
        intake_keralabookstore.SOURCE,
        *(store.source for store in intake_storefront.STORES),
    }
    assert running <= set(intake.SOURCES), sorted(running - set(intake.SOURCES))


def test_the_days_source_filter_offers_kerala_book_store(client):
    html = client.get(f"/intake/{NIGHT.isoformat()}").text
    assert "Kerala Book Store" in html


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


def test_the_nights_page_warns_when_the_last_run_stopped_early(client, monkeypatch):
    monkeypatch.setattr(
        intake,
        "short_night",
        lambda days, ready, limit, now: {
            "day": date(2026, 10, 5),
            "kind": "short",
            "published": 1,
            "ready": ready,
            "limit": limit,
        },
    )
    html = client.get("/intake").text
    assert "The run on Monday 5 October stopped early." in html
    assert "It published 1 book," in html
    assert "656 were ready and a night can take 150" in html
    assert 'href="/handbook/intake#short"' in html


def test_the_nights_page_says_when_a_night_left_no_trace(client, monkeypatch):
    monkeypatch.setattr(
        intake,
        "short_night",
        lambda days, ready, limit, now: {
            "day": date(2026, 10, 5),
            "kind": "missing",
            "published": 0,
            "ready": ready,
            "limit": limit,
        },
    )
    assert "No sign of the run on Monday 5 October." in client.get("/intake").text


def test_an_ordinary_morning_has_no_warning(client, monkeypatch):
    monkeypatch.setattr(intake, "short_night", lambda days, ready, limit, now: None)
    html = client.get("/intake").text
    assert "stopped early" not in html and "No sign of the run" not in html


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
