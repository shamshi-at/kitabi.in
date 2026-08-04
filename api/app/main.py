"""FastAPI app factory: mounts routers, the version gate, CORS, structured
errors, and the APScheduler lifespan (keep-warm / notify jobs)."""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api import (
    auth,
    catalog,
    connections,
    devices,
    health,
    me,
    promotions,
    recommendations,
    sitemap,
    sync,
    users,
)
from app.api import import_ as import_api
from app.core.config import get_settings
from app.core.version_gate import VersionGateMiddleware
from app.jobs import scheduler


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    if get_settings().scheduler_enabled:
        scheduler.start()
    yield
    scheduler.shutdown()


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(
        title="Kitabi API",
        version=settings.app_version,
        lifespan=lifespan,
        docs_url="/docs" if settings.env == "dev" else None,
        redoc_url=None,
    )

    app.add_middleware(VersionGateMiddleware)

    if settings.cors_origins:
        # The mobile app needs no CORS at all (it isn't a browser) and the admin
        # console is its own app making same-origin calls. The ONLY browser
        # callers are kitabi.in's public share pages, and they are strictly
        # read-only and unauthenticated — so this is scoped to exactly what
        # they do and nothing more (docs/web-platform-plan.md §11):
        #
        #   * GET only — the public web has no write path, by design. `["*"]`
        #     advertised POST/PATCH/DELETE to every browser on the internet.
        #   * No credentials — nothing on the public web signs in, and
        #     `allow_credentials=True` is what lets a cross-origin page read a
        #     response with the user's cookies attached.
        #   * `Accept` only — those pages send `Accept: application/json` and
        #     nothing else. Dropping `Authorization` enforces "the public web
        #     never carries a token" at the transport layer instead of trusting
        #     that no one adds one later.
        #
        # CORS is a *browser* policy, not access control — curl ignores it
        # entirely. This narrows what a hostile web page can make a reader's
        # browser do; the controls against scripted abuse are rate and cost
        # (llm_quota, Cloudflare rules), never this.
        #
        # Once the public pages are edge-rendered (W1) the browser stops calling
        # the API at all and this block can go away completely.
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_origins,
            allow_credentials=False,
            allow_methods=["GET"],
            allow_headers=["Accept"],
        )

    @app.exception_handler(HTTPException)
    async def structured_http_error(_: Request, exc: HTTPException) -> JSONResponse:
        # Errors always carry structured detail {"code", "message"} (CLAUDE.md).
        detail = exc.detail
        if not isinstance(detail, dict):
            detail = {"code": "error", "message": str(detail)}
        return JSONResponse(status_code=exc.status_code, content=detail, headers=exc.headers)

    app.include_router(health.router)
    app.include_router(auth.router)
    app.include_router(me.router)
    app.include_router(users.router)
    app.include_router(connections.router)
    app.include_router(devices.router)
    app.include_router(catalog.router)
    app.include_router(sitemap.router)
    app.include_router(recommendations.router)
    app.include_router(promotions.router)
    app.include_router(import_api.router)
    app.include_router(sync.router)
    return app


app = create_app()
