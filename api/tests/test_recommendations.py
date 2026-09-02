import json
import uuid
from datetime import UTC, datetime, timedelta

import httpx
from sqlalchemy import select

from app.core.config import get_settings
from app.models import Edition, LibraryEntry, LlmUsage, Rating, RecCache, Work
from app.services import recommendation_service
from app.services.recommendation_service import _SYSTEM, _extract_json


def _settings(**overrides):
    base = {
        "anthropic_api_key": "test-key",
        "llm_daily_quota_recommendations": 50,
        "llm_daily_global_cap": 100,
        "recs_cache_ttl_days": 7,
    }
    return get_settings().model_copy(update={**base, **overrides})


class _CountingLlm:
    """A MockTransport that answers with fixed picks and counts its calls —
    the whole cache story is told by how many times this fires."""

    def __init__(self, work_ids):
        self.calls = 0
        self._ids = [str(w) for w in work_ids]

    def transport(self):
        async def _reply(_request: httpx.Request) -> httpx.Response:
            self.calls += 1
            picks = [{"work_id": i, "why": f"You loved things like {i[:4]}."} for i in self._ids]
            return httpx.Response(
                200, json={"content": [{"type": "text", "text": json.dumps(picks)}]}
            )

        return httpx.MockTransport(_reply)


async def _seed_reader(db, *, candidates=1):
    """A reader with one 5-star rating and `candidates` unowned catalogue books."""
    user_id = uuid.uuid4()
    rated = Work(title="Chemmeen")
    others = [Work(title=f"Candidate {i}") for i in range(candidates)]
    db.add_all([rated, *others])
    await db.flush()
    db.add(Rating(id=uuid.uuid4(), user_id=user_id, work_id=rated.id, value=5))
    await db.commit()
    return user_id, rated, others


async def test_recommendations_disabled_without_key(client, monkeypatch):
    """With no Anthropic key configured, the feature is dormant: enabled=False,
    no picks, no external call. Forced explicitly (not relying on the ambient
    .env) so a developer who has set a real key locally still sees this pass —
    the router and service both read get_settings() directly."""
    disabled = get_settings().model_copy(update={"anthropic_api_key": ""})
    monkeypatch.setattr("app.api.recommendations.get_settings", lambda: disabled)
    monkeypatch.setattr("app.services.recommendation_service.get_settings", lambda: disabled)

    resp = await client.get("/recommendations")
    assert resp.status_code == 200
    body = resp.json()
    assert body["enabled"] is False
    assert body["picks"] == []


def test_extract_json_pulls_the_array_out_of_surrounding_text():
    text = 'Sure! [{"work_id": "abc", "why": "You loved X."}] hope that helps'
    assert _extract_json(text) == [{"work_id": "abc", "why": "You loved X."}]


def test_extract_json_returns_empty_on_garbage():
    assert _extract_json("no json here") == []
    assert _extract_json("[not valid json}") == []


def test_system_prompt_formats_without_raising():
    """`_generate_picks` does `_SYSTEM.format(limit=...)`; the JSON example in
    the prompt must have its braces escaped or that raises KeyError at call
    time (only reachable with a real key — the disabled test never hits it).
    Renders it and checks the example survived intact."""
    rendered = _SYSTEM.format(limit=5)
    assert '{"work_id": "<id>", "why": "<sentence>"}' in rendered
    assert "Pick at most 5" in rendered


# --------------------------------------------------------------------------
# The result cache — a repeat visit must not be a repeat bill (2 Sep 2026)
# --------------------------------------------------------------------------


async def test_an_unchanged_shelf_is_served_from_cache(db_sessionmaker, monkeypatch):
    """Two visits, one Anthropic call, one quota unit. The picks are a pure
    function of the shelf; the second visit could only recompute the first."""
    settings = _settings()
    monkeypatch.setattr("app.services.recommendation_service.get_settings", lambda: settings)

    async with db_sessionmaker() as db:
        user_id, _, others = await _seed_reader(db)
        llm = _CountingLlm([others[0].id])

        async with httpx.AsyncClient(transport=llm.transport()) as fake:
            first = await recommendation_service.recommend(db, user_id, client=fake)
            second = await recommendation_service.recommend(db, user_id, client=fake)

        spent = await db.scalar(select(LlmUsage.count).where(LlmUsage.user_id == user_id))

    assert llm.calls == 1, "the second visit never reached Anthropic"
    assert spent == 1, "…and never touched the quota"
    assert [(w.id, why) for w, why in second] == [(w.id, why) for w, why in first]


async def test_a_new_rating_regenerates(db_sessionmaker, monkeypatch):
    """The fingerprint is the shelf. Rate one more book and the cached answer
    is no longer about this reader — it must be recomputed."""
    settings = _settings()
    monkeypatch.setattr("app.services.recommendation_service.get_settings", lambda: settings)

    async with db_sessionmaker() as db:
        user_id, _, others = await _seed_reader(db, candidates=2)
        llm = _CountingLlm([others[0].id])

        async with httpx.AsyncClient(transport=llm.transport()) as fake:
            await recommendation_service.recommend(db, user_id, client=fake)
            db.add(Rating(id=uuid.uuid4(), user_id=user_id, work_id=others[1].id, value=4))
            await db.commit()
            await recommendation_service.recommend(db, user_id, client=fake)

    assert llm.calls == 2


async def test_an_aged_cache_regenerates(db_sessionmaker, monkeypatch):
    """The fingerprint can stay stable for months on a dormant shelf; the TTL
    is how catalogue growth still reaches that reader."""
    settings = _settings()
    monkeypatch.setattr("app.services.recommendation_service.get_settings", lambda: settings)

    async with db_sessionmaker() as db:
        user_id, _, others = await _seed_reader(db)
        llm = _CountingLlm([others[0].id])

        async with httpx.AsyncClient(transport=llm.transport()) as fake:
            await recommendation_service.recommend(db, user_id, client=fake)
            row = await db.get(RecCache, user_id)
            row.generated_at = datetime.now(UTC) - timedelta(days=8)
            await db.commit()
            await recommendation_service.recommend(db, user_id, client=fake)

    assert llm.calls == 2


async def test_over_quota_still_serves_the_standing_picks(db_sessionmaker, monkeypatch):
    """The cache check sits BEFORE the meter on purpose: a reader who has
    spent their day still sees their picks — only regeneration costs."""
    settings = _settings(llm_daily_quota_recommendations=1)
    monkeypatch.setattr("app.services.recommendation_service.get_settings", lambda: settings)

    async with db_sessionmaker() as db:
        user_id, _, others = await _seed_reader(db)
        llm = _CountingLlm([others[0].id])

        async with httpx.AsyncClient(transport=llm.transport()) as fake:
            await recommendation_service.recommend(db, user_id, client=fake)  # spends the 1
            served = await recommendation_service.recommend(db, user_id, client=fake)

    assert llm.calls == 1
    assert len(served) == 1, "no 429 — the cached answer stands"


async def test_a_cached_pick_that_vanished_is_not_shown(db_sessionmaker, monkeypatch):
    """The cache stores work ids, never work data — a book soft-deleted since
    generation is dropped on serve, and the survivors still come back."""
    settings = _settings()
    monkeypatch.setattr("app.services.recommendation_service.get_settings", lambda: settings)

    async with db_sessionmaker() as db:
        user_id, _, others = await _seed_reader(db, candidates=2)
        llm = _CountingLlm([o.id for o in others])

        async with httpx.AsyncClient(transport=llm.transport()) as fake:
            first = await recommendation_service.recommend(db, user_id, client=fake)
            assert len(first) == 2
            (await db.get(Work, others[0].id)).deleted_at = datetime.now(UTC)
            await db.commit()
            second = await recommendation_service.recommend(db, user_id, client=fake)

    assert llm.calls == 1, "still the cached answer — just without the ghost"
    assert [w.id for w, _ in second] == [others[1].id]


async def test_an_empty_answer_is_not_pinned_for_a_week(db_sessionmaker, monkeypatch):
    """A refusal or flaky reply produces no picks; caching that would freeze
    'nothing for you' until the TTL. The retry costs quota — that is the
    quota's job."""
    settings = _settings()
    monkeypatch.setattr("app.services.recommendation_service.get_settings", lambda: settings)

    async def _empty(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"content": [{"type": "text", "text": "[]"}]})

    async with db_sessionmaker() as db:
        user_id, _, _others = await _seed_reader(db)
        async with httpx.AsyncClient(transport=httpx.MockTransport(_empty)) as fake:
            assert await recommendation_service.recommend(db, user_id, client=fake) == []
            cached = await db.get(RecCache, user_id)
        spent = await db.scalar(select(LlmUsage.count).where(LlmUsage.user_id == user_id))

    assert cached is None
    assert spent == 1


async def test_owning_a_new_book_regenerates(db_sessionmaker, monkeypatch):
    """The owned set is part of the fingerprint too — a pick the reader has
    since shelved must never be recommended back to them from cache."""
    settings = _settings()
    monkeypatch.setattr("app.services.recommendation_service.get_settings", lambda: settings)

    async with db_sessionmaker() as db:
        user_id, _, others = await _seed_reader(db, candidates=2)
        llm = _CountingLlm([others[0].id])

        async with httpx.AsyncClient(transport=llm.transport()) as fake:
            await recommendation_service.recommend(db, user_id, client=fake)
            edition = Edition(work_id=others[0].id)
            db.add(edition)
            await db.flush()
            db.add(LibraryEntry(id=uuid.uuid4(), user_id=user_id, edition_id=edition.id))
            await db.commit()
            await recommendation_service.recommend(db, user_id, client=fake)

    assert llm.calls == 2
