"""The drill-down lists: every kind renders in every scope it is offered in, and
opening a reader's private data always leaves a line in the audit log.

The second half is the condition the owner attached to opening private data at
all (4 Oct 2026): operators may see a reader's whole account *because* every
look is recorded. So it is tested at the router, where the audit is written,
not by reading the template — a list that renders private rows without the
audit line must fail here.

No database: the queries are patched out and the router is mounted on a bare
app, so these cover the page and its rules, not the SQL (which is exercised
against a real database separately).
"""

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

from console import activity, deps, queries, security
from console.routers import activity as activity_router
from console.templating import templates

NOW = datetime(2026, 10, 4, 8, 3, tzinfo=UTC)
READER = SimpleNamespace(
    id=uuid.UUID("11111111-1111-1111-1111-111111111111"),
    full_name="Anaya",
    username="anaya",
    email="anaya@example.com",
    suspended_at=None,
    profile_visible=True,
)
OTHER = SimpleNamespace(
    id=uuid.UUID("22222222-2222-2222-2222-222222222222"),
    full_name="Ravi",
    username=None,
    email="ravi@example.com",
    suspended_at=None,
    profile_visible=False,
)
WORK = SimpleNamespace(
    id=uuid.UUID("33333333-3333-3333-3333-333333333333"),
    title="Chemmeen",
)
AUTHOR_ID = uuid.UUID("44444444-4444-4444-4444-444444444444")
SERIES_ID = uuid.UUID("55555555-5555-5555-5555-555555555555")

_who = {"reader_id": READER.id, "reader": READER}
_book = {"work_id": WORK.id, "title": WORK.title}
_entry = SimpleNamespace(
    ownership="owned",
    is_favorite=True,
    notes="the copy with Amma's handwriting",
    status="reading",
    current_page=120,
    start_date=date(2026, 10, 1),
    finish_date=None,
)
_edition = SimpleNamespace(format="paperback", page_count=240, isbn="9788126403455")

ROWS = {
    "readers": [{**_who, "at": NOW}],
    "active": [{**_who, "at": NOW, "ops": 12}],
    "now": [{**_who, **_book, "s": SimpleNamespace(page_start=40), "minutes": 41127, "at": NOW}],
    "shelved": [{**_who, **_book, "e": _entry, "edition": _edition, "tags": ["kerala"], "at": NOW}],
    "finished": [{**_who, **_book, "e": _entry, "edition": _edition, "tags": [], "at": NOW}],
    "sittings": [
        {
            **_who,
            **_book,
            "x": SimpleNamespace(auto_stopped=True, page_start=10, page_end=30),
            "minutes": 25,
            "at": NOW,
        }
    ],
    "notes": [
        {
            **_who,
            **_book,
            "x": SimpleNamespace(body="Karuthamma, again.", page_start=3, page_end=4),
            "minutes": None,
            "at": NOW,
        }
    ],
    "reviews": [
        {
            **_who,
            **_book,
            "subject": {"kind": "works", "id": WORK.id, "name": WORK.title},
            "x": SimpleNamespace(visible=False, body="Unbearable, beautifully."),
            "at": NOW,
        }
    ],
    "ratings": [
        {
            **_who,
            "work_id": None,
            "title": None,
            "subject": {"kind": "series", "id": SERIES_ID, "name": "Kayar"},
            "x": SimpleNamespace(value=4),
            "at": NOW,
        }
    ],
    "lending": [
        {
            **_who,
            **_book,
            "x": SimpleNamespace(
                direction="lent",
                borrower_user_id=OTHER.id,
                borrower_name="Ravi",
                note=None,
                lent_date=date(2026, 9, 1),
                due_date=None,
                returned_date=None,
            ),
            "other": OTHER,
            "at": NOW,
        }
    ],
    "works": [
        {
            "x": SimpleNamespace(
                id=WORK.id,
                title=WORK.title,
                authors=[SimpleNamespace(id=AUTHOR_ID, name="Thakazhi", pen_name=None)],
                language="Malayalam",
                form="Novel",
            ),
            "adder_id": READER.id,
            "adder": READER,
            "at": NOW,
        }
    ],
    "authors": [
        {
            "x": SimpleNamespace(
                id=AUTHOR_ID, name="Thakazhi", name_translit="thakazhi", primary_language=None
            ),
            "adder_id": None,
            "adder": None,
            "at": NOW,
        }
    ],
    "connections": [
        {
            **_who,
            "x": SimpleNamespace(status="accepted"),
            "other_id": OTHER.id,
            "other": OTHER,
            "sent": True,
            "at": NOW,
        }
    ],
    "log": [
        {
            **_who,
            "x": SimpleNamespace(
                event_type="reading_started", entity_type="library_entry", entity_id=uuid.uuid4()
            ),
            "payload": '{"page": 40}',
            "at": NOW,
        }
    ],
}


class _DB:
    async def get(self, model, row_id):  # noqa: ANN001
        if row_id == READER.id:
            return READER
        if row_id == WORK.id:
            return WORK
        return None


def _admin(role: str = "editor") -> SimpleNamespace:
    return SimpleNamespace(
        id=uuid.UUID("99999999-9999-9999-9999-999999999999"), role=role, email="op@kitabi.in"
    )


@pytest.fixture
def client(monkeypatch):
    """The activity router on a bare app, queries patched, audit recorded."""
    audits: list[dict] = []
    state = {"more": False, "role": "editor"}

    async def rows(db, kind, scope, page=1, size=activity.PAGE_SIZE):  # noqa: ANN001
        return ROWS[kind], state["more"]

    async def counts(db, scope):  # noqa: ANN001
        return {k.key: len(ROWS[k.key]) for k in activity.kinds_for(scope.context)}

    async def minutes(db, scope):  # noqa: ANN001
        return 25

    async def badges(db):  # noqa: ANN001
        return {"claims": 0, "revisions": 0, "reports": 0, "merges": 0, "promotions_live": 0}

    async def audit(db, action, **kw):  # noqa: ANN001
        audits.append({"action": action, **kw})

    monkeypatch.setattr(activity, "rows", rows)
    monkeypatch.setattr(activity, "counts", counts)
    monkeypatch.setattr(activity, "minutes", minutes)
    monkeypatch.setattr(queries, "nav_badges", badges)
    monkeypatch.setattr(security, "audit", audit)
    # A template that reads a field the row doesn't carry must fail the test,
    # not render a blank cell in production.
    monkeypatch.setattr(templates.env, "undefined", StrictUndefined)

    app = FastAPI()
    app.include_router(activity_router.router)
    app.dependency_overrides[deps.current_admin] = lambda: _admin(state["role"])
    app.dependency_overrides[deps.get_db] = lambda: _DB()
    c = TestClient(app)
    c.audits = audits
    c.state = state
    return c


SCOPE_PARAMS = {
    "all": "range=all",
    "reader": f"reader={READER.id}",
    "work": f"work={WORK.id}",
}

CASES = [(k.key, ctx) for k in activity.KINDS for ctx in k.contexts]


@pytest.mark.parametrize(("kind", "context"), CASES)
def test_every_kind_renders_in_every_scope_it_is_offered_in(client, kind, context):
    res = client.get(f"/activity/{kind}?{SCOPE_PARAMS[context]}")
    assert res.status_code == 200, res.text[:400]
    html = res.text
    # Every kind offered in this scope is a tab, and the current one is marked.
    for k in activity.kinds_for(context):
        assert f"/activity/{k.key}?" in html
    assert 'class="tab on"' in html


@pytest.mark.parametrize(
    "kind", [k.key for k in activity.KINDS if "all" in k.contexts and k.key != "authors"]
)
def test_site_wide_rows_name_the_reader_as_a_link(client, kind):
    html = client.get(f"/activity/{kind}?range=today").text
    if kind == "works":
        # A work's reader is the person who added it.
        assert f'href="/readers/{READER.id}"' in html
    else:
        assert f'href="/readers/{READER.id}"' in html, "the reader on each row opens their page"


def test_books_open_the_book_page_for_an_editor_and_a_peek_for_a_moderator(client):
    html = client.get("/activity/shelved?range=today").text
    assert f'href="/catalog/works/{WORK.id}"' in html
    client.state["role"] = "moderator"
    html = client.get("/activity/shelved?range=today").text
    # The book page is editor+ — a moderator gets the popup, not a bounce.
    assert f'href="/catalog/works/{WORK.id}"' not in html
    assert f'data-peek="/catalog/peek/works/{WORK.id}"' in html


@pytest.mark.parametrize("kind", [k.key for k in activity.KINDS if k.private])
def test_opening_any_private_list_writes_one_audit_line(client, kind):
    ctx = next(c for c in ("reader", "all", "work") if c in activity.BY_KEY[kind].contexts)
    res = client.get(f"/activity/{kind}?{SCOPE_PARAMS[ctx]}")
    assert res.status_code == 200
    assert len(client.audits) == 1, f"{kind} rendered private rows without an audit line"
    line = client.audits[0]
    assert line["action"] == "privacy.view"
    assert line["admin_id"] == _admin().id
    assert activity.BY_KEY[kind].label in line["summary"]
    if ctx == "reader":
        assert line["target_type"] == "reader"
        assert line["target_id"] == str(READER.id)
        assert READER.email in line["summary"], "the line must say whose account was opened"
    # And the page tells the operator so.
    assert "audit log" in res.text


@pytest.mark.parametrize("kind", [k.key for k in activity.KINDS if not k.private])
def test_public_lists_are_not_audited(client, kind):
    ctx = activity.BY_KEY[kind].contexts[0]
    client.get(f"/activity/{kind}?{SCOPE_PARAMS[ctx]}")
    assert client.audits == []


def test_scrolling_further_is_not_a_second_look(client):
    """One look is one line. The scrolled pages are the same look."""
    res = client.get(
        f"/activity/shelved?reader={READER.id}&page=2", headers={"X-Requested-With": "fetch"}
    )
    assert res.status_code == 200
    assert client.audits == []
    # A fragment is rows, not a page.
    assert "<html" not in res.text and "<tr>" in res.text


def test_a_long_list_ends_on_a_relative_next_page_sentinel(client):
    client.state["more"] = True
    html = client.get(f"/activity/sittings?reader={READER.id}&range=7").text
    assert "data-more=" in html
    # Relative: behind Railway's proxy an absolute URL comes back http:// and the
    # browser refuses to fetch it from the https:// page.
    assert f'data-more="/activity/sittings?reader={READER.id}&amp;range=7&amp;page=2"' in html


def test_a_kind_that_does_not_belong_in_a_scope_redirects_to_one_that_does(client):
    # Notes are listed on a reader's account, not as a site-wide feed.
    res = client.get("/activity/notes?range=today", follow_redirects=False)
    assert res.status_code == 303
    assert res.headers["location"] == "/activity/readers?range=today"


def test_a_chart_column_opens_its_own_window(client):
    html = client.get("/activity/works?from=2026-10-04T08:00Z&to=2026-10-04T09:00Z").text
    assert "4 Oct 2026, 08:00–09:00 UTC" in html


def test_every_live_tile_on_the_dashboard_opens_its_rows():
    env = templates.env
    html = env.get_template("_dash_live.html").render(
        pulse={
            "reading_now": 2,
            "active_24h": 3,
            "new_readers_today": 0,
            "shelved_today": 1,
            "minutes_today": 38,
            "works_today": 149,
            "reviews_today": 0,
            "as_of": NOW,
        },
        reading_shape={"books": 2, "longest_minutes": 41127},
    )
    for href in (
        "/activity/now",
        "/activity/active?range=24h",
        "/activity/readers?range=today",
        "/activity/shelved?range=today",
        "/activity/sittings?range=today",
        "/activity/works?range=today",
        "/activity/reviews?range=today",
    ):
        assert f'href="{href}"' in html, href
