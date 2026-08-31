"""The append-only audit log — every admin action and sign-in attempt, newest
first, never editable or deletable."""

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse
from sqlalchemy import select

from .. import queries
from ..deps import CurrentAdmin, DbSession
from ..models_ref import AdminAuditLog, AdminUser
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
    # Resolve every admin the page shows in one query, id -> email, so the log
    # reads "shamshi" not "f9947d9f". A revoked/deleted admin is absent from the
    # map and falls back to the id fragment in the template — the row must never
    # vanish just because the actor's account is gone (that is exactly when the
    # trail matters most).
    ids = {r.admin_id for r in rows if r.admin_id is not None}
    admins = {}
    if ids:
        admins = dict(
            (
                await db.execute(select(AdminUser.id, AdminUser.email).where(AdminUser.id.in_(ids)))
            ).all()
        )
    badges = await queries.nav_badges(db)
    return templates.TemplateResponse(
        request,
        "audit.html",
        {"admin": admin, "active": "audit", "badges": badges, "rows": rows, "admins": admins},
    )
