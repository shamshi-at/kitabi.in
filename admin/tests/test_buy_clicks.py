"""The buy-clicks report: which books readers go on to look at buying.

Three things are pinned.

- **The arithmetic** (`fold_days`, `with_shares`, `window_start`) — a quiet day
  is a zero that is shown, a window is whole UTC days, and a share is of the
  period's total. Pure, so tested without a database.
- **Opening the report is audited.** It names readers, and the console's rule
  since 4 Oct 2026 is that a reader's own behaviour may be seen *because* the
  look is recorded. Tested at the router, where the line is written.
- **A website click names nobody**, on screen as in the table.

No database: the five queries are patched out, so these cover the page and its
rules, not the SQL (which is run against a real database separately).
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

from console import deps, queries, security
from console.routers import buy_clicks
from console.templating import templates

NOW = datetime(2026, 10, 5, 9, 30, tzinfo=UTC)
TODAY = NOW.date()
READER_ID = uuid.UUID("11111111-1111-1111-1111-111111111111")
WORK_ID = uuid.UUID("33333333-3333-3333-3333-333333333333")

TOTALS = {"clicks": 12, "readers": 3, "books": 4, "app": 5, "web": 7, "tagged": 10}
SHOP = {
    "key": "amazon",
    "label": "Amazon",
    "clicks": 12,
    "books": 4,
    "app": 5,
    "web": 7,
    "share": 100,
}
BOOK = {
    "work_id": WORK_ID,
    "title": "ചെമ്മീൻ",
    "clicks": 6,
    "app": 2,
    "web": 4,
    "readers": 2,
    "last": NOW,
    "share": 50,
}
CLICK = {
    "at": NOW,
    "reader_id": READER_ID,
    "reader": "Anaya",
    "work_id": WORK_ID,
    "title": "ചെമ്മീൻ",
    "shop": "Amazon",
    "surface": "App",
    "tagged": True,
}
WEB_CLICK = {**CLICK, "reader_id": None, "reader": None, "surface": "Website", "tagged": False}


# --- the arithmetic ---------------------------------------------------------


def test_a_quiet_day_is_a_zero_that_is_shown():
    """A table that skips days with no clicks makes a dead week look like a
    shorter list."""
    days = buy_clicks.fold_days(
        [(date(2026, 10, 5), "web", 3), (date(2026, 10, 3), "app", 1)],
        start=date(2026, 10, 2),
        today=TODAY,
    )
    assert [d["day"].day for d in days] == [5, 4, 3, 2], "newest first, every day present"
    assert [d["total"] for d in days] == [3, 0, 1, 0]
    assert days[0] == {"day": TODAY, "app": 0, "web": 3, "total": 3, "share": 100}
    assert days[2]["app"] == 1 and days[2]["share"] == 33


def test_a_days_app_and_website_clicks_are_one_row():
    days = buy_clicks.fold_days([(TODAY, "web", 4), (TODAY, "app", 2)], start=TODAY, today=TODAY)
    assert days == [{"day": TODAY, "app": 2, "web": 4, "total": 6, "share": 100}]


def test_all_time_starts_at_the_first_click_not_at_the_epoch():
    days = buy_clicks.fold_days([(date(2026, 10, 3), "web", 1)], start=None, today=TODAY)
    assert [d["day"].day for d in days] == [5, 4, 3]


def test_no_clicks_at_all_is_one_empty_day_not_a_crash():
    assert buy_clicks.fold_days([], start=None, today=TODAY) == [
        {"day": TODAY, "app": 0, "web": 0, "total": 0, "share": 0}
    ]


def test_a_surface_nobody_named_is_still_counted_in_the_total():
    """A third surface (a tablet build, a partner site) must not vanish from
    the day's total because this file names two."""
    days = buy_clicks.fold_days([(TODAY, "tv", 2), (TODAY, "app", 1)], start=TODAY, today=TODAY)
    assert days[0]["total"] == 3


def test_a_window_is_whole_days_ending_today():
    """ "Last 7 days" is today and the six before it — the same seven rows the
    day table shows."""
    start = buy_clicks.window_start("7", NOW)
    assert start == datetime(2026, 9, 29, tzinfo=UTC)
    days = buy_clicks.fold_days([], start=start.date(), today=TODAY)
    assert len(days) == 7
    assert buy_clicks.window_start("all", NOW) is None
    assert buy_clicks.window_start("nonsense", NOW) == buy_clicks.window_start("28", NOW)


def test_shares_are_of_the_periods_total():
    rows = buy_clicks.with_shares([{"clicks": 3}, {"clicks": 1}], total=4)
    assert [r["share"] for r in rows] == [75, 25]
    assert buy_clicks.with_shares([{"clicks": 0}], total=0)[0]["share"] == 0


def test_a_shop_nobody_listed_here_still_reads_as_a_name():
    """One shop today, more expected. A new key must show up as itself the day
    its first click arrives, without this file being edited."""
    assert buy_clicks.shop_label("amazon") == "Amazon"
    assert buy_clicks.shop_label("dc_books") == "Dc Books"
    assert buy_clicks.surface_label("web") == "Website"
    assert buy_clicks.surface_label("tv") == "tv"


def test_a_reader_is_shown_by_the_best_name_there_is():
    named = SimpleNamespace(full_name="Anaya", username="anaya", email="a@example.com")
    handle = SimpleNamespace(full_name=None, username="anaya", email="a@example.com")
    bare = SimpleNamespace(full_name=None, username=None, email="a@example.com")
    assert buy_clicks.display_name(named) == "Anaya"
    assert buy_clicks.display_name(handle) == "@anaya"
    assert buy_clicks.display_name(bare) == "a@example.com"
    assert buy_clicks.display_name(None) == "a deleted account"


# --- the page ---------------------------------------------------------------


@pytest.fixture
def client(monkeypatch):
    state = {
        "role": "editor",
        "totals": TOTALS,
        "recent": [CLICK, WEB_CLICK],
        "asked": [],
    }
    audits: list[dict] = []

    async def totals(db, start):  # noqa: ANN001
        state["asked"].append(start)
        return state["totals"]

    async def days(db, start, now):  # noqa: ANN001
        return buy_clicks.fold_days([(TODAY, "web", 7), (TODAY, "app", 5)], TODAY, TODAY)

    async def shops(db, start, total):  # noqa: ANN001
        return [SHOP]

    async def books(db, start, total):  # noqa: ANN001
        return [BOOK]

    async def recent(db, start):  # noqa: ANN001
        return state["recent"]

    async def badges(db):  # noqa: ANN001
        return {"claims": 0, "revisions": 0, "reports": 0, "merges": 0, "promotions_live": 0}

    async def audit(db, action, **kw):  # noqa: ANN001
        audits.append({"action": action, **kw})

    monkeypatch.setattr(buy_clicks, "_totals", totals)
    monkeypatch.setattr(buy_clicks, "_days", days)
    monkeypatch.setattr(buy_clicks, "_shops", shops)
    monkeypatch.setattr(buy_clicks, "_books", books)
    monkeypatch.setattr(buy_clicks, "_recent", recent)
    monkeypatch.setattr(queries, "nav_badges", badges)
    monkeypatch.setattr(security, "audit", audit)
    # A template that reads a field the row doesn't carry must fail the test,
    # not render a blank cell in production.
    monkeypatch.setattr(templates.env, "undefined", StrictUndefined)

    app = FastAPI()
    app.include_router(buy_clicks.router)
    app.dependency_overrides[deps.current_admin] = lambda: SimpleNamespace(
        id=uuid.UUID("99999999-9999-9999-9999-999999999999"),
        role=state["role"],
        email="op@kitabi.in",
    )
    app.dependency_overrides[deps.get_db] = lambda: object()
    c = TestClient(app)
    c.state = state
    c.audits = audits
    return c


def test_the_report_shows_who_which_book_and_which_shop(client):
    page = client.get("/buy-clicks")
    assert page.status_code == 200
    html = page.text
    assert f'<a href="/readers/{READER_ID}">Anaya</a>' in html
    assert f'href="/catalog/works/{WORK_ID}"' in html
    assert "ചെമ്മീൻ" in html
    assert "<b>Amazon</b>" in html
    assert "From the app" in html and "From the website" in html
    assert "10 of\n      12 clicks were on a link carrying Kitabi" in html


def test_a_website_click_names_nobody(client):
    """The table stores nothing about a visitor, so there is nobody to link."""
    html = client.get("/buy-clicks").text
    assert "A website visitor" in html
    assert html.count("/readers/") == 1, "only the signed-in reader is a link"


def test_opening_the_report_is_recorded_once(client):
    """It names readers. The look is the price of the looking."""
    client.get("/buy-clicks?range=7")
    assert len(client.audits) == 1
    line = client.audits[0]
    assert line["action"] == "privacy.view"
    assert line["summary"] == "Buy clicks · everyone · last 7 days"
    assert str(line["admin_id"]) == "99999999-9999-9999-9999-999999999999"


def test_the_window_is_one_the_screen_offers(client):
    html = client.get("/buy-clicks?range=90").text
    assert '<a class="btn s on" href="/buy-clicks?range=90">Last 90 days</a>' in html
    client.get("/buy-clicks?range=%3Cscript%3E")
    assert client.audits[-1]["summary"].endswith("last 28 days"), "anything else is the default"
    client.get("/buy-clicks?range=all")
    assert client.state["asked"][-1] is None, "all time has no start"


def test_a_period_with_no_clicks_says_so_instead_of_drawing_empty_tables(client):
    client.state["totals"] = {**TOTALS, "clicks": 0, "readers": 0, "books": 0, "app": 0, "web": 0}
    client.state["recent"] = []
    html = client.get("/buy-clicks").text
    assert "No buy link was opened in this period." in html
    assert "By shop" not in html


def test_a_moderator_cannot_open_it(client):
    client.state["role"] = "moderator"
    with pytest.raises(deps.RedirectException):
        client.get("/buy-clicks")
    assert client.audits == [], "turned away before anything was read or recorded"


# --- the fixtures are the queries' shapes -----------------------------------


@pytest.mark.parametrize(
    ("fn", "fixture", "added_later"),
    [
        (buy_clicks._recent, CLICK, set()),
        (buy_clicks._books, BOOK, {"share"}),
        (buy_clicks._shops, SHOP, {"share"}),
        (buy_clicks._totals, TOTALS, set()),
    ],
)
def test_each_fixture_carries_exactly_the_keys_its_query_returns(fn, fixture, added_later):
    """A fixture is a claim about what the query hands the template. Read the
    keys out of the function, so a column added or renamed there fails here
    instead of rendering blank (CLAUDE.md, 9 Aug 2026)."""
    returned = set(re.findall(r'"(\w+)":', inspect.getsource(fn)))
    assert returned == set(fixture) - added_later, fn.__name__


def test_the_report_is_in_the_menu_and_the_handbook():
    base = (Path(buy_clicks.__file__).resolve().parents[1] / "templates" / "base.html").read_text()
    assert "navlink('/buy-clicks'" in base
    from console import handbook

    topic = handbook.BY_SLUG["buyclicks"]
    assert topic.screen == "/buy-clicks"
