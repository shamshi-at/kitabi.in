"""Kitabi Admin — the back office at admin.kitabi.in.

FastAPI + Jinja + a little htmx, reusing the API's database and models (see
bootstrap.py). Server-rendered with a DB-backed session cookie, so no admin
token ever lives in JavaScript. Reader identity (Supabase) and admin identity
(admin_users) never meet.
"""

from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles

from .deps import RedirectException
from .routers import (
    account,
    admins,
    audit,
    auth,
    catalog,
    claims,
    dashboard,
    edits,
    readers,
    reports,
    search,
)
from .templating import templates

app = FastAPI(title="Kitabi Admin", docs_url=None, redoc_url=None, openapi_url=None)

_STATIC = Path(__file__).parent / "static"
app.mount("/static", StaticFiles(directory=_STATIC), name="static")


@app.exception_handler(RedirectException)
async def _redirect(_: Request, exc: RedirectException) -> RedirectResponse:
    # Dependencies signal "go elsewhere" by raising; turn it into a real 303.
    return RedirectResponse(exc.location, status_code=303)


app.include_router(auth.router)
app.include_router(dashboard.router)
app.include_router(claims.router)
app.include_router(edits.router)
app.include_router(reports.router)
app.include_router(catalog.router)
app.include_router(readers.router)
app.include_router(admins.router)
app.include_router(audit.router)
app.include_router(account.router)
app.include_router(search.router)


@app.get("/healthz")
async def healthz() -> dict:
    return {"status": "ok"}


@app.exception_handler(404)
async def _not_found(request: Request, _exc) -> RedirectResponse:
    return templates.TemplateResponse(request, "404.html", status_code=404)
