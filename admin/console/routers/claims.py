"""Author claims — the queue that prompted the whole console. Reuses the API's
own `catalog_service.approve_claim` / `reject_claim`, which already guard the
single write to `authors.linked_user_id`; the console just gives them a face
and records who decided in the audit trail.
"""

import uuid

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy import func, select

from .. import queries, security
from ..deps import CurrentAdmin, DbSession, client_ip
from ..flash import pop_flash, set_flash
from ..models_ref import (
    CLAIM_PENDING,
    Author,
    AuthorClaim,
    Profile,
)
from ..templating import templates

# The claim decision path lives in the API service — reuse it, don't reimplement.
from app.services import catalog_service  # noqa: E402

router = APIRouter(prefix="/moderation")


async def _pending_rows(db: DbSession) -> list[dict]:
    """Each pending claim with its author, the claimant's public identity, and
    how many *other* readers are also claiming that author (the contested case)."""
    rows = (
        await db.execute(
            select(AuthorClaim, Author, Profile)
            .join(Author, Author.id == AuthorClaim.author_id)
            .join(Profile, Profile.id == AuthorClaim.user_id, isouter=True)
            .where(AuthorClaim.status == CLAIM_PENDING)
            .order_by(AuthorClaim.created_at.asc())
        )
    ).all()
    # count works per author + rival claims per author, in two small queries
    author_ids = [a.id for _c, a, _p in rows]
    rivals: dict = {}
    if author_ids:
        rc = (
            await db.execute(
                select(AuthorClaim.author_id, func.count())
                .where(
                    AuthorClaim.status == CLAIM_PENDING,
                    AuthorClaim.author_id.in_(author_ids),
                )
                .group_by(AuthorClaim.author_id)
            )
        ).all()
        rivals = {aid: n for aid, n in rc}
    out = []
    for claim, author, profile in rows:
        out.append(
            {
                "claim": claim,
                "author": author,
                "profile": profile,
                "rivals": rivals.get(author.id, 1),
                "already_linked": author.linked_user_id is not None,
            }
        )
    return out


@router.get("/claims")
async def claims(request: Request, admin: CurrentAdmin, db: DbSession) -> HTMLResponse:
    items = await _pending_rows(db)
    decided = int(
        await db.scalar(
            select(func.count())
            .select_from(AuthorClaim)
            .where(AuthorClaim.status != CLAIM_PENDING)
        )
        or 0
    )
    badges = await queries.nav_badges(db)
    flash = pop_flash(request)
    resp = templates.TemplateResponse(
        request,
        "claims.html",
        {
            "admin": admin,
            "active": "claims",
            "badges": badges,
            "items": items,
            "decided": decided,
            "flash": flash,
        },
    )
    if flash:
        resp.delete_cookie("admin_flash", path="/")
    return resp


@router.post("/claims/{claim_id}/approve")
async def approve(
    request: Request, admin: CurrentAdmin, db: DbSession, claim_id: uuid.UUID
) -> RedirectResponse:
    claim = await db.get(AuthorClaim, claim_id)
    resp = RedirectResponse("/moderation/claims", status_code=303)
    try:
        await catalog_service.approve_claim(db, claim_id, admin.id)
    except Exception as exc:  # noqa: BLE001 — surface the service's structured message
        detail = getattr(exc, "detail", {}) or {}
        set_flash(resp, "err", detail.get("message", "Could not approve this claim."))
        return resp
    author = await db.get(Author, claim.author_id) if claim else None
    await security.audit(
        db,
        "claim.approve",
        admin_id=admin.id,
        target_type="author",
        target_id=str(claim.author_id) if claim else None,
        summary=f"linked {author.name if author else '?'} to reader {claim.user_id if claim else '?'}",
        ip=client_ip(request),
    )
    set_flash(resp, "ok", "Claim approved — the author is now linked.")
    return resp


@router.post("/claims/{claim_id}/reject")
async def reject(
    request: Request, admin: CurrentAdmin, db: DbSession, claim_id: uuid.UUID
) -> RedirectResponse:
    claim = await db.get(AuthorClaim, claim_id)
    resp = RedirectResponse("/moderation/claims", status_code=303)
    try:
        await catalog_service.reject_claim(db, claim_id, admin.id)
    except Exception as exc:  # noqa: BLE001
        detail = getattr(exc, "detail", {}) or {}
        set_flash(resp, "err", detail.get("message", "Could not reject this claim."))
        return resp
    await security.audit(
        db,
        "claim.reject",
        admin_id=admin.id,
        target_type="author",
        target_id=str(claim.author_id) if claim else None,
        ip=client_ip(request),
    )
    set_flash(resp, "ok", "Claim rejected. The shared record is unchanged.")
    return resp
