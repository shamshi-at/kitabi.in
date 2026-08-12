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

The screen shows a **cluster**, not a pair, because that is what the matchers
actually produce — three Vaikom Muhammad Basheers group together, and asking
"is B the same as A?" three times is three chances to answer inconsistently.
So: every member is listed, the reviewer picks which one survives (the machine
only supplies the default), fixes its name if neither spelling is right, and
folds the rest in one action. Reported 12 Aug 2026, from a queue proposing
"Rev. William Rev. William Benham" as the row to keep — the survivor heuristic
had no way to say "both of these are wrong".

Reuses the API's own merge_service, which owns the guards (no self-merges, no
chained merges, works and fields carried across). The console gives it a face
and records who decided.
"""

import uuid
from typing import Annotated

from app.services import merge_service  # noqa: E402 — the decision path lives in the API
from fastapi import APIRouter, Form, Request
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


async def _rows_by_id(db: DbSession, kind: str, ids: list[uuid.UUID]) -> dict:
    """The model rows behind a cluster — for the romanized name and language,
    which are what actually tell two same-looking records apart on screen."""
    if not ids:
        return {}
    model = merge_service.MODELS[kind]
    found = (await db.execute(select(model).where(model.id.in_(ids)))).scalars().all()
    return {r.id: r for r in found}


async def _queue(db: DbSession) -> list[dict]:
    """Everything awaiting a human, both kinds, with enough context to decide.

    The counts matter: "merge a 34-book row into a 1-book row" is a different
    proposition from "merge two 1-book rows", and the reviewer cannot tell
    without them. Every member of the cluster is returned — the machine's pick
    is a default (`survivor_id`), not a verdict.
    """
    out: list[dict] = []
    for kind in ("authors", "publishers"):
        candidates = [
            c for c in await merge_service.find_candidates(db, kind) if not c.auto_mergeable
        ]
        ids = [c.survivor_id for c in candidates] + [i for c in candidates for i, _ in c.losers]
        counts = await _counts(db, kind, ids)
        rows = await _rows_by_id(db, kind, ids)
        for c in candidates:
            members = [
                {
                    "id": row_id,
                    "name": name,
                    "translit": getattr(rows.get(row_id), "name_translit", None),
                    "language": getattr(rows.get(row_id), "primary_language", None),
                    "count": counts.get(row_id, 0),
                    "suspect": merge_service.repeats_itself(name),
                }
                for row_id, name in [(c.survivor_id, c.survivor_name), *c.losers]
            ]
            out.append(
                {
                    "kind": kind,
                    "singular": "author" if kind == "authors" else "publisher",
                    "unit": "book" if kind == "authors" else "edition",
                    "reason": _LABEL.get(c.reason, c.reason),
                    "survivor_id": c.survivor_id,
                    "members": members,
                    # Nothing in the cluster carries anything: merging is then
                    # pure tidying, and which row survives barely matters.
                    "empty": not any(m["count"] for m in members),
                    "suspect": any(m["suspect"] for m in members),
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


@router.post("/merges/{kind}/merge")
async def do_merge(
    request: Request,
    admin: CurrentAdmin,
    db: DbSession,
    kind: str,
    survivor_id: Annotated[uuid.UUID, Form()],
    member_ids: Annotated[list[uuid.UUID], Form()],
    survivor_name: Annotated[str, Form()] = "",
) -> RedirectResponse:
    """Fold a whole cluster into the row the reviewer chose to keep, under the
    name they chose to keep it under.

    One decision, one action: a cluster of four asked as three separate
    questions invites three separate answers. `member_ids` carries every row on
    screen and `survivor_id` names the keeper, so a member the reviewer already
    dismissed is simply not in the form.

    The rename rides along rather than being its own step, because renaming
    first would break the merge: the matchers group by name, so correcting one
    spelling drops the cluster out of the queue before it can be folded.
    """
    resp = RedirectResponse("/moderation/merges", status_code=303)
    if kind not in merge_service.MODELS:
        set_flash(resp, "err", "Unknown kind.")
        return resp
    if survivor_id not in member_ids:
        # The keeper must be one of the rows offered, or a hand-made POST could
        # fold this cluster into any row in the catalog.
        set_flash(resp, "err", "The record to keep must be one of the listed ones.")
        return resp

    model = merge_service.MODELS[kind]

    # Editing the catalog is an editor's job; the queue itself is open to
    # moderators, so the field is not rendered for them and is ignored here.
    renamed = ""
    survivor_name = " ".join(survivor_name.split())
    if survivor_name and admin.role in ("editor", "super_admin"):
        keeper = await db.get(model, survivor_id)
        if keeper is not None and keeper.name != survivor_name:
            previous, keeper.name = keeper.name, survivor_name
            await db.commit()
            renamed = f" (renamed from “{previous}”)"
            await security.audit(
                db,
                "catalog.rename",
                admin_id=admin.id,
                target_type=kind,
                target_id=str(survivor_id),
                summary=f"“{previous}” → “{survivor_name}” (while merging)",
                ip=client_ip(request),
            )
            await db.commit()

    merged: list[str] = []
    for loser_id in member_ids:
        if loser_id == survivor_id:
            continue
        loser = await db.get(model, loser_id)
        if await merge_service.merge(db, kind, survivor_id, loser_id):
            merged.append(loser.name if loser else "?")
    if not merged:
        # The rename above (if any) has already committed — say so rather than
        # reporting a flat failure for a request that did change something.
        set_flash(resp, "err", f"Nothing was merged{renamed} — those rows may already be merged.")
        return resp
    await db.commit()

    survivor = await db.get(model, survivor_id)
    final_name = survivor.name if survivor else "?"
    await security.audit(
        db,
        "merge.apply",
        admin_id=admin.id,
        target_type=kind,
        target_id=str(survivor_id),
        summary="merged " + ", ".join(f"“{n}”" for n in merged) + f" into “{final_name}”",
        ip=client_ip(request),
    )
    await db.commit()
    set_flash(
        resp,
        "ok",
        f"Merged {len(merged)} into “{final_name}”{renamed}. The old URLs redirect here now.",
    )
    return resp


@router.post("/merges/{kind}/dismiss")
async def do_dismiss(
    request: Request,
    admin: CurrentAdmin,
    db: DbSession,
    kind: str,
    row_id: Annotated[uuid.UUID, Form()],
    member_ids: Annotated[list[uuid.UUID], Form()],
) -> RedirectResponse:
    """ "Not the same." Recorded, so it never comes back.

    Dismissed against every other member of the cluster, not just the proposed
    survivor: in a cluster of three, rejecting C against A alone leaves (B, C)
    unanswered, and the next run proposes it — the reviewer would have to say
    "not the same" about the same row twice to make it stop.
    """
    resp = RedirectResponse("/moderation/merges", status_code=303)
    if kind not in merge_service.MODELS:
        set_flash(resp, "err", "Unknown kind.")
        return resp
    model = merge_service.MODELS[kind]
    row = await db.get(model, row_id)
    for other_id in member_ids:
        await merge_service.dismiss(db, kind, row_id, other_id, by=admin.id)
    await db.commit()
    await security.audit(
        db,
        "merge.dismiss",
        admin_id=admin.id,
        target_type=kind,
        target_id=str(row_id),
        summary=f"“{row.name if row else '?'}” marked as not a duplicate of the others",
        ip=client_ip(request),
    )
    await db.commit()
    set_flash(resp, "ok", "Noted — it won't be suggested against those again.")
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
