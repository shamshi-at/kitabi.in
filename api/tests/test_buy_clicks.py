"""Buy-link clicks: who opened which shop for which book (5 Oct 2026).

Two doors and they are tested apart, because they make different promises.

**The app's** names the reader — the owner asked for *who* — and must be safe
to retry: the outbox resends a whole batch when the network drops mid-reply.

**The website's** is the one write the public web is allowed (CLAUDE.md names
it as the exception to "strictly read-only"). What is pinned for it is how
little it can do: it stores nothing about the visitor, it cannot be made to
record a book or a shop that does not exist, it never tells a caller which of
those was the problem, and there is a ceiling on how many it will take.
"""

import uuid
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import select

from app.models import SURFACE_APP, SURFACE_WEB, BuyClick, Edition
from app.services import buy_click_service, buy_links

from .test_public_pages import _seed_book


@pytest.fixture(autouse=True)
def _fresh_web_limits():
    buy_click_service.reset_web_limits()
    yield
    buy_click_service.reset_web_limits()


async def _book(db_sessionmaker, **kw) -> tuple[uuid.UUID, uuid.UUID]:
    """A live book; returns (work id, edition id)."""
    async with db_sessionmaker() as db:
        work, _ = await _seed_book(db, **kw)
        edition = (await db.execute(select(Edition).where(Edition.work_id == work.id))).scalar_one()
        return work.id, edition.id


async def _clicks(db_sessionmaker) -> list[BuyClick]:
    async with db_sessionmaker() as db:
        return list(
            (await db.execute(select(BuyClick).order_by(BuyClick.occurred_at))).scalars().all()
        )


def _event(edition_id, **over) -> dict:
    return {
        "id": str(uuid.uuid4()),
        "edition_id": str(edition_id),
        "retailer": "Amazon",
        "affiliate": True,
        "occurred_at": datetime.now(UTC).isoformat(),
        **over,
    }


# --------------------------------------------------------------------------
# the vocabulary
# --------------------------------------------------------------------------


def test_a_shop_is_recorded_under_its_key_however_the_client_spells_it():
    """The link the clients are served says "Amazon"; the row says "amazon"."""
    assert buy_links.retailer_key("Amazon") == "amazon"
    assert buy_links.retailer_key(" amazon ") == "amazon"
    assert buy_links.retailer_key("Flipkart") is None, "not a shop we serve"
    assert buy_links.retailer_key(None) is None
    assert buy_links.retailer_key({"x": 1}) is None


def test_every_served_link_names_a_shop_the_click_log_knows():
    """The day a second shop is added to `merged`, this fails until its key is
    in `RETAILER_KEYS` — otherwise its clicks would be dropped as unknown and
    the report would show the new button as a button nobody presses."""
    for link in buy_links.merged(
        None, isbn="9788126412808", title="Kayar", author=None, amazon_tag="kitabi-21"
    ):
        assert buy_links.retailer_key(link["retailer"]) is not None, link["retailer"]


# --------------------------------------------------------------------------
# the app's door
# --------------------------------------------------------------------------


async def test_the_app_records_who_clicked_which_shop_for_which_book(client, db_sessionmaker, user):
    work_id, edition_id = await _book(db_sessionmaker)

    resp = await client.post("/buy-clicks", json={"events": [_event(edition_id)]})

    assert resp.status_code == 200 and resp.json() == {"accepted": 1}
    (click,) = await _clicks(db_sessionmaker)
    assert str(click.user_id) == user["id"]
    assert click.work_id == work_id, "the book is resolved here, not trusted from the device"
    assert click.edition_id == edition_id
    assert click.retailer == "amazon"
    assert click.surface == SURFACE_APP
    assert click.affiliate is True


async def test_a_retried_batch_is_not_counted_twice(client, db_sessionmaker):
    """The outbox resends everything it could not confirm."""
    _, edition_id = await _book(db_sessionmaker)
    batch = {"events": [_event(edition_id), _event(edition_id)]}

    await client.post("/buy-clicks", json=batch)
    await client.post("/buy-clicks", json=batch)

    assert len(await _clicks(db_sessionmaker)) == 2


async def test_one_bad_event_does_not_lose_the_batch(client, db_sessionmaker):
    """An edition removed since the tap, or a shop this server does not serve,
    is dropped — and the response is still a 200, or the app's outbox would
    retry a batch that can never succeed."""
    _, edition_id = await _book(db_sessionmaker)
    resp = await client.post(
        "/buy-clicks",
        json={
            "events": [
                _event(edition_id),
                _event(uuid.uuid4()),
                _event(edition_id, retailer="Flipkart"),
            ]
        },
    )
    assert resp.status_code == 200 and resp.json() == {"accepted": 1}
    assert len(await _clicks(db_sessionmaker)) == 1


async def test_a_click_on_a_removed_book_is_not_recorded(client, db_sessionmaker):
    work_id, edition_id = await _book(db_sessionmaker)
    async with db_sessionmaker() as db:
        from app.models import Work  # noqa: PLC0415

        work = await db.get(Work, work_id)
        work.deleted_at = datetime.now(UTC)
        await db.commit()

    resp = await client.post("/buy-clicks", json={"events": [_event(edition_id)]})

    assert resp.json() == {"accepted": 0}
    assert await _clicks(db_sessionmaker) == []


async def test_a_phone_with_a_wrong_clock_does_not_put_a_click_in_the_wrong_year(
    client, db_sessionmaker
):
    """`occurred_at` is the device's word. A clock set to 2031, or 1970, would
    file the click under a week no report will ever show."""
    _, edition_id = await _book(db_sessionmaker)
    now = datetime.now(UTC)
    await client.post(
        "/buy-clicks",
        json={
            "events": [
                _event(edition_id, occurred_at=(now + timedelta(days=400)).isoformat()),
                _event(edition_id, occurred_at="1970-01-01T00:00:00Z"),
                _event(edition_id, occurred_at=(now - timedelta(days=3)).isoformat()),
            ]
        },
    )
    times = sorted(c.occurred_at for c in await _clicks(db_sessionmaker))
    assert times[0] < now - timedelta(days=2), "a click reported three days late keeps its day"
    assert all(
        abs(t - now) < timedelta(minutes=5) for t in times[1:]
    ), "the two impossible ones are stamped with when they arrived"


async def test_an_empty_batch_is_fine(client):
    resp = await client.post("/buy-clicks", json={"events": []})
    assert resp.status_code == 200 and resp.json() == {"accepted": 0}


async def test_the_apps_door_needs_a_signed_in_reader(unauthenticated_client, db_sessionmaker):
    _, edition_id = await _book(db_sessionmaker)
    resp = await unauthenticated_client.post("/buy-clicks", json={"events": [_event(edition_id)]})
    assert resp.status_code == 401
    assert await _clicks(db_sessionmaker) == []


# --------------------------------------------------------------------------
# the website's door — the one write the public web makes
# --------------------------------------------------------------------------


async def _beacon(http, body, **headers):
    """What `navigator.sendBeacon(url, string)` sends: text/plain, not JSON."""
    content = body if isinstance(body, bytes | str) else __import__("json").dumps(body)
    return await http.post(
        "/public/buy-click",
        content=content,
        headers={"content-type": "text/plain;charset=UTF-8", **headers},
    )


async def test_a_website_click_is_recorded_with_nobody_attached(
    unauthenticated_client, db_sessionmaker
):
    work_id, edition_id = await _book(db_sessionmaker)

    resp = await _beacon(
        unauthenticated_client,
        {"edition_id": str(edition_id), "retailer": "Amazon", "affiliate": True},
        **{"user-agent": "Mozilla/5.0 (iPhone) Safari/605.1.15"},
    )

    assert resp.status_code == 204
    (click,) = await _clicks(db_sessionmaker)
    assert click.user_id is None
    assert click.surface == SURFACE_WEB
    assert (click.work_id, click.edition_id, click.retailer) == (work_id, edition_id, "amazon")


def test_the_table_has_nowhere_to_keep_a_visitor():
    """The privacy policy says a website click is counted without identifying
    the visitor. That is a promise about columns, so it is checked on them: a
    later "let's just store the IP for debugging" fails here first."""
    columns = set(BuyClick.__table__.columns.keys())
    assert columns == {
        "id",
        "user_id",
        "work_id",
        "edition_id",
        "retailer",
        "surface",
        "affiliate",
        "occurred_at",
        "received_at",
    }


@pytest.mark.parametrize(
    "body",
    [
        b"",
        b"not json",
        b"[]",
        b'"a string"',
        b'{"retailer": "Amazon"}',
        b'{"edition_id": "not-a-uuid", "retailer": "Amazon"}',
        b'{"edition_id": "' + str(uuid.uuid4()).encode() + b'", "retailer": "Amazon"}',
        b'{"edition_id": 7, "retailer": {"$ne": null}}',
    ],
)
async def test_junk_is_answered_exactly_like_a_real_click_and_stores_nothing(
    unauthenticated_client, db_sessionmaker, body
):
    """204 either way. An error for "no such edition" would tell a prober
    which of its guesses were real."""
    resp = await _beacon(unauthenticated_client, body)
    assert resp.status_code == 204
    assert await _clicks(db_sessionmaker) == []


async def test_an_unknown_shop_is_not_recorded(unauthenticated_client, db_sessionmaker):
    _, edition_id = await _book(db_sessionmaker)
    resp = await _beacon(
        unauthenticated_client, {"edition_id": str(edition_id), "retailer": "evil.example"}
    )
    assert resp.status_code == 204
    assert await _clicks(db_sessionmaker) == []


async def test_an_oversized_body_is_not_read_as_a_click(unauthenticated_client, db_sessionmaker):
    _, edition_id = await _book(db_sessionmaker)
    body = {"edition_id": str(edition_id), "retailer": "Amazon", "pad": "x" * 2000}
    assert (await _beacon(unauthenticated_client, body)).status_code == 204
    assert await _clicks(db_sessionmaker) == []


@pytest.mark.parametrize(
    "agent",
    [
        "Googlebot/2.1 (+http://www.google.com/bot.html)",
        "WhatsApp/2.23 link preview",
        "HeadlessChrome",
    ],
)
async def test_a_crawler_or_link_preview_is_not_a_reader(
    unauthenticated_client, db_sessionmaker, agent
):
    _, edition_id = await _book(db_sessionmaker)
    resp = await _beacon(
        unauthenticated_client,
        {"edition_id": str(edition_id), "retailer": "Amazon"},
        **{"user-agent": agent},
    )
    assert resp.status_code == 204
    assert await _clicks(db_sessionmaker) == []


async def test_the_anonymous_door_has_a_ceiling(
    unauthenticated_client, db_sessionmaker, monkeypatch
):
    """Nobody can be asked who they are, so the bound is on the door itself."""
    monkeypatch.setattr(buy_click_service, "WEB_PER_MINUTE", 3)
    _, edition_id = await _book(db_sessionmaker)
    for _ in range(8):
        resp = await _beacon(
            unauthenticated_client, {"edition_id": str(edition_id), "retailer": "Amazon"}
        )
        assert resp.status_code == 204, "past the ceiling it is dropped, never refused"
    assert len(await _clicks(db_sessionmaker)) == 3


async def test_junk_does_not_use_up_the_allowance_real_clicks_need(
    unauthenticated_client, db_sessionmaker, monkeypatch
):
    monkeypatch.setattr(buy_click_service, "WEB_PER_MINUTE", 2)
    _, edition_id = await _book(db_sessionmaker)
    for _ in range(10):
        await _beacon(
            unauthenticated_client, {"edition_id": str(uuid.uuid4()), "retailer": "Amazon"}
        )
    await _beacon(unauthenticated_client, {"edition_id": str(edition_id), "retailer": "Amazon"})
    assert len(await _clicks(db_sessionmaker)) == 1


def test_the_ceiling_lets_clicks_through_again_once_the_minute_has_passed(monkeypatch):
    monkeypatch.setattr(buy_click_service, "WEB_PER_MINUTE", 2)
    assert buy_click_service._web_allowed(now=1000.0)
    assert buy_click_service._web_allowed(now=1001.0)
    assert not buy_click_service._web_allowed(now=1002.0)
    assert buy_click_service._web_allowed(now=1061.5), "the first two have aged out"
