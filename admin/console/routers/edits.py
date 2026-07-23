"""Suggested edits — the escalation queue for catalog revisions. Readers already
review edits to books they contributed; this lists *every* pending revision
(seeded books with no contributor, ones a contributor left sitting) and lets an
admin decide via the API's own decide_revision with the admin override.
"""

import uuid

from app.services import catalog_service  # noqa: E402 — reuse the decision path
from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy import select

from .. import queries, security
from ..deps import DbSession, RequireEditor, client_ip
from ..flash import pop_flash, set_flash
from ..models_ref import Profile, Work, WorkRevision
from ..templating import templates

router = APIRouter(prefix="/moderation")

# Edits change the shared catalog, so this is an editor+ surface (moderators
# work claims/reports, editors also fix the catalog).


async def _pending(db: DbSession) -> list[dict]:
    rows = (
        await db.execute(
            select(WorkRevision, Work.title, Profile.full_name, Profile.username)
            .join(Work, Work.id == WorkRevision.work_id)
            .outerjoin(Profile, Profile.id == WorkRevision.proposed_by_user_id)
            .where(WorkRevision.status == "pending", Work.deleted_at.is_(None))
            .order_by(WorkRevision.created_at)
        )
    ).all()
    out = []
    for rev, title, full_name, username in rows:
        work = await catalog_service.get_work_or_404(db, rev.work_id)
        # Current values for each field the revision proposes to change.
        current = {k: getattr(work, k, None) for k in rev.payload}
        out.append(
            {
                "rev": rev,
                "title": title,
                "proposer": full_name or (f"@{username}" if username else None),
                "current": current,
                "orphan": work.created_by_user_id is None,
            }
        )
    return out


@router.get("/edits")
async def edits(request: Request, admin: RequireEditor, db: DbSession) -> HTMLResponse:
    items = await _pending(db)
    badges = await queries.nav_badges(db)
    flash = pop_flash(request)
    resp = templates.TemplateResponse(
        request,
        "edits.html",
        {"admin": admin, "active": "edits", "badges": badges, "items": items, "flash": flash},
    )
    if flash:
        resp.delete_cookie("admin_flash", path="/")
    return resp


@router.post("/edits/{revision_id}/{decision}")
async def decide(
    request: Request,
    admin: RequireEditor,
    db: DbSession,
    revision_id: uuid.UUID,
    decision: str,
) -> RedirectResponse:
    resp = RedirectResponse("/moderation/edits", status_code=303)
    if decision not in ("approve", "reject"):
        set_flash(resp, "err", "Unknown decision.")
        return resp
    try:
        await catalog_service.decide_revision(
            db, revision_id, admin.id, approve=(decision == "approve"), admin_override=True
        )
    except Exception as exc:  # noqa: BLE001
        detail = getattr(exc, "detail", {}) or {}
        set_flash(resp, "err", detail.get("message", "Could not apply that decision."))
        return resp
    await security.audit(
        db,
        f"revision.{decision}",
        admin_id=admin.id,
        target_type="revision",
        target_id=str(revision_id),
        ip=client_ip(request),
    )
    set_flash(resp, "ok", f"Edit {decision}d.")
    return resp
