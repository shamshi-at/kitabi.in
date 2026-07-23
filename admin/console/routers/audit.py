"""The append-only audit log — every admin action and sign-in attempt, newest
first, never editable or deletable."""

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse
from sqlalchemy import select

from .. import queries
from ..deps import CurrentAdmin, DbSession
from ..models_ref import AdminAuditLog
from ..templating import templates

router = APIRouter()


@router.get("/audit")
async def audit_log(request: Request, admin: CurrentAdmin, db: DbSession) -> HTMLResponse:
    rows = (
        (
            await db.execute(
                select(AdminAuditLog).order_by(AdminAuditLog.created_at.desc()).limit(200)
            )
        )
        .scalars()
        .all()
    )
    badges = await queries.nav_badges(db)
    return templates.TemplateResponse(
        request,
        "audit.html",
        {"admin": admin, "active": "audit", "badges": badges, "rows": rows},
    )
