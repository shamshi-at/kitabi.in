"""Suggested edits — the escalation queue for catalog revisions. Readers already
review edits to books they contributed; this lists *every* pending revision
(seeded books with no contributor, ones a contributor left sitting) and lets an
admin decide via the API's own decide_revision with the admin override.

A revision is an edit to the Work, or — since 5 Sep 2026 — to one of its
printings (`edition_id`); both share this queue and this decide path.
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
        # An edition revision's payload names Edition fields, so the "current"
        # column has to be read off the printing it targets — read off the Work
        # every one of them would come back None, which renders as "— empty —"
        # and invites an approval against a diff that never showed the old
        # value.
        subject = work
        printing = None
        if rev.edition_id is not None:
            subject = await catalog_service.get_edition_or_404(db, rev.edition_id)
            printing = subject.isbn or (
                f"{subject.page_count} pp" if subject.page_count else str(subject.id)[:8]
            )
        current = {k: getattr(subject, k, None) for k in rev.payload}
        out.append(
            {
                "rev": rev,
                "title": title,
                "proposer": full_name or (f"@{username}" if username else None),
                "current": current,
                "printing": printing,
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
