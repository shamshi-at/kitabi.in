"""The back office must not be indexable.

These run without a database — the middleware and the robots route are pure
request/response plumbing, and mounting them on a bare app keeps the test
honest about what it covers.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from fastapi import FastAPI
from fastapi.responses import JSONResponse
from fastapi.testclient import TestClient

from console.noindex import ROBOTS_HEADER, ROBOTS_TXT, NoIndexMiddleware, robots


def _app() -> FastAPI:
    app = FastAPI()
    app.add_middleware(NoIndexMiddleware)
    app.add_route("/robots.txt", robots, methods=["GET"])

    @app.get("/dashboard")
    async def _dash() -> dict:
        return {"ok": True}

    @app.get("/boom")
    async def _boom() -> JSONResponse:
        return JSONResponse({"detail": "nope"}, status_code=403)

    return app


def test_robots_txt_disallows_the_whole_host():
    res = TestClient(_app()).get("/robots.txt")
    assert res.status_code == 200
    assert res.text == ROBOTS_TXT
    assert "Disallow: /" in res.text
    # No Allow anywhere — unlike the API, nothing on this host is public.
    assert "Allow:" not in res.text


def test_the_header_is_on_every_response_including_errors_and_404s():
    client = TestClient(_app())
    cases = [("/dashboard", 200), ("/robots.txt", 200), ("/boom", 403), ("/nope", 404)]
    for path, expected in cases:
        res = client.get(path)
        assert res.status_code == expected, path
        assert res.headers.get("X-Robots-Tag") == ROBOTS_HEADER, path


def test_the_header_says_all_three_things():
    # noindex: don't list it. nofollow: don't walk into the app's routes.
    # noarchive: no cached snapshot of an admin screen.
    assert ROBOTS_HEADER == "noindex, nofollow, noarchive"


def test_robots_txt_is_wired_into_the_real_app():
    """The middleware and route above are only useful if main.py mounts them."""
    main = (Path(__file__).resolve().parents[1] / "console" / "main.py").read_text()
    assert "NoIndexMiddleware" in main
    assert 'app.add_route("/robots.txt"' in main
