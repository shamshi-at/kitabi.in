"""Daily spend limits on the two endpoints that call Anthropic, plus the auth
gate on the ISBN lookup — the only public read that spends OpenLibrary's quota
and writes to our database.

The point of these limits is that auth on those endpoints means "any Google
account", so without them the ceiling on the bill was the caller's patience.
"""

import uuid
from datetime import UTC, datetime, timedelta

import httpx
import pytest
from fastapi import HTTPException
from sqlalchemy import select

from app.core.config import get_settings
from app.models import FEATURE_COVER_EXTRACT, FEATURE_RECOMMENDATIONS, LlmUsage, Rating, Work
from app.services import llm_quota, recommendation_service

_BUCKET = "https://proj.supabase.co/storage/v1/object/public/covers"


def _settings(**overrides):
    """Explicit quota values — never the ambient .env, which a developer may
    have set locally."""
    base = {
        "llm_daily_quota_recommendations": 3,
        "llm_daily_quota_cover_extract": 3,
        "llm_daily_global_cap": 100,
    }
    return get_settings().model_copy(update={**base, **overrides})


async def test_consume_increments_and_returns_the_running_count(db_sessionmaker):
    settings, user_id = _settings(), uuid.uuid4()
    async with db_sessionmaker() as db:
        counts = [
            await llm_quota.consume(db, user_id, FEATURE_RECOMMENDATIONS, settings=settings)
            for _ in range(3)
        ]
    assert counts == [1, 2, 3]


async def test_per_user_quota_rejects_past_the_cap(db_sessionmaker):
    settings, user_id = _settings(llm_daily_quota_recommendations=2), uuid.uuid4()
    async with db_sessionmaker() as db:
        await llm_quota.consume(db, user_id, FEATURE_RECOMMENDATIONS, settings=settings)
        await llm_quota.consume(db, user_id, FEATURE_RECOMMENDATIONS, settings=settings)

        with pytest.raises(HTTPException) as err:
            await llm_quota.consume(db, user_id, FEATURE_RECOMMENDATIONS, settings=settings)

    assert err.value.status_code == 429
    assert err.value.detail["code"] == "quota_exceeded"
    # The app needs to know when to stop asking, so the header is part of the
    # contract, not decoration.
    assert int(err.value.headers["Retry-After"]) > 0


async def test_a_rejected_call_does_not_hand_back_a_free_retry(db_sessionmaker):
    """The counter keeps climbing past the cap. If a rejection rolled the
    increment back, hammering the endpoint would sit forever at cap+1 and every
    other request would be let through."""
    settings, user_id = _settings(llm_daily_quota_recommendations=1), uuid.uuid4()
    async with db_sessionmaker() as db:
        await llm_quota.consume(db, user_id, FEATURE_RECOMMENDATIONS, settings=settings)
        for _ in range(3):
            with pytest.raises(HTTPException):
                await llm_quota.consume(db, user_id, FEATURE_RECOMMENDATIONS, settings=settings)

        stored = await db.scalar(select(LlmUsage.count).where(LlmUsage.user_id == user_id))
    assert stored == 4


async def test_buckets_are_per_user_per_feature_and_per_day(db_sessionmaker):
    settings = _settings(llm_daily_quota_recommendations=1, llm_daily_quota_cover_extract=1)
    user_a, user_b = uuid.uuid4(), uuid.uuid4()
    yesterday = llm_quota.utc_day() - timedelta(days=1)

    async with db_sessionmaker() as db:
        await llm_quota.consume(db, user_a, FEATURE_RECOMMENDATIONS, settings=settings)

        # A different feature, a different reader, and a different day are all
        # separate buckets — none of them is spent by the call above.
        assert await llm_quota.consume(db, user_a, FEATURE_COVER_EXTRACT, settings=settings) == 1
        assert await llm_quota.consume(db, user_b, FEATURE_RECOMMENDATIONS, settings=settings) == 1
        assert (
            await llm_quota.consume(
                db, user_a, FEATURE_RECOMMENDATIONS, settings=settings, day=yesterday
            )
            == 1
        )

        # …but the same bucket is still exhausted.
        with pytest.raises(HTTPException) as err:
            await llm_quota.consume(db, user_a, FEATURE_RECOMMENDATIONS, settings=settings)
    assert err.value.status_code == 429


async def test_global_cap_opens_the_circuit_before_charging_anyone(db_sessionmaker):
    """The breaker is checked first, so a reader doesn't spend their own quota
    on a request that was going to be refused anyway."""
    settings = _settings(llm_daily_global_cap=2, llm_daily_quota_recommendations=50)
    heavy, other = uuid.uuid4(), uuid.uuid4()

    async with db_sessionmaker() as db:
        await llm_quota.consume(db, heavy, FEATURE_RECOMMENDATIONS, settings=settings)
        await llm_quota.consume(db, heavy, FEATURE_RECOMMENDATIONS, settings=settings)

        with pytest.raises(HTTPException) as err:
            await llm_quota.consume(db, other, FEATURE_RECOMMENDATIONS, settings=settings)

        # Vague on purpose — an attacker doesn't need "we hit our budget" confirmed.
        assert err.value.status_code == 503
        assert err.value.detail["code"] == "llm_unavailable"
        # Nothing was charged to the reader who was refused.
        untouched = await db.scalar(select(LlmUsage).where(LlmUsage.user_id == other))
    assert untouched is None


async def test_global_cap_counts_every_feature_together(db_sessionmaker):
    settings = _settings(llm_daily_global_cap=2, llm_daily_quota_cover_extract=50)
    user_id = uuid.uuid4()
    async with db_sessionmaker() as db:
        await llm_quota.consume(db, user_id, FEATURE_RECOMMENDATIONS, settings=settings)
        await llm_quota.consume(db, user_id, FEATURE_COVER_EXTRACT, settings=settings)

        with pytest.raises(HTTPException) as err:
            await llm_quota.consume(db, user_id, FEATURE_COVER_EXTRACT, settings=settings)
    assert err.value.status_code == 503


async def test_zero_means_no_limit(db_sessionmaker):
    settings = _settings(llm_daily_quota_recommendations=0, llm_daily_global_cap=0)
    user_id = uuid.uuid4()
    async with db_sessionmaker() as db:
        for _ in range(6):
            await llm_quota.consume(db, user_id, FEATURE_RECOMMENDATIONS, settings=settings)
        stored = await db.scalar(select(LlmUsage.count).where(LlmUsage.user_id == user_id))
    assert stored == 6


async def test_unknown_feature_is_a_programming_error_not_a_free_bucket(db_sessionmaker):
    async with db_sessionmaker() as db:
        with pytest.raises(ValueError):
            await llm_quota.consume(db, uuid.uuid4(), "made_up", settings=_settings())


def test_retry_after_is_the_seconds_left_until_utc_midnight():
    at = datetime(2026, 8, 4, 23, 0, 0, tzinfo=UTC)
    assert llm_quota._seconds_until_reset(at) == 3600


# --------------------------------------------------------------------------
# Where the recommendations meter sits
# --------------------------------------------------------------------------


async def test_cold_start_recommendations_spend_no_quota(db_sessionmaker, monkeypatch):
    """A reader with no ratings yet gets `[]` without Anthropic ever being
    called, so re-opening that screen must not eat their daily allowance. This
    is why the meter lives next to the call in the service and not in the
    router — every early return above it is free."""
    settings = _settings(anthropic_api_key="test-key")
    monkeypatch.setattr("app.services.recommendation_service.get_settings", lambda: settings)
    user_id = uuid.uuid4()

    async with db_sessionmaker() as db:
        assert await recommendation_service.recommend(db, user_id) == []
        spent = await db.scalar(select(LlmUsage).where(LlmUsage.user_id == user_id))
    assert spent is None


async def test_a_real_recommendation_run_is_metered(db_sessionmaker, monkeypatch):
    settings = _settings(anthropic_api_key="test-key")
    monkeypatch.setattr("app.services.recommendation_service.get_settings", lambda: settings)
    user_id = uuid.uuid4()

    async def _reply(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200, json={"content": [{"type": "text", "text": '[{"work_id": "x", "why": "y"}]'}]}
        )

    async with db_sessionmaker() as db:
        rated = Work(title="Chemmeen")
        db.add_all([rated, Work(title="Kayar")])  # …and one candidate to pick from
        await db.flush()
        db.add(Rating(id=uuid.uuid4(), user_id=user_id, work_id=rated.id, value=5))
        await db.commit()

        async with httpx.AsyncClient(transport=httpx.MockTransport(_reply)) as fake:
            await recommendation_service.recommend(db, user_id, client=fake)

        spent = await db.scalar(select(LlmUsage.count).where(LlmUsage.user_id == user_id))
    assert spent == 1


# --------------------------------------------------------------------------
# Through the endpoints
# --------------------------------------------------------------------------


async def test_cover_extract_returns_429_when_the_reader_is_out_of_quota(
    client, db_sessionmaker, user, monkeypatch
):
    """No Anthropic call is made — the quota check sits after every cheap
    rejection and before the paid call, so a 429 costs nothing."""
    settings = _settings(
        anthropic_api_key="test-key",
        supabase_url="https://proj.supabase.co",
        llm_daily_quota_cover_extract=1,
    )
    monkeypatch.setattr("app.api.catalog.get_settings", lambda: settings)

    first = await client.post("/catalog/cover-extract", json={"front_url": f"{_BUCKET}/a.jpg"})
    # The first call passes the quota gate and then fails at the (unreachable,
    # fake-key) Anthropic call — a 502, not a 429. That is the point: the gate
    # let it through.
    assert first.status_code != 429

    second = await client.post("/catalog/cover-extract", json={"front_url": f"{_BUCKET}/b.jpg"})
    assert second.status_code == 429
    assert second.json()["code"] == "quota_exceeded"
    assert "Retry-After" in second.headers


async def test_a_malformed_request_never_spends_quota(client, db_sessionmaker, user, monkeypatch):
    settings = _settings(
        anthropic_api_key="test-key",
        supabase_url="https://proj.supabase.co",
        llm_daily_quota_cover_extract=1,
    )
    monkeypatch.setattr("app.api.catalog.get_settings", lambda: settings)

    # No image at all, then an image from somewhere that isn't our bucket.
    assert (await client.post("/catalog/cover-extract", json={})).status_code == 422
    bad = await client.post("/catalog/cover-extract", json={"front_url": "https://evil.test/x.jpg"})
    assert bad.status_code == 422

    async with db_sessionmaker() as db:
        spent = await db.scalar(select(LlmUsage).where(LlmUsage.user_id == uuid.UUID(user["id"])))
    assert spent is None


async def test_isbn_lookup_requires_a_signed_in_reader(unauthenticated_client):
    """It proxies OpenLibrary and writes to our catalog, so an anonymous
    caller hammering it would get Kitabi rate-limited by a third party and
    fill the catalog with rows nobody asked for."""
    resp = await unauthenticated_client.get("/catalog/isbn/9780802162175")
    assert resp.status_code == 401


async def test_isbn_lookup_still_works_for_the_scan_flow(client):
    """The app attaches its bearer token to every request, so closing the
    endpoint needed no client change — this is the regression guard for that."""
    resp = await client.get("/catalog/isbn/9780802162175")
    assert resp.status_code == 200
    assert resp.json()["title"] == "The Covenant of Water"
