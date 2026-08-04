"""Duplicate review — the queue for merges the machine will not make alone.

Exact-name clusters are folded by a scheduled job in the API (owner decision:
an identical normalised name in a catalogue this size is overwhelmingly one
entity, and every merge is reversible). What reaches this screen is the softer
evidence — word order, spelling, transliteration — where the machine has a
suspicion and a person has to decide.

Both decisions are recorded. "Merge" folds the rows; "Not the same" writes a
dismissal so the pair never comes back. Without the second, the matchers
recompute from names on every run and the reviewer is asked the same question
forever — a list rather than a queue.

Reuses the API's own merge_service, which owns the guards (no self-merges, no
chained merges, works and fields carried across). The console gives it a face
and records who decided.
"""

import uuid

from app.services import merge_service  # noqa: E402 — the decision path lives in the API
from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy import func, select

from .. import queries, security
from ..deps import CurrentAdmin, DbSession, client_ip
from ..flash import pop_flash, set_flash
from ..models_ref import Edition
from ..models_ref import work_authors as WA
from ..templating import templates

router = APIRouter(prefix="/moderation")

_LABEL = {
    "word_order": "Same words, different order",
    "spelling": "Same name, different spelling",
    "exact": "Identical name",
}


async def _counts(db: DbSession, kind: str, ids: list[uuid.UUID]) -> dict:
    if not ids:
        return {}
    if kind == "authors":
        stmt = (
            select(WA.c.author_id, func.count(WA.c.work_id))
            .where(WA.c.author_id.in_(ids))
            .group_by(WA.c.author_id)
        )
    else:
        stmt = (
            select(Edition.publisher_id, func.count(Edition.id))
            .where(Edition.publisher_id.in_(ids), Edition.deleted_at.is_(None))
            .group_by(Edition.publisher_id)
        )
    return dict((await db.execute(stmt)).all())


async def _queue(db: DbSession) -> list[dict]:
    """Everything awaiting a human, both kinds, with enough context to decide.

    The counts matter: "merge a 34-book row into a 1-book row" is a different
    proposition from "merge two 1-book rows", and the reviewer cannot tell
    without them.
    """
    out: list[dict] = []
    for kind in ("authors", "publishers"):
        candidates = [
            c for c in await merge_service.find_candidates(db, kind) if not c.auto_mergeable
        ]
        ids = [c.survivor_id for c in candidates] + [i for c in candidates for i, _ in c.losers]
        counts = await _counts(db, kind, ids)
        for c in candidates:
            out.append(
                {
                    "kind": kind,
                    "singular": "author" if kind == "authors" else "publisher",
                    "reason": _LABEL.get(c.reason, c.reason),
                    "survivor_id": c.survivor_id,
                    "survivor_name": c.survivor_name,
                    "survivor_count": counts.get(c.survivor_id, 0),
                    "losers": [
                        {"id": i, "name": n, "count": counts.get(i, 0)} for i, n in c.losers
                    ],
                }
            )
    return out


@router.get("/merges")
async def merges(request: Request, admin: CurrentAdmin, db: DbSession) -> HTMLResponse:
    items = await _queue(db)
    badges = await queries.nav_badges(db)
    flash = pop_flash(request)
    resp = templates.TemplateResponse(
        request,
        "merges.html",
        {
            "admin": admin,
            "active": "merges",
            "badges": badges,
            "items": items,
            "flash": flash,
        },
    )
    if flash:
        resp.delete_cookie("admin_flash", path="/")
    return resp


@router.post("/merges/{kind}/{survivor_id}/{loser_id}/merge")
async def do_merge(
    request: Request,
    admin: CurrentAdmin,
    db: DbSession,
    kind: str,
    survivor_id: uuid.UUID,
    loser_id: uuid.UUID,
) -> RedirectResponse:
    resp = RedirectResponse("/moderation/merges", status_code=303)
    if kind not in merge_service.MODELS:
        set_flash(resp, "err", "Unknown kind.")
        return resp

    model = merge_service.MODELS[kind]
    loser = await db.get(model, loser_id)
    loser_name = loser.name if loser else "?"

    if not await merge_service.merge(db, kind, survivor_id, loser_id):
        set_flash(resp, "err", "Could not merge those — one may already be merged.")
        return resp
    await db.commit()

    survivor = await db.get(model, survivor_id)
    await security.audit(
        db,
        "merge.apply",
        admin_id=admin.id,
        target_type=kind,
        target_id=str(survivor_id),
        summary=f"merged “{loser_name}” into “{survivor.name if survivor else '?'}”",
        ip=client_ip(request),
    )
    await db.commit()
    set_flash(resp, "ok", f"Merged “{loser_name}”. It redirects to the survivor now.")
    return resp


@router.post("/merges/{kind}/{a_id}/{b_id}/dismiss")
async def do_dismiss(
    request: Request,
    admin: CurrentAdmin,
    db: DbSession,
    kind: str,
    a_id: uuid.UUID,
    b_id: uuid.UUID,
) -> RedirectResponse:
    """ "Not the same." Recorded, so the pair never comes back."""
    resp = RedirectResponse("/moderation/merges", status_code=303)
    if kind not in merge_service.MODELS:
        set_flash(resp, "err", "Unknown kind.")
        return resp
    await merge_service.dismiss(db, kind, a_id, b_id, by=admin.id)
    await db.commit()
    await security.audit(
        db,
        "merge.dismiss",
        admin_id=admin.id,
        target_type=kind,
        target_id=str(a_id),
        summary="marked as not duplicates",
        ip=client_ip(request),
    )
    await db.commit()
    set_flash(resp, "ok", "Noted — they won't be suggested again.")
    return resp


@router.post("/merges/{kind}/{loser_id}/unmerge")
async def do_unmerge(
    request: Request, admin: CurrentAdmin, db: DbSession, kind: str, loser_id: uuid.UUID
) -> RedirectResponse:
    """Undo a merge. Restores the row and its URL, but NOT which works belonged
    to it — that is a judgement no column recorded, so it is left to a human."""
    resp = RedirectResponse("/moderation/merges", status_code=303)
    if kind not in merge_service.MODELS or not await merge_service.unmerge(db, kind, loser_id):
        set_flash(resp, "err", "That row is not merged.")
        return resp
    await db.commit()
    await security.audit(
        db,
        "merge.undo",
        admin_id=admin.id,
        target_type=kind,
        target_id=str(loser_id),
        summary="unmerged (works stay with the survivor)",
        ip=client_ip(request),
    )
    await db.commit()
    set_flash(resp, "ok", "Unmerged. Its books stayed with the survivor — move them by hand.")
    return resp
