"""The landing screen — a live view of the service, in the shape an operator
reads it: what is happening right now, what has moved this week, and what is
waiting on a human.

Two response kinds share one set of queries. The full page is server-rendered
like every other console page; `/live` returns just the moving strip as an HTML
fragment, which admin.js swaps in on a timer so the numbers tick without a
reload (and without a websocket, a poller service, or any JSON API — the same
templates render both).
"""

from fastapi import APIRouter, Query, Request
from fastapi.responses import HTMLResponse

from .. import insights, queries
from ..deps import CurrentAdmin, DbSession
from ..templating import templates

router = APIRouter()


async def _live_context(db: DbSession) -> dict:
    return {
        "pulse": await insights.pulse(db),
        "reading_shape": await insights.reading_now_shape(db),
    }


@router.get("/")
async def dashboard(
    request: Request,
    admin: CurrentAdmin,
    db: DbSession,
    range_: str = Query(default=insights.DEFAULT_RANGE, alias="range"),
) -> HTMLResponse:
    range_ = range_ if range_ in insights.RANGES else insights.DEFAULT_RANGE
    stats = await queries.dashboard_stats(db)
    growth = await insights.growth(db, insights.RANGES[range_])
    denied = request.query_params.get("denied")
    flash = {"kind": "err", "text": "You don't have access to that section."} if denied else None
    return templates.TemplateResponse(
        request,
        "dashboard.html",
        {
            "admin": admin,
            "active": "dashboard",
            "badges": stats["badges"],
            "stats": stats,
            "growth": growth,
            "series": insights.SERIES,
            "ranges": insights.RANGES,
            "range_key": range_,
            "signups": await insights.recent_readers(db),
            "additions": await insights.recent_catalog(db),
            "flash": flash,
            **await _live_context(db),
        },
    )


@router.get("/live")
async def live(request: Request, admin: CurrentAdmin, db: DbSession) -> HTMLResponse:
    """The moving strip on its own. Requires a signed-in admin like every other
    route — a fragment endpoint is still an endpoint."""
    return templates.TemplateResponse(
        request, "_dash_live.html", {"admin": admin, **await _live_context(db)}
    )
