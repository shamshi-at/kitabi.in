"""Moving hotlinked covers into our own bucket.

The decision that carries the weight is **gone vs. transient**. A definitive 404
means stop asking; a timeout or a 5xx means try later. Collapse the two and the
job either hammers a free third-party service forever or throws away good covers
over one bad minute — and neither failure announces itself.
"""

import uuid

import httpx
import pytest

from app.core.config import get_settings
from app.models import Edition, Work
from app.services import cover_storage

BASE = "https://proj.supabase.co"
PNG = b"\x89PNG\r\n\x1a\n" + b"x" * 64


def _settings(**over):
    return get_settings().model_copy(
        update={"supabase_url": BASE, "supabase_service_role_key": "svc-key", **over}
    )


def _client(handler):
    return httpx.AsyncClient(transport=httpx.MockTransport(handler), timeout=5)


# --------------------------------------------------------------------------
# The dormancy gate
# --------------------------------------------------------------------------


def test_dormant_without_a_service_role_key():
    """Same gate as recs and push (rule 8): no key, no external call, no bill."""
    assert cover_storage.configured(_settings()) is True
    assert cover_storage.configured(_settings(supabase_service_role_key="")) is False
    assert cover_storage.configured(_settings(supabase_url="")) is False


def test_is_ours_recognises_an_already_migrated_cover():
    """Checked before every fetch — it's what makes the job idempotent and
    cheap to re-run once the backlog is clear."""
    s = _settings()
    assert cover_storage.is_ours(s, f"{BASE}/storage/v1/object/public/covers/catalog/x.jpg")
    assert not cover_storage.is_ours(s, "https://covers.openlibrary.org/b/id/1-L.jpg")
    assert not cover_storage.is_ours(s, None)


# --------------------------------------------------------------------------
# gone vs. transient
# --------------------------------------------------------------------------


@pytest.mark.parametrize("status", [404, 410])
async def test_a_definitive_missing_cover_is_gone(status):
    async with _client(lambda r: httpx.Response(status)) as c:
        result = await cover_storage.fetch_cover(c, "https://covers.openlibrary.org/x.jpg")
    assert result.gone is True
    assert result.body is None


@pytest.mark.parametrize("status", [500, 502, 503, 429])
async def test_a_server_error_is_transient_not_gone(status):
    """429 especially: being rate-limited must never be read as "this cover
    does not exist" — that would delete covers for being popular."""
    async with _client(lambda r: httpx.Response(status)) as c:
        result = await cover_storage.fetch_cover(c, "https://covers.openlibrary.org/x.jpg")
    assert result.gone is False
    assert result.body is None


async def test_a_network_failure_is_transient():
    def boom(request):
        raise httpx.ConnectError("no route")

    async with _client(boom) as c:
        result = await cover_storage.fetch_cover(c, "https://covers.openlibrary.org/x.jpg")
    assert result.gone is False


async def test_a_non_image_response_counts_as_gone():
    """OpenLibrary answers a missing cover with a 1x1 GIF or an HTML page rather
    than a 404, so "not an image" is also "there is no cover here" — otherwise
    those rows are retried on every run forever."""
    async with _client(
        lambda r: httpx.Response(
            200, content=b"<html>nope</html>", headers={"content-type": "text/html"}
        )
    ) as c:
        result = await cover_storage.fetch_cover(c, "https://covers.openlibrary.org/x.jpg")
    assert result.gone is True


async def test_an_oversized_image_is_skipped_but_not_deleted():
    big = b"\x89PNG\r\n\x1a\n" + b"x" * (cover_storage.MAX_BYTES + 1)
    async with _client(
        lambda r: httpx.Response(200, content=big, headers={"content-type": "image/png"})
    ) as c:
        result = await cover_storage.fetch_cover(c, "https://covers.openlibrary.org/x.jpg")
    assert result.body is None and result.gone is False


async def test_a_good_image_comes_back_whole():
    async with _client(
        lambda r: httpx.Response(200, content=PNG, headers={"content-type": "image/png"})
    ) as c:
        result = await cover_storage.fetch_cover(c, "https://covers.openlibrary.org/x.jpg")
    assert result.body == PNG
    assert result.content_type == "image/png"
    assert result.gone is False


# --------------------------------------------------------------------------
# Storing
# --------------------------------------------------------------------------


async def test_the_stored_path_is_derived_from_the_edition_id():
    """Deterministic, not a random object name: re-running must land on the same
    URL rather than orphaning objects under a URL something still references."""
    seen = {}

    def handler(request):
        seen["url"] = str(request.url)
        seen["auth"] = request.headers.get("authorization")
        seen["upsert"] = request.headers.get("x-upsert")
        seen["cache"] = request.headers.get("cache-control")
        return httpx.Response(200, json={})

    key = uuid.UUID("11111111-2222-3333-4444-555555555555")
    async with _client(handler) as c:
        url = await cover_storage.store_cover(c, _settings(), key, PNG, "image/png")

    assert url == f"{BASE}/storage/v1/object/public/covers/catalog/{key}.png"
    assert seen["url"] == f"{BASE}/storage/v1/object/covers/catalog/{key}.png"
    assert seen["auth"] == "Bearer svc-key"
    assert seen["upsert"] == "true"  # idempotent re-run
    assert "immutable" in seen["cache"]


async def test_a_rejected_upload_returns_none_rather_than_a_bad_url():
    """The caller must not repoint the catalogue at something that isn't there."""
    async with _client(lambda r: httpx.Response(403, json={"message": "denied"})) as c:
        assert (
            await cover_storage.store_cover(c, _settings(), uuid.uuid4(), PNG, "image/png") is None
        )


# --------------------------------------------------------------------------
# Through the job
# --------------------------------------------------------------------------


async def _edition(db, cover_url):
    work = Work(title="A Book")
    db.add(work)
    await db.flush()
    edition = Edition(work_id=work.id, cover_url=cover_url)
    db.add(edition)
    await db.commit()
    return edition


async def test_the_job_moves_a_cover_and_repoints_the_edition(db_sessionmaker, monkeypatch):
    from app.jobs import backfill_covers as job

    settings = _settings()
    monkeypatch.setattr("app.jobs.backfill_covers.get_settings", lambda: settings)
    monkeypatch.setattr(job.asyncio, "sleep", lambda _: _noop())

    async with db_sessionmaker() as db:
        edition = await _edition(db, "https://covers.openlibrary.org/b/id/1-L.jpg")

        def handler(request):
            if "openlibrary" in str(request.url):
                return httpx.Response(200, content=PNG, headers={"content-type": "image/png"})
            return httpx.Response(200, json={})

        monkeypatch.setattr("app.jobs.backfill_covers.SessionLocal", db_sessionmaker)
        async with _client(handler) as c:
            await job.backfill_covers(client=c)
        await db.refresh(edition)

    assert edition.cover_url == (f"{BASE}/storage/v1/object/public/covers/catalog/{edition.id}.png")


async def test_the_job_clears_a_cover_that_is_definitively_gone(db_sessionmaker, monkeypatch):
    """Null renders a typeset cover in both the app and the site, which beats a
    URL that will never load — and it stops the row being retried forever."""
    from app.jobs import backfill_covers as job

    settings = _settings()
    monkeypatch.setattr("app.jobs.backfill_covers.get_settings", lambda: settings)
    monkeypatch.setattr(job.asyncio, "sleep", lambda _: _noop())

    async with db_sessionmaker() as db:
        edition = await _edition(db, "https://covers.openlibrary.org/b/id/dead-L.jpg")
        monkeypatch.setattr("app.jobs.backfill_covers.SessionLocal", db_sessionmaker)
        async with _client(lambda r: httpx.Response(404)) as c:
            await job.backfill_covers(client=c)
        await db.refresh(edition)

    assert edition.cover_url is None


async def test_a_transient_failure_leaves_the_row_untouched(db_sessionmaker, monkeypatch):
    """The whole point of the gone/transient split: a rate limit must not cost
    us the cover."""
    from app.jobs import backfill_covers as job

    settings = _settings()
    monkeypatch.setattr("app.jobs.backfill_covers.get_settings", lambda: settings)
    monkeypatch.setattr(job.asyncio, "sleep", lambda _: _noop())

    original = "https://covers.openlibrary.org/b/id/busy-L.jpg"
    async with db_sessionmaker() as db:
        edition = await _edition(db, original)
        monkeypatch.setattr("app.jobs.backfill_covers.SessionLocal", db_sessionmaker)
        async with _client(lambda r: httpx.Response(429)) as c:
            await job.backfill_covers(client=c)
        await db.refresh(edition)

    assert edition.cover_url == original


async def test_the_job_does_nothing_without_a_key(db_sessionmaker, monkeypatch):
    from app.jobs import backfill_covers as job

    monkeypatch.setattr(
        "app.jobs.backfill_covers.get_settings",
        lambda: _settings(supabase_service_role_key=""),
    )

    def explode(request):
        raise AssertionError("dormant job must make no external call")

    monkeypatch.setattr("app.jobs.backfill_covers.SessionLocal", db_sessionmaker)
    async with _client(explode) as c:
        await job.backfill_covers(client=c)


async def _noop():
    return None
