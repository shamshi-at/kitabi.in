"""The append-only audit log — every admin action and sign-in attempt, newest
first, never editable or deletable.

The log answers "who did this, and when" only if you can *find* the row. At 200
rows with no filter that stopped being true within weeks of launch, so the page
now filters by admin, by action and by period, and pages through the rest. Every
choice lives in the query string, so a filtered view is a link.
"""

import uuid
from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Query, Request
from fastapi.responses import HTMLResponse
from sqlalchemy import func, or_, select

from .. import queries
from ..deps import CurrentAdmin, DbSession
from ..models_ref import AdminAuditLog, AdminUser
from ..templating import templates

router = APIRouter()

PAGE_SIZE = 100
PERIODS = {"1": "Last 24 hours", "7": "Last 7 days", "30": "Last 30 days", "all": "All time"}
DEFAULT_PERIOD = "30"


@router.get("/audit")
async def audit_log(
    request: Request,
    admin: CurrentAdmin,
    db: DbSession,
    q: str = Query(default=""),
    who: str = Query(default=""),
    period: str = Query(default=DEFAULT_PERIOD),
    page: int = Query(default=1, ge=1),
) -> HTMLResponse:
    q = q.strip()
    period = period if period in PERIODS else DEFAULT_PERIOD

    conds = []
    if period != "all":
        conds.append(AdminAuditLog.created_at >= datetime.now(UTC) - timedelta(days=int(period)))
    if who:
        try:
            conds.append(AdminAuditLog.admin_id == uuid.UUID(who))
        except ValueError:
            who = ""
    if q:
        like = f"%{q}%"
        conds.append(
            or_(
                AdminAuditLog.action.ilike(like),
                AdminAuditLog.summary.ilike(like),
                AdminAuditLog.target_type.ilike(like),
            )
        )

    matching = int(
        await db.scalar(select(func.count()).select_from(AdminAuditLog).where(*conds)) or 0
    )
    pages = max(1, -(-matching // PAGE_SIZE))
    page = min(page, pages)
    rows = (
        (
            await db.execute(
                select(AdminAuditLog)
                .where(*conds)
                .order_by(AdminAuditLog.created_at.desc())
                .offset((page - 1) * PAGE_SIZE)
                .limit(PAGE_SIZE)
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
    # Everyone who has ever acted, for the "who" picker — including admins whose
    # accounts were later revoked, since their rows are still here.
    actors = (
        await db.execute(select(AdminUser.id, AdminUser.email).order_by(AdminUser.email.asc()))
    ).all()
    badges = await queries.nav_badges(db)
    return templates.TemplateResponse(
        request,
        "audit.html",
        {
            "admin": admin,
            "active": "audit",
            "badges": badges,
            "rows": rows,
            "admins": admins,
            "actors": actors,
            "q": q,
            "who": who,
            "periods": PERIODS,
            "period": period,
            "page": page,
            "pages": pages,
            "matching": matching,
        },
    )
