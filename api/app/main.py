import asyncio
import contextlib
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text

from app.api import auth, catalog, health, me, recommendations, sync
from app.api import import_ as import_api
from app.core.config import get_settings
from app.core.db import engine
from app.core.version_gate import VersionGateMiddleware
from app.jobs import scheduler


async def _keep_pool_warm() -> None:
    """Ping the DB every 30s to keep a pooled connection alive. When the API and
    Supabase aren't co-located, an idle-dropped connection costs a ~2s
    cross-region reconnect on the NEXT request — so we pay that reconnect here,
    in the background, and real requests find a warm connection. (The real fix
    is co-locating the API with the DB region — see STATUS.md.)"""
    while True:
        with contextlib.suppress(Exception):
            async with engine.connect() as conn:
                await conn.execute(text("SELECT 1"))
        await asyncio.sleep(30)


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    if get_settings().scheduler_enabled:
        scheduler.start()
    warm = asyncio.create_task(_keep_pool_warm())
    yield
    warm.cancel()
    with contextlib.suppress(asyncio.CancelledError):
        await warm
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
        # The mobile app doesn't need CORS; only a future web origin goes here.
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_origins,
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["Authorization", "Content-Type"],
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
    app.include_router(catalog.router)
    app.include_router(recommendations.router)
    app.include_router(import_api.router)
    app.include_router(sync.router)
    return app


app = create_app()
