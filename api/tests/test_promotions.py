"""Promotion serving — the targeting resolver above all.

Targeting is the part of this feature that can be quietly, invisibly wrong: a
rule that matches too widely shows a Malayalam campaign to everyone, and a rule
that matches too narrowly shows it to nobody and looks like "the feature isn't
working". Both fail silently in production, so every rule gets a test here for
the match *and* the non-match.
"""

import uuid
from datetime import UTC, datetime, timedelta

import pytest

from app.models.promotion import (
    CARD_TEXT,
    KIND_BANNER,
    KIND_CARD,
    PLACEMENT_HOME_STREAM,
    PLACEMENT_HOME_TOP,
    STATUS_DRAFT,
    STATUS_PAUSED,
    STATUS_PUBLISHED,
    Promotion,
    PromotionContent,
    PromotionEvent,
)
from app.services import promotion_service


def _now() -> datetime:
    return datetime.now(UTC)


async def _make_promo(
    sessionmaker,
    *,
    name="Test campaign",
    kind=KIND_BANNER,
    placement=PLACEMENT_HOME_TOP,
    status=STATUS_PUBLISHED,
    targeting=None,
    frequency=None,
    priority=5,
    starts_at=None,
    ends_at=None,
    sponsor=None,
    card_style=None,
    contents=((None, "Default headline"),),
) -> uuid.UUID:
    """Create a campaign with one content row per (language, headline) pair."""
    promo_id = uuid.uuid4()
    async with sessionmaker() as db:
        db.add(
            Promotion(
                id=promo_id,
                name=name,
                kind=kind,
                card_style=card_style,
                placement=placement,
                status=status,
                sponsor=sponsor,
                priority=priority,
                starts_at=starts_at if starts_at is not None else _now() - timedelta(days=1),
                ends_at=ends_at,
                targeting=targeting or {},
                frequency=frequency or {},
            )
        )
        for language, headline in contents:
            db.add(PromotionContent(promotion_id=promo_id, language=language, headline=headline))
        await db.commit()
    return promo_id


async def _resolve(sessionmaker, user, **kwargs) -> list[dict]:
    async with sessionmaker() as db:
        return await promotion_service.resolve_for_reader(db, uuid.UUID(user["id"]), **kwargs)


# ---------------------------------------------------------------- basics


async def test_nothing_published_returns_empty(client):
    await client.post("/auth/bootstrap")
    resp = await client.get("/promotions")
    assert resp.status_code == 200
    assert resp.json()["promotions"] == []


async def test_live_promotion_is_served_with_default_copy(client, db_sessionmaker):
    await client.post("/auth/bootstrap")
    await _make_promo(db_sessionmaker, contents=((None, "Trivandrum Book Fair"),))
    body = (await client.get("/promotions")).json()
    assert len(body["promotions"]) == 1
    promo = body["promotions"][0]
    assert promo["headline"] == "Trivandrum Book Fair"
    assert promo["kind"] == KIND_BANNER
    assert promo["dismissible"] is True  # default
    assert promo["language"] is None


@pytest.mark.parametrize(
    "status,starts,ends,served",
    [
        (STATUS_DRAFT, -1, None, False),
        (STATUS_PAUSED, -1, None, False),
        (STATUS_PUBLISHED, 1, None, False),  # scheduled, not started
        (STATUS_PUBLISHED, -2, -1, False),  # ended
        (STATUS_PUBLISHED, -1, 1, True),  # live, inside window
        (STATUS_PUBLISHED, -1, None, True),  # live, open-ended
    ],
)
async def test_only_published_and_in_window_is_served(
    client, db_sessionmaker, status, starts, ends, served
):
    await client.post("/auth/bootstrap")
    await _make_promo(
        db_sessionmaker,
        status=status,
        starts_at=_now() + timedelta(days=starts),
        ends_at=_now() + timedelta(days=ends) if ends is not None else None,
    )
    body = (await client.get("/promotions")).json()
    assert (len(body["promotions"]) == 1) is served


async def test_effective_state_is_derived_from_dates_not_stored():
    """Nothing runs on a timer to flip a finished campaign — so there is no day
    on which the timer didn't run and an ended campaign is still live."""
    now = _now()
    published = Promotion(
        id=uuid.uuid4(), name="x", status=STATUS_PUBLISHED, starts_at=None, ends_at=None
    )
    assert promotion_service.effective_state(published, now) == "live"
    published.starts_at = now + timedelta(days=1)
    assert promotion_service.effective_state(published, now) == "scheduled"
    published.starts_at, published.ends_at = now - timedelta(days=2), now - timedelta(days=1)
    assert promotion_service.effective_state(published, now) == "ended"
    published.status = STATUS_PAUSED
    assert promotion_service.effective_state(published, now) == "paused"
    published.status = STATUS_DRAFT
    assert promotion_service.effective_state(published, now) == "draft"


# ---------------------------------------------------------------- language


async def test_language_targeting_includes_and_excludes(client, db_sessionmaker, user):
    """The headline case: a Malayalam campaign reaches Malayalam readers."""
    await client.post("/auth/bootstrap")
    await client.patch("/me", json={"preferred_languages": ["Tamil"]})
    await _make_promo(db_sessionmaker, targeting={"languages": ["Malayalam"]})

    assert await _resolve(db_sessionmaker, user) == []

    await client.patch("/me", json={"preferred_languages": ["Malayalam", "English"]})
    assert len(await _resolve(db_sessionmaker, user)) == 1


async def test_variant_picked_by_readers_first_matching_language(client, db_sessionmaker, user):
    await client.post("/auth/bootstrap")
    await client.patch("/me", json={"preferred_languages": ["Malayalam", "English"]})
    await _make_promo(
        db_sessionmaker,
        targeting={"languages": ["Malayalam", "English"]},
        contents=((None, "Onam reading season"), ("Malayalam", "ഓണം വായനക്കാലം")),
    )
    resolved = await _resolve(db_sessionmaker, user)
    assert resolved[0]["headline"] == "ഓണം വായനക്കാലം"
    assert resolved[0]["language"] == "Malayalam"


async def test_reader_without_that_language_falls_back_to_default_variant(
    client, db_sessionmaker, user
):
    await client.post("/auth/bootstrap")
    await client.patch("/me", json={"preferred_languages": ["English"]})
    await _make_promo(
        db_sessionmaker,
        targeting={"languages": ["Malayalam", "English"]},
        contents=((None, "Onam reading season"), ("Malayalam", "ഓണം വായനക്കാലം")),
    )
    resolved = await _resolve(db_sessionmaker, user)
    assert resolved[0]["headline"] == "Onam reading season"
    assert resolved[0]["language"] is None


async def test_no_default_and_no_matching_variant_is_skipped_entirely(
    client, db_sessionmaker, user
):
    """Better to show nothing than to show a reader copy in a language they
    never asked for."""
    await client.post("/auth/bootstrap")
    await client.patch("/me", json={"preferred_languages": ["English"]})
    await _make_promo(
        db_sessionmaker,
        targeting={},  # eligible…
        contents=(("Malayalam", "ഓണം വായനക്കാലം"),),  # …but nothing to say to them
    )
    assert await _resolve(db_sessionmaker, user) == []


# ---------------------------------------------------------------- device rules


async def test_platform_targeting_and_unknown_platform_fails_closed(client, db_sessionmaker, user):
    await client.post("/auth/bootstrap")
    await _make_promo(db_sessionmaker, targeting={"platform": ["android"]})

    assert len(await _resolve(db_sessionmaker, user, platform="android")) == 1
    assert await _resolve(db_sessionmaker, user, platform="ios") == []
    # A build too old to send X-Platform must not receive a platform-targeted
    # campaign — showing it to someone you can't verify is the wrong direction.
    assert await _resolve(db_sessionmaker, user, platform=None) == []


@pytest.mark.parametrize(
    "version,served",
    [("0.1.0", False), ("0.2.0", True), ("0.9.1", True), ("1.0.0", False), (None, False)],
)
async def test_app_version_window(client, db_sessionmaker, user, version, served):
    await client.post("/auth/bootstrap")
    await _make_promo(
        db_sessionmaker, targeting={"app_version_min": "0.2.0", "app_version_max": "0.9.9"}
    )
    resolved = await _resolve(db_sessionmaker, user, app_version=version)
    assert (len(resolved) == 1) is served


def test_parse_version_rejects_junk():
    assert promotion_service.parse_version("1.2.3") == (1, 2, 3)
    assert promotion_service.parse_version("1.2.3+42") == (1, 2, 3)
    assert promotion_service.parse_version("beta") is None
    assert promotion_service.parse_version(None) is None


# ---------------------------------------------------------------- library rules


async def test_library_size_and_status_and_genre_rules(client, db_sessionmaker, user):
    await client.post("/auth/bootstrap")
    size_promo = await _make_promo(
        db_sessionmaker, targeting={"library_size": {"min": 1}}, name="has books"
    )
    assert await _resolve(db_sessionmaker, user) == []

    # Give the reader a book, via the real catalog + library path.
    created = await client.post(
        "/catalog/works",
        json={
            "title": "Goat Days",
            "author_names": ["Benyamin"],
            "language": "Malayalam",
            "genre_names": ["Fiction"],
        },
    )
    assert created.status_code in (200, 201), created.text
    work = created.json()
    edition_id = work["editions"][0]["id"]
    async with db_sessionmaker() as db:
        from app.models.library_entry import LibraryEntry

        db.add(
            LibraryEntry(
                id=uuid.uuid4(),
                user_id=uuid.UUID(user["id"]),
                edition_id=uuid.UUID(edition_id),
                status="reading",
            )
        )
        await db.commit()

    assert len(await _resolve(db_sessionmaker, user)) == 1

    async with db_sessionmaker() as db:
        promo = await db.get(Promotion, size_promo)
        promo.targeting = {"has_status": ["read"]}
        await db.commit()
    assert await _resolve(db_sessionmaker, user) == []

    async with db_sessionmaker() as db:
        promo = await db.get(Promotion, size_promo)
        promo.targeting = {"has_status": ["reading"]}
        await db.commit()
    assert len(await _resolve(db_sessionmaker, user)) == 1

    async with db_sessionmaker() as db:
        promo = await db.get(Promotion, size_promo)
        promo.targeting = {"genres": ["Fiction"]}
        await db.commit()
    assert len(await _resolve(db_sessionmaker, user)) == 1

    async with db_sessionmaker() as db:
        promo = await db.get(Promotion, size_promo)
        promo.targeting = {"genres": ["Poetry"]}
        await db.commit()
    assert await _resolve(db_sessionmaker, user) == []


async def test_account_age_targets_new_readers(client, db_sessionmaker, user):
    await client.post("/auth/bootstrap")
    await _make_promo(db_sessionmaker, targeting={"account_age_days": {"max": 7}})
    assert len(await _resolve(db_sessionmaker, user)) == 1

    async with db_sessionmaker() as db:
        from app.models.profile import Profile

        profile = await db.get(Profile, uuid.UUID(user["id"]))
        profile.created_at = _now() - timedelta(days=30)
        await db.commit()
    assert await _resolve(db_sessionmaker, user) == []


# ---------------------------------------------------------------- reader lists


async def test_reader_ids_and_exclusions(client, db_sessionmaker, user):
    await client.post("/auth/bootstrap")
    promo_id = await _make_promo(db_sessionmaker, targeting={"reader_ids": [str(uuid.uuid4())]})
    assert await _resolve(db_sessionmaker, user) == []

    async with db_sessionmaker() as db:
        promo = await db.get(Promotion, promo_id)
        promo.targeting = {"reader_ids": [user["id"]]}
        await db.commit()
    assert len(await _resolve(db_sessionmaker, user)) == 1

    async with db_sessionmaker() as db:
        promo = await db.get(Promotion, promo_id)
        promo.targeting = {"exclude_reader_ids": [user["id"]]}
        await db.commit()
    assert await _resolve(db_sessionmaker, user) == []


def test_rollout_bucket_is_stable_and_salted_per_campaign():
    """A reader must always land on the same side of a partial rollout, or the
    promo flickers between fetches and the metrics mean nothing."""
    # Fixed ids, not uuid4 — with two random campaigns, "they land in different
    # buckets" is a 1-in-100 coin flip and the test flakes on the hundredth run.
    reader, promo = uuid.UUID(int=1), uuid.UUID(int=2)
    first = promotion_service.rollout_bucket(promo, reader)
    assert first == promotion_service.rollout_bucket(promo, reader)
    assert 0 <= first < 100
    # Salted by campaign, so a 10% rollout doesn't always pick the same tenth
    # of readers: one reader across 50 campaigns must spread across buckets.
    buckets = {promotion_service.rollout_bucket(uuid.UUID(int=i), reader) for i in range(50)}
    assert len(buckets) > 10


async def test_rollout_zero_and_hundred(client, db_sessionmaker, user):
    await client.post("/auth/bootstrap")
    promo_id = await _make_promo(db_sessionmaker, targeting={"rollout_percent": 0})
    assert await _resolve(db_sessionmaker, user) == []
    async with db_sessionmaker() as db:
        promo = await db.get(Promotion, promo_id)
        promo.targeting = {"rollout_percent": 100}
        await db.commit()
    assert len(await _resolve(db_sessionmaker, user)) == 1


# ---------------------------------------------------------------- placement caps


async def test_one_per_placement_highest_priority_wins(client, db_sessionmaker, user):
    await client.post("/auth/bootstrap")
    await _make_promo(db_sessionmaker, name="low", priority=1, contents=((None, "Low priority"),))
    await _make_promo(db_sessionmaker, name="high", priority=9, contents=((None, "High priority"),))
    resolved = await _resolve(db_sessionmaker, user)
    assert len(resolved) == 1
    assert resolved[0]["headline"] == "High priority"


async def test_banner_and_card_can_both_show_but_never_two_of_either(client, db_sessionmaker, user):
    await client.post("/auth/bootstrap")
    await _make_promo(db_sessionmaker, name="banner", contents=((None, "Banner"),))
    await _make_promo(
        db_sessionmaker,
        name="card",
        kind=KIND_CARD,
        card_style=CARD_TEXT,
        placement=PLACEMENT_HOME_STREAM,
        contents=((None, "Card"),),
    )
    await _make_promo(
        db_sessionmaker,
        name="second card",
        kind=KIND_CARD,
        card_style=CARD_TEXT,
        placement=PLACEMENT_HOME_STREAM,
        contents=((None, "Second card"),),
    )
    resolved = await _resolve(db_sessionmaker, user)
    assert len(resolved) == 2
    assert {p["placement"] for p in resolved} == {PLACEMENT_HOME_TOP, PLACEMENT_HOME_STREAM}


# ---------------------------------------------------------------- frequency


async def _event(sessionmaker, promo_id, user, kind, *, when=None, language=None):
    async with sessionmaker() as db:
        db.add(
            PromotionEvent(
                id=uuid.uuid4(),
                promotion_id=promo_id,
                user_id=uuid.UUID(user["id"]),
                kind=kind,
                language=language,
                occurred_at=when or _now(),
            )
        )
        await db.commit()


async def test_dismissal_is_permanent_by_default(client, db_sessionmaker, user):
    await client.post("/auth/bootstrap")
    promo_id = await _make_promo(db_sessionmaker)
    assert len(await _resolve(db_sessionmaker, user)) == 1
    await _event(db_sessionmaker, promo_id, user, "dismiss")
    assert await _resolve(db_sessionmaker, user) == []


async def test_redisplay_after_days_brings_it_back(client, db_sessionmaker, user):
    await client.post("/auth/bootstrap")
    promo_id = await _make_promo(
        db_sessionmaker, frequency={"redisplay_after_days": 7, "min_hours_between": 0}
    )
    await _event(db_sessionmaker, promo_id, user, "dismiss", when=_now() - timedelta(days=3))
    assert await _resolve(db_sessionmaker, user) == []
    async with db_sessionmaker() as db:
        promo = await db.get(Promotion, promo_id)
        promo.frequency = {"redisplay_after_days": 1, "min_hours_between": 0}
        await db.commit()
    assert len(await _resolve(db_sessionmaker, user)) == 1


async def test_max_impressions_stops_it(client, db_sessionmaker, user):
    await client.post("/auth/bootstrap")
    promo_id = await _make_promo(
        db_sessionmaker, frequency={"max_impressions": 2, "min_hours_between": 0}
    )
    await _event(db_sessionmaker, promo_id, user, "impression")
    assert len(await _resolve(db_sessionmaker, user)) == 1
    await _event(db_sessionmaker, promo_id, user, "impression")
    assert await _resolve(db_sessionmaker, user) == []


async def test_cooldown_defaults_to_24h_and_is_honoured(client, db_sessionmaker, user):
    """Not zero, deliberately: the same strip on every cold start is how a
    promotion becomes a grievance."""
    await client.post("/auth/bootstrap")
    promo_id = await _make_promo(db_sessionmaker)  # no frequency set at all
    await _event(db_sessionmaker, promo_id, user, "impression", when=_now() - timedelta(hours=2))
    assert await _resolve(db_sessionmaker, user) == []
    await _event(db_sessionmaker, promo_id, user, "impression", when=_now() - timedelta(hours=30))
    # Still blocked — the *most recent* impression is what counts.
    assert await _resolve(db_sessionmaker, user) == []


async def test_cooldown_expires(client, db_sessionmaker, user):
    await client.post("/auth/bootstrap")
    promo_id = await _make_promo(db_sessionmaker)
    await _event(db_sessionmaker, promo_id, user, "impression", when=_now() - timedelta(hours=30))
    assert len(await _resolve(db_sessionmaker, user)) == 1


# ---------------------------------------------------------------- events API


async def test_events_are_idempotent_on_client_generated_id(client, db_sessionmaker):
    await client.post("/auth/bootstrap")
    promo_id = await _make_promo(db_sessionmaker)
    event = {
        "id": str(uuid.uuid4()),
        "promotion_id": str(promo_id),
        "kind": "impression",
        "occurred_at": _now().isoformat(),
    }
    assert (await client.post("/promotions/events", json={"events": [event]})).status_code == 200
    # The same batch replayed by a retrying outbox must not double-count.
    assert (await client.post("/promotions/events", json={"events": [event]})).status_code == 200
    async with db_sessionmaker() as db:
        from sqlalchemy import func, select

        count = await db.scalar(select(func.count()).select_from(PromotionEvent))
    assert count == 1


async def test_event_for_unknown_promotion_is_dropped_not_rejected(client, db_sessionmaker):
    """A 4xx here would make the app's outbox retry a batch that can never
    succeed."""
    await client.post("/auth/bootstrap")
    resp = await client.post(
        "/promotions/events",
        json={
            "events": [
                {
                    "id": str(uuid.uuid4()),
                    "promotion_id": str(uuid.uuid4()),
                    "kind": "dismiss",
                    "occurred_at": _now().isoformat(),
                }
            ]
        },
    )
    assert resp.status_code == 200
    assert resp.json()["accepted"] == 0


async def test_bad_event_kind_is_a_422(client, db_sessionmaker):
    await client.post("/auth/bootstrap")
    promo_id = await _make_promo(db_sessionmaker)
    resp = await client.post(
        "/promotions/events",
        json={
            "events": [
                {
                    "id": str(uuid.uuid4()),
                    "promotion_id": str(promo_id),
                    "kind": "purchased",
                    "occurred_at": _now().isoformat(),
                }
            ]
        },
    )
    assert resp.status_code == 422


async def test_dismiss_through_the_api_stops_it_being_served(client, db_sessionmaker):
    await client.post("/auth/bootstrap")
    promo_id = await _make_promo(db_sessionmaker)
    assert len((await client.get("/promotions")).json()["promotions"]) == 1
    await client.post(
        "/promotions/events",
        json={
            "events": [
                {
                    "id": str(uuid.uuid4()),
                    "promotion_id": str(promo_id),
                    "kind": "dismiss",
                    "occurred_at": _now().isoformat(),
                }
            ]
        },
    )
    assert (await client.get("/promotions")).json()["promotions"] == []


# ---------------------------------------------------------------- transport


async def test_etag_makes_the_repeat_poll_a_304(client, db_sessionmaker):
    await client.post("/auth/bootstrap")
    await _make_promo(db_sessionmaker)
    first = await client.get("/promotions")
    etag = first.headers["etag"]
    again = await client.get("/promotions", headers={"If-None-Match": etag})
    assert again.status_code == 304


async def test_opt_out_stops_delivery_entirely(client, db_sessionmaker):
    await client.post("/auth/bootstrap")
    await _make_promo(db_sessionmaker)
    assert len((await client.get("/promotions")).json()["promotions"]) == 1
    await client.patch("/me", json={"promotions_opt_out": True})
    # Not hidden in the app — never sent.
    assert (await client.get("/promotions")).json()["promotions"] == []


# ---------------------------------------------------------------- estimate


async def test_audience_estimate_agrees_with_what_is_served(client, db_sessionmaker, user):
    await client.post("/auth/bootstrap")
    await client.patch("/me", json={"preferred_languages": ["Malayalam"]})
    async with db_sessionmaker() as db:
        estimate = await promotion_service.estimate_audience(db, {"languages": ["Malayalam"]})
    assert estimate == {
        "matched": 1,
        "total": 1,
        "opted_out": 0,
        "rollout_percent": None,
        "ignores_device_rules": False,
    }
    async with db_sessionmaker() as db:
        miss = await promotion_service.estimate_audience(db, {"languages": ["Tamil"]})
    assert miss["matched"] == 0


async def test_opted_out_readers_leave_the_denominator_too(client, db_sessionmaker):
    """Otherwise the console shows "Everyone: 3" beside "of 4 readers" on the
    same panel — two numbers that are each right and together read as a bug."""
    await client.post("/auth/bootstrap")
    await client.patch("/me", json={"promotions_opt_out": True})
    async with db_sessionmaker() as db:
        estimate = await promotion_service.estimate_audience(db, {})
    assert estimate["total"] == 0
    assert estimate["matched"] == 0
    assert estimate["opted_out"] == 1


async def test_estimate_flags_that_it_cannot_honour_device_rules(client, db_sessionmaker):
    """Platform and app version are per-install, not per-reader — the estimate
    says so rather than quietly reporting a number that ignores them."""
    await client.post("/auth/bootstrap")
    async with db_sessionmaker() as db:
        estimate = await promotion_service.estimate_audience(db, {"platform": ["ios"]})
    assert estimate["ignores_device_rules"] is True
    assert estimate["matched"] == 1
