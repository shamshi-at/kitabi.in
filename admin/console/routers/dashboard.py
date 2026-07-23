"""The landing screen: KPI row, catalog-health bars, and the queue badges."""

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse

from .. import queries
from ..deps import CurrentAdmin, DbSession
from ..templating import templates

router = APIRouter()


@router.get("/")
async def dashboard(
    request: Request, admin: CurrentAdmin, db: DbSession
) -> HTMLResponse:
    stats = await queries.dashboard_stats(db)
    denied = request.query_params.get("denied")
    flash = (
        {"kind": "err", "text": "You don't have access to that section."}
        if denied
        else None
    )
    return templates.TemplateResponse(
        request,
        "dashboard.html",
        {
            "admin": admin,
            "active": "dashboard",
            "badges": stats["badges"],
            "stats": stats,
            "flash": flash,
        },
    )
