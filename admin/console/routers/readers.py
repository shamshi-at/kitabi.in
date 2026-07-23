"""Readers — support, not surveillance. Find an account, see the identity it has
already made public plus aggregate contribution counts, and act when it
misbehaves. It never shows a reader's private shelf, notes or unpublished
reviews. Suspend (any admin) sets profiles.suspended_at, which the API's auth
dependency enforces — a suspended reader is locked out until unsuspended, with
their data intact. Hard account deletion is intentionally NOT a console button:
a real erasure across Layer-2 tables + Supabase Auth is a separate, deliberate
operation, not a one-click action.
"""

import uuid
from datetime import UTC, datetime

from app.services import scoring_service  # noqa: E402
from fastapi import APIRouter, Query, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy import func, or_, select

from .. import queries, security
from ..deps import CurrentAdmin, DbSession, client_ip
from ..flash import pop_flash, set_flash
from ..models_ref import Profile
from ..templating import templates

router = APIRouter(prefix="/readers")


@router.get("")
async def readers(
    request: Request, admin: CurrentAdmin, db: DbSession, q: str = Query(default="")
) -> HTMLResponse:
    q = q.strip()
    stmt = select(Profile).where(Profile.deleted_at.is_(None))
    if q:
        like = f"%{q}%"
        stmt = stmt.where(
            or_(
                Profile.full_name.ilike(like),
                Profile.username.ilike(like),
                Profile.email.ilike(like),
            )
        )
    stmt = stmt.order_by(Profile.created_at.desc()).limit(50)
    rows = (await db.execute(stmt)).scalars().all()
    total = int(await db.scalar(select(func.count()).select_from(Profile)) or 0)
    badges = await queries.nav_badges(db)
    flash = pop_flash(request)
    resp = templates.TemplateResponse(
        request,
        "readers.html",
        {
            "admin": admin,
            "active": "readers",
            "badges": badges,
            "q": q,
            "rows": rows,
            "total": total,
            "flash": flash,
        },
    )
    if flash:
        resp.delete_cookie("admin_flash", path="/")
    return resp


@router.get("/{reader_id}")
async def reader_detail(
    request: Request, admin: CurrentAdmin, db: DbSession, reader_id: uuid.UUID
) -> HTMLResponse:
    profile = await db.get(Profile, reader_id)
    if profile is None:
        resp = RedirectResponse("/readers", status_code=303)
        set_flash(resp, "err", "No such reader.")
        return resp
    score = await scoring_service.compute_score(db, reader_id)
    badges = await queries.nav_badges(db)
    flash = pop_flash(request)
    resp = templates.TemplateResponse(
        request,
        "reader_detail.html",
        {
            "admin": admin,
            "active": "readers",
            "badges": badges,
            "p": profile,
            "score": score,
            "flash": flash,
        },
    )
    if flash:
        resp.delete_cookie("admin_flash", path="/")
    return resp


@router.post("/{reader_id}/{action}")
async def moderate(
    request: Request, admin: CurrentAdmin, db: DbSession, reader_id: uuid.UUID, action: str
) -> RedirectResponse:
    resp = RedirectResponse(f"/readers/{reader_id}", status_code=303)
    profile = await db.get(Profile, reader_id)
    if profile is None:
        set_flash(resp, "err", "No such reader.")
        return resp
    if action == "suspend":
        profile.suspended_at = datetime.now(UTC)
        await db.commit()
        await security.audit(
            db,
            "reader.suspend",
            admin_id=admin.id,
            target_type="reader",
            target_id=str(reader_id),
            summary=profile.email,
            ip=client_ip(request),
        )
        set_flash(resp, "ok", "Reader suspended — locked out of the app, data kept.")
    elif action == "unsuspend":
        profile.suspended_at = None
        await db.commit()
        await security.audit(
            db,
            "reader.unsuspend",
            admin_id=admin.id,
            target_type="reader",
            target_id=str(reader_id),
            summary=profile.email,
            ip=client_ip(request),
        )
        set_flash(resp, "ok", "Suspension lifted.")
    else:
        set_flash(resp, "err", "Unknown action.")
    return resp
