"""The audit log's Target column opens the record, for every kind of line.

Owner request, 6 Oct 2026: *"target should be clickable, so I can see what record
it is — it should work for all the audit log types."* Before, the catalogue's
kinds were linked and an edition (the 122 Amazon-link lines), an edit and a review
were plain text.

Three things are pinned: every `target_type` the console can write has been
decided (so the next feature that adds one cannot silently leave the log with a
type that opens nothing); what each kind resolves to — a name, and the page that
shows it; and that the page renders it, linked for someone who can open the
catalogue and as a peek for someone who can not. No database: the lookup is a
seam and the page is mounted on a bare app.
"""

import re
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

from console import audit_targets as at
from console import deps, queries
from console.routers import audit as audit_router
from console.routers import incoming
from console.templating import templates

CONSOLE = Path(at.__file__).resolve().parent


def uid(n: int) -> str:
    return str(uuid.UUID(int=n))


def row(target_type, target_id, rid=None, action="catalog.amazon_link.set", **over):
    return SimpleNamespace(
        id=rid or uuid.uuid4(),
        created_at=datetime(2026, 10, 6, 11, 45, 26, tzinfo=UTC),
        admin_id=None,
        action=action,
        target_type=target_type,
        target_id=target_id,
        summary="",
        ip=None,
        **over,
    )


class FakeLookup:
    """`names(kind, ids)` from a dict of `{kind: {id: row}}`; records its calls."""

    def __init__(self, data):
        self.data, self.calls = data, []

    async def names(self, kind, ids):
        self.calls.append((kind, set(ids)))
        return {i: r for i, r in self.data.get(kind, {}).items() if i in ids}


# --------------------------------------------------------------------------
# every kind of line has been decided
# --------------------------------------------------------------------------


def _written_target_types() -> set[str]:
    """Every literal `target_type="…"` an audit call in the console passes, plus
    the kinds the calls that pass a variable can carry."""
    found: set[str] = set()
    for path in CONSOLE.rglob("*.py"):
        found.update(re.findall(r'target_type="(\w+)"', path.read_text()))
    from app.services import merge_service  # noqa: PLC0415

    found.update(merge_service.MODELS)  # catalog.rename / merge.apply / merge.undo `kind`
    found.update(incoming.KINDS)  # content.reviewed `kind`
    found.update(incoming.IMAGE_COLUMNS)  # image.remove.<kind> `source`
    return found


def test_every_target_type_the_console_writes_has_been_decided():
    """A new audit call with a new `target_type` fails here until someone says
    where it opens (`OPENS`) or that it is not a record (`NOT_A_RECORD`)."""
    undecided = {
        t
        for t in _written_target_types()
        if at.kind_of(t) not in at.OPENS and at.kind_of(t) not in at.NOT_A_RECORD
    }
    assert not undecided, f"audit targets with no decision in audit_targets.py: {sorted(undecided)}"


def test_the_guard_is_looking_at_something():
    written = _written_target_types()
    assert {"edition", "reader", "promotion", "revision", "review", "email"} <= written
    assert {"authors", "publishers", "series"} <= written, "a merge's kind is read from the service"


def test_plural_and_singular_are_one_kind():
    assert [at.kind_of(t) for t in ("works", "Work", "authors", "publishers", "series")] == [
        "work",
        "work",
        "author",
        "publisher",
        "series",
    ]
    assert at.kind_of(None) is None and at.kind_of("") is None


# --------------------------------------------------------------------------
# what each kind turns into
# --------------------------------------------------------------------------

WORK, EDITION, REVISION, REVIEW, SERIES_REVIEW = uid(1), uid(2), uid(3), uid(4), uid(5)


async def _resolved(rows, data):
    return await at.resolve(rows, FakeLookup(data))


@pytest.mark.asyncio
async def test_an_edition_opens_its_book_and_names_the_printing():
    r = row("edition", EDITION)
    got = await _resolved(
        [r], {"edition": {EDITION: ("Koormam", "9789376881192", uuid.UUID(WORK), False)}}
    )
    assert got[r.id] == at.Target("work", WORK, "Koormam · 9789376881192")


@pytest.mark.asyncio
async def test_an_edition_with_no_isbn_says_so():
    r = row("edition", EDITION)
    got = await _resolved([r], {"edition": {EDITION: ("Koormam", None, uuid.UUID(WORK), False)}})
    assert got[r.id].label == "Koormam · no ISBN"


@pytest.mark.asyncio
async def test_an_edit_opens_the_book_it_is_for():
    r = row("revision", REVISION, action="revision.approve")
    got = await _resolved([r], {"revision": {REVISION: ("Chemmeen", uuid.UUID(WORK), False)}})
    assert got[r.id] == at.Target("work", WORK, "Edit of Chemmeen")


@pytest.mark.asyncio
async def test_a_review_opens_the_book_or_the_series_it_is_of():
    on_book, on_series = row("review", REVIEW), row("review", SERIES_REVIEW)
    got = await _resolved(
        [on_book, on_series],
        {
            "review": {
                REVIEW: ("work", uuid.UUID(WORK), "Chemmeen", False),
                SERIES_REVIEW: ("series", uuid.UUID(uid(9)), "Kayar", False),
            }
        },
    )
    assert got[on_book.id] == at.Target("work", WORK, "Review of Chemmeen")
    assert got[on_series.id] == at.Target("series", uid(9), "Review of Kayar")


@pytest.mark.asyncio
async def test_a_reader_is_named_the_way_the_rest_of_the_console_names_them():
    a, b, c = uid(11), uid(12), uid(13)
    rows = [row("reader", a), row("reader", b), row("reader", c)]
    got = await _resolved(
        rows,
        {
            "reader": {
                a: ("Anaya", "anaya", "anaya@example.com"),
                b: (None, "ravi", "ravi@example.com"),
                c: (None, None, "kim@example.com"),
            }
        },
    )
    assert [got[r.id].label for r in rows] == ["Anaya", "@ravi", "kim@example.com"]
    assert all(got[r.id].kind == "reader" for r in rows)


@pytest.mark.asyncio
async def test_the_catalogue_kinds_resolve_by_name_plural_or_singular():
    rows = [
        row("works", uid(21), action="catalog.rename"),
        row("authors", uid(22), action="merge.apply"),
        row("publisher", uid(23), action="publisher.upload_logo"),
        row("series", uid(24), action="series.add_work"),
        row("promotion", uid(25), action="promotion.publish"),
        row("admin", uid(26), action="admin.invite"),
    ]
    got = await _resolved(
        rows,
        {
            "work": {uid(21): ("Aadujeevitham", False)},
            "author": {uid(22): ("Benyamin",)},
            "publisher": {uid(23): ("DC Books",)},
            "series": {uid(24): ("Kayar",)},
            "promotion": {uid(25): ("Diwali banner",)},
            "admin": {uid(26): ("op@kitabi.in",)},
        },
    )
    assert [(got[r.id].kind, got[r.id].label) for r in rows] == [
        ("work", "Aadujeevitham"),
        ("author", "Benyamin"),
        ("publisher", "DC Books"),
        ("series", "Kayar"),
        ("promotion", "Diwali banner"),
        ("admin", "op@kitabi.in"),
    ]


@pytest.mark.asyncio
async def test_a_deleted_book_is_named_and_marked_not_linked():
    """Its page bounces to the catalogue: a link would land somewhere else."""
    r, e = row("work", WORK, action="work.delete"), row("edition", EDITION)
    got = await _resolved(
        [r, e],
        {
            "work": {WORK: ("The Wild Duck", True)},
            "edition": {EDITION: ("The Wild Duck", "9780000000002", uuid.UUID(WORK), True)},
        },
    )
    assert got[r.id] == at.Target("work", WORK, "The Wild Duck · deleted", linked=False)
    assert got[e.id].linked is False and got[e.id].label.endswith("· deleted")


@pytest.mark.asyncio
async def test_a_record_that_is_gone_is_marked_not_linked_and_the_row_stays():
    r = row("promotion", uid(31), action="promotion.edit_content")
    got = await _resolved([r], {})
    assert got[r.id] == at.Target(
        "promotion", uid(31), f"{uid(31)[:12]} · record gone", linked=False
    )


@pytest.mark.asyncio
async def test_what_is_not_a_record_is_left_for_the_old_text():
    rows = [
        row("email", "someone@example.com", action="auth.fail"),  # a sign-in attempt
        row(None, None, action="auth.success"),
        row("work", None),
        row("edition", "not-a-uuid"),
        row("mystery", uid(40)),
    ]
    assert await _resolved(rows, {}) == {}


@pytest.mark.asyncio
async def test_a_page_costs_one_query_per_kind_not_one_per_row():
    rows = [row("edition", uid(100 + n)) for n in range(40)] + [row("reader", uid(200))]
    lookup = FakeLookup({})
    await at.resolve(rows, lookup)
    assert sorted(kind for kind, _ in lookup.calls) == ["edition", "reader"]
    assert len(dict(lookup.calls)["edition"]) == 40


@pytest.mark.asyncio
async def test_a_long_title_is_clipped_in_the_column_not_in_the_tooltip():
    r = row("edition", EDITION)
    got = await _resolved(
        [r], {"edition": {EDITION: ("x" * 300, "9789376881192", uuid.UUID(WORK), False)}}
    )
    assert len(got[r.id].label) <= at.MAX_LABEL and got[r.id].label.endswith("…")


# --------------------------------------------------------------------------
# the page
# --------------------------------------------------------------------------


class _Result:
    def __init__(self, rows):
        self._rows = rows

    def scalars(self):
        return SimpleNamespace(all=lambda: self._rows)

    def all(self):
        return self._rows


class _DB:
    def __init__(self, rows):
        self.rows = rows

    async def scalar(self, _stmt):  # noqa: ANN001, ANN202
        return len(self.rows)

    async def execute(self, stmt):  # noqa: ANN001, ANN202
        return _Result(self.rows if "admin_audit_log" in str(stmt) else [])


@pytest.fixture
def page(monkeypatch):
    state = {"rows": [], "role": "editor", "data": {}}

    async def badges(db):  # noqa: ANN001
        return {"claims": 0, "revisions": 0, "reports": 0, "merges": 0, "promotions_live": 0}

    async def names(self, kind, ids):  # noqa: ANN001
        return {i: r for i, r in state["data"].get(kind, {}).items() if i in ids}

    monkeypatch.setattr(queries, "nav_badges", badges)
    monkeypatch.setattr(at.DbLookup, "names", names)
    monkeypatch.setattr(templates.env, "undefined", StrictUndefined)

    app = FastAPI()
    app.include_router(audit_router.router)
    app.dependency_overrides[deps.current_admin] = lambda: SimpleNamespace(
        id=uuid.UUID(int=99), role=state["role"], email="op@kitabi.in"
    )
    app.dependency_overrides[deps.get_db] = lambda: _DB(state["rows"])
    client = TestClient(app)
    client.state = state
    return client


def test_the_target_is_a_link_to_the_book_with_the_title_and_isbn(page):
    page.state["rows"] = [row("edition", EDITION)]
    page.state["data"] = {
        "edition": {EDITION: ("Koormam", "9789376881192", uuid.UUID(WORK), False)}
    }
    html = page.get("/audit").text
    assert f'<a href="/catalog/works/{WORK}">Koormam · 9789376881192</a>' in html
    assert f'title="{EDITION}"' in html, "the id is the tooltip"
    assert "edition ·" in html, "the kind is still said"


def test_a_moderator_gets_the_peek_not_a_link_that_would_bounce_them(page):
    page.state["role"] = "moderator"
    page.state["rows"] = [row("edition", EDITION)]
    page.state["data"] = {
        "edition": {EDITION: ("Koormam", "9789376881192", uuid.UUID(WORK), False)}
    }
    html = page.get("/audit").text
    assert f'data-peek="/catalog/peek/works/{WORK}"' in html
    assert f'href="/catalog/works/{WORK}"' not in html


def test_a_deleted_or_vanished_record_is_text_with_no_link(page):
    page.state["rows"] = [
        row("work", WORK, action="work.delete"),
        row("promotion", uid(31), action="promotion.delete"),
    ]
    page.state["data"] = {"work": {WORK: ("The Wild Duck", True)}}
    html = page.get("/audit").text
    assert "The Wild Duck · deleted" in html and "record gone" in html
    assert f'href="/catalog/works/{WORK}"' not in html
    assert f'href="/promotions/{uid(31)}"' not in html


def test_a_failed_sign_ins_email_and_a_line_with_no_target_are_untouched(page):
    page.state["rows"] = [
        row("email", "someone@example.com", action="auth.fail"),
        row(None, None, action="auth.success"),
    ]
    html = page.get("/audit").text
    assert "email · someone@example.com" in html, "the whole attempted address, not a stub"
    assert 'href="/readers/' not in html
