"""A console page is never served from a browser's cache.

The Buy links worklist removes a saved row on screen only, so the HTML the server
sent still has it; Back handed that HTML back from the browser's cache and the
saved card reappeared with an empty field (owner report, 6 Oct 2026; reproduced
in a browser: `transferSize: 0`, navigation type `back_forward`). `no-store` makes
back/forward ask again. No database: the middleware is pure plumbing.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from fastapi import FastAPI
from fastapi.responses import HTMLResponse, JSONResponse, Response
from fastapi.testclient import TestClient

from console.freshness import NO_STORE, NoStoreMiddleware


def _app() -> FastAPI:
    app = FastAPI()
    app.add_middleware(NoStoreMiddleware)

    @app.get("/page", response_class=HTMLResponse)
    async def _page() -> str:
        return "<html><body>a live query</body></html>"

    @app.get("/data")
    async def _data() -> dict:
        return {"ok": True}

    @app.get("/picture")
    async def _picture() -> Response:
        return Response(
            b"png", media_type="image/png", headers={"Cache-Control": "private, max-age=300"}
        )

    @app.get("/own-header", response_class=HTMLResponse)
    async def _own() -> HTMLResponse:
        return HTMLResponse("<p>x</p>", headers={"Cache-Control": "no-cache"})

    @app.get("/fragment")
    async def _fragment() -> HTMLResponse:
        return HTMLResponse("<tr></tr>")

    @app.get("/gone")
    async def _gone() -> JSONResponse:
        return JSONResponse({"detail": "nope"}, status_code=404)

    return app


def test_an_html_page_is_never_stored():
    res = TestClient(_app()).get("/page")
    assert res.headers["cache-control"] == NO_STORE == "no-store"


def test_a_scrolled_page_of_rows_is_never_stored_either():
    assert TestClient(_app()).get("/fragment").headers["cache-control"] == "no-store"


def test_only_html_is_touched():
    client = TestClient(_app())
    assert "cache-control" not in client.get("/data").headers
    assert client.get("/picture").headers["cache-control"] == "private, max-age=300"


def test_a_response_that_sets_its_own_cache_policy_keeps_it():
    assert TestClient(_app()).get("/own-header").headers["cache-control"] == "no-cache"


def test_the_real_console_has_it_installed():
    """Not just the class: `main.py` has to add it, or none of the above ships."""
    source = (Path(__file__).resolve().parents[1] / "console" / "main.py").read_text()
    assert "app.add_middleware(NoStoreMiddleware)" in source
