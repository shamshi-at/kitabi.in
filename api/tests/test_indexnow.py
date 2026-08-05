"""IndexNow submission — announcing a new book instead of waiting to be crawled.

Every failure mode here is silent, which is what these guard. A wrong key file,
a URL below the content floor, or an exception escaping into the request all
look exactly like "it works" from the outside: the book saves, the response is
201, and nothing is ever announced (or worse, the create starts failing because
a third party is down).
"""

import re
from pathlib import Path

import httpx
import pytest

from app.core.config import Settings
from app.services import indexnow

REPO = Path(__file__).resolve().parents[2]


class _Recorder:
    """Stands in for httpx.AsyncClient — records the call, never touches the net."""

    def __init__(self, status_code: int = 200, raises: Exception | None = None) -> None:
        self.status_code = status_code
        self.raises = raises
        self.calls: list[tuple[str, dict]] = []

    async def post(self, url: str, json: dict) -> httpx.Response:
        self.calls.append((url, json))
        if self.raises is not None:
            raise self.raises
        return httpx.Response(self.status_code, request=httpx.Request("POST", url))


@pytest.fixture
def enabled(monkeypatch):
    monkeypatch.setattr(indexnow, "is_enabled", lambda *a, **k: True)


# --------------------------------------------------------------------------
# The two files that must agree, or nothing works and nothing says so
# --------------------------------------------------------------------------


def test_the_key_file_exists_and_matches_the_key():
    """Ownership is proved by serving the key at /<key>.txt. If the file is
    missing or its contents drift, every submission comes back 403 and the only
    symptom is that nothing is ever indexed."""
    key_file = REPO / "landing-page" / f"{indexnow.KEY}.txt"
    assert key_file.exists(), f"missing {key_file.name} — IndexNow will 403 every submission"
    assert key_file.read_text().strip() == indexnow.KEY


def test_the_key_file_is_actually_served():
    """Two separate ways this file can exist in the repo and still 404 in
    production: the Pages catch-all serves an ALLOWLIST (a path not on it 404s
    before static assets are consulted), and the deploy workflow copies named
    files into public/. Both have to know about it."""
    catch_all = (REPO / "landing-page" / "functions" / "[[path]].js").read_text()
    assert (
        f"'/{indexnow.KEY}.txt'" in catch_all
    ), "the key file must be in ASSET_FILES in [[path]].js, or the catch-all 404s it"
    deploy = (REPO / ".github" / "workflows" / "deploy.yml").read_text()
    assert re.search(
        r"cp landing-page/\*\.txt public/", deploy
    ), "deploy.yml must copy the key file into public/"


def test_the_key_is_a_valid_indexnow_key():
    """The spec: 8-128 characters, a-z A-Z 0-9 and dashes only."""
    assert re.fullmatch(r"[A-Za-z0-9-]{8,128}", indexnow.KEY)


# --------------------------------------------------------------------------
# What gets submitted
# --------------------------------------------------------------------------


def test_the_url_is_the_canonical_page_never_a_redirect():
    """Submitting /isbn/<isbn> would spend crawl budget on a 301 hop — the same
    rule that keeps redirects out of sitemap.xml."""
    assert indexnow.book_url("chemmeen") == "https://kitabi.in/book/chemmeen"
    assert "/isbn/" not in indexnow.book_url("chemmeen")


async def test_the_payload_is_the_shape_indexnow_expects(enabled):
    recorder = _Recorder()
    ok = await indexnow.submit(["https://kitabi.in/book/chemmeen"], client=recorder)

    assert ok
    url, payload = recorder.calls[0]
    assert url == indexnow.ENDPOINT
    assert payload["host"] == "kitabi.in"
    assert payload["key"] == indexnow.KEY
    assert payload["keyLocation"] == f"https://kitabi.in/{indexnow.KEY}.txt"
    assert payload["urlList"] == ["https://kitabi.in/book/chemmeen"]


@pytest.mark.parametrize("code", [200, 202])
async def test_accepted_responses(enabled, code):
    """202 means the key is still being validated — also a success."""
    assert await indexnow.submit(["https://kitabi.in/book/x"], client=_Recorder(code)) is True


@pytest.mark.parametrize("code", [400, 403, 422, 429, 500])
async def test_rejections_are_reported_but_never_raised(enabled, code):
    assert await indexnow.submit(["https://kitabi.in/book/x"], client=_Recorder(code)) is False


async def test_a_network_failure_is_swallowed(enabled):
    """Adding a book must not depend on Bing being reachable."""
    recorder = _Recorder(raises=httpx.ConnectTimeout("boom"))
    assert await indexnow.submit(["https://kitabi.in/book/x"], client=recorder) is False


async def test_nothing_is_sent_when_disabled(monkeypatch):
    monkeypatch.setattr(indexnow, "is_enabled", lambda *a, **k: False)
    recorder = _Recorder()
    assert await indexnow.submit(["https://kitabi.in/book/x"], client=recorder) is False
    assert recorder.calls == [], "a disabled integration must make no request at all"


async def test_an_empty_url_list_makes_no_request(enabled):
    recorder = _Recorder()
    assert await indexnow.submit([], client=recorder) is False
    assert recorder.calls == []


# --------------------------------------------------------------------------
# The switch
# --------------------------------------------------------------------------


def test_off_by_default_so_a_laptop_never_announces_pages():
    assert Settings(indexnow_enabled=False).indexnow_enabled is False
    assert indexnow.is_enabled(Settings(indexnow_enabled=False)) is False
    assert indexnow.is_enabled(Settings(indexnow_enabled=True)) is True


def test_production_opts_in_from_the_repo_not_a_dashboard():
    """Same pattern as ALLOW_PROD_MIGRATION: what production does should be
    readable from a checkout. If this line goes, submissions stop silently."""
    dockerfile = (REPO / "api" / "Dockerfile").read_text()
    assert re.search(r"^ENV INDEXNOW_ENABLED=1$", dockerfile, re.MULTILINE)


# --------------------------------------------------------------------------
# Through the router — the part that decides WHETHER to announce
# --------------------------------------------------------------------------


async def test_a_book_that_clears_the_content_floor_is_announced(client, monkeypatch):
    sent: list[list[str]] = []

    async def fake_submit(urls, **kwargs):
        sent.append(urls)
        return True

    monkeypatch.setattr(indexnow, "is_enabled", lambda *a, **k: True)
    monkeypatch.setattr(indexnow, "announce", fake_submit)

    resp = await client.post(
        "/catalog/works",
        json={"title": "Chemmeen", "cover_url": "https://x/c.jpg"},  # a cover clears the floor
    )
    assert resp.status_code == 201
    assert sent, "an indexable new book should be announced"
    assert sent[0][0].startswith("https://kitabi.in/book/")


async def test_a_thin_book_is_not_announced(client, monkeypatch):
    """It renders `noindex, follow`. Inviting a crawler to a page that tells it
    not to index is pointless, and spends goodwill this protocol runs on. It
    gets picked up later, by the sitemap, once someone improves it."""
    sent: list[list[str]] = []

    async def fake_submit(urls, **kwargs):
        sent.append(urls)
        return True

    monkeypatch.setattr(indexnow, "is_enabled", lambda *a, **k: True)
    monkeypatch.setattr(indexnow, "announce", fake_submit)

    resp = await client.post("/catalog/works", json={"title": "A Bare Row"})
    assert resp.status_code == 201
    assert sent == [], "a work below the content floor must not be announced"


async def test_creating_a_book_still_succeeds_when_indexnow_explodes(client, monkeypatch):
    """The whole point of the background task + swallowed errors."""

    async def exploding_submit(urls, **kwargs):
        raise RuntimeError("IndexNow is on fire")

    monkeypatch.setattr(indexnow, "is_enabled", lambda *a, **k: True)
    monkeypatch.setattr(indexnow, "submit", exploding_submit)  # announce must contain it

    resp = await client.post(
        "/catalog/works", json={"title": "Resilient", "cover_url": "https://x/c.jpg"}
    )
    assert resp.status_code == 201, "a third party's outage must never fail a book create"


async def test_no_submission_when_the_integration_is_off(client, monkeypatch):
    """The default for every environment except the container."""
    sent: list[list[str]] = []

    async def fake_submit(urls, **kwargs):
        sent.append(urls)
        return True

    monkeypatch.setattr(indexnow, "is_enabled", lambda *a, **k: False)
    monkeypatch.setattr(indexnow, "announce", fake_submit)

    resp = await client.post(
        "/catalog/works", json={"title": "Quiet", "cover_url": "https://x/c.jpg"}
    )
    assert resp.status_code == 201
    assert sent == []


async def test_announce_never_raises_whatever_submit_does(monkeypatch):
    """The boundary guarantee, tested directly rather than only through a route."""

    async def exploding(urls, **kwargs):
        raise RuntimeError("anything at all")

    monkeypatch.setattr(indexnow, "submit", exploding)
    await indexnow.announce(["https://kitabi.in/book/x"])  # must simply return
