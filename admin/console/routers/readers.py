"""Readers — support, not surveillance. Find an account, see the identity it has
already made public plus aggregate contribution counts, and act when it
misbehaves. It never shows a reader's private shelf, notes or unpublished
reviews. Suspend (any admin) sets profiles.suspended_at, which the API's auth
dependency enforces — a suspended reader is locked out until unsuspended, with
their data intact. Hard account deletion is intentionally NOT a console button:
a real erasure across Layer-2 tables + Supabase Auth is a separate, deliberate
operation, not a one-click action.

Two things a moderator needs that a search box alone can't give: a way to page
through everyone (the list was capped at the 50 newest, with no way to reach the
51st), and a way to ask a *question* of the list — who is suspended, who joined
this week, whose profile is public. Both are query-string state, so a filtered
view is a link somebody can paste to a colleague.
"""

import uuid
from datetime import UTC, datetime, timedelta

from app.services import scoring_service  # noqa: E402
from fastapi import APIRouter, Query, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy import func, or_, select

from .. import queries, security
from ..deps import CurrentAdmin, DbSession, client_ip
from ..flash import pop_flash, set_flash
from ..models_ref import DeviceToken, Profile, SyncOp
from ..templating import templates

router = APIRouter(prefix="/readers")

PAGE_SIZE = 50

# The saved questions the list can answer. Each is a label plus the condition it
# adds — kept here rather than in the template so the count beside a filter and
# the rows behind it can never be computed two different ways.
FILTERS = {
    "all": "Everyone",
    "active": "Not suspended",
    "suspended": "Suspended",
    "new": "Joined in the last 7 days",
    "public": "Public profile",
}

SORTS = {"new": "Newest first", "old": "Oldest first", "name": "Name A–Z"}


def _conditions(which: str) -> list:
    base = [Profile.deleted_at.is_(None)]
    if which == "active":
        return [*base, Profile.suspended_at.is_(None)]
    if which == "suspended":
        return [*base, Profile.suspended_at.is_not(None)]
    if which == "new":
        return [*base, Profile.created_at >= datetime.now(UTC) - timedelta(days=7)]
    if which == "public":
        return [*base, Profile.profile_visible.is_(True)]
    return base


def _order(sort: str):  # noqa: ANN202 — SQLAlchemy ordering clause
    if sort == "old":
        return Profile.created_at.asc()
    if sort == "name":
        return Profile.full_name.asc().nulls_last()
    return Profile.created_at.desc()


@router.get("")
async def readers(
    request: Request,
    admin: CurrentAdmin,
    db: DbSession,
    q: str = Query(default=""),
    which: str = Query(default="all", alias="filter"),
    sort: str = Query(default="new"),
    page: int = Query(default=1, ge=1),
) -> HTMLResponse:
    q = q.strip()
    which = which if which in FILTERS else "all"
    sort = sort if sort in SORTS else "new"

    conds = _conditions(which)
    if q:
        like = f"%{q}%"
        conds.append(
            or_(
                Profile.full_name.ilike(like),
                Profile.username.ilike(like),
                Profile.email.ilike(like),
            )
        )
    # The matching count, not the table count: a "50 accounts" heading over a
    # filtered list is a wrong answer to the question the operator just asked.
    matching = int(await db.scalar(select(func.count()).select_from(Profile).where(*conds)) or 0)
    pages = max(1, -(-matching // PAGE_SIZE))
    page = min(page, pages)
    rows = (
        (
            await db.execute(
                select(Profile)
                .where(*conds)
                .order_by(_order(sort))
                .offset((page - 1) * PAGE_SIZE)
                .limit(PAGE_SIZE)
            )
        )
        .scalars()
        .all()
    )
    total = int(
        await db.scalar(
            select(func.count()).select_from(Profile).where(Profile.deleted_at.is_(None))
        )
        or 0
    )
    suspended = int(
        await db.scalar(
            select(func.count())
            .select_from(Profile)
            .where(Profile.deleted_at.is_(None), Profile.suspended_at.is_not(None))
        )
        or 0
    )
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
            "suspended": suspended,
            "matching": matching,
            "filters": FILTERS,
            "which": which,
            "sorts": SORTS,
            "sort": sort,
            "page": page,
            "pages": pages,
            "flash": flash,
        },
    )
    if flash:
        resp.delete_cookie("admin_flash", path="/")
    return resp


async def _last_seen(db: DbSession, reader_id: uuid.UUID) -> datetime | None:
    """When this reader's device last pushed anything. There is no `last_seen`
    column on the profile, and adding one would mean a write on every sync; the
    sync log already answers the question for free."""
    return await db.scalar(select(func.max(SyncOp.applied_at)).where(SyncOp.user_id == reader_id))


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
    platforms = (
        await db.execute(
            select(DeviceToken.platform, func.count())
            .where(DeviceToken.user_id == reader_id)
            .group_by(DeviceToken.platform)
        )
    ).all()
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
            "last_seen": await _last_seen(db, reader_id),
            "platforms": [(p or "unknown", int(n)) for p, n in platforms],
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

    async def record(what: str) -> None:
        await security.audit(
            db,
            what,
            admin_id=admin.id,
            target_type="reader",
            target_id=str(reader_id),
            summary=profile.email,
            ip=client_ip(request),
        )

    if action == "suspend":
        profile.suspended_at = datetime.now(UTC)
        await db.commit()
        await record("reader.suspend")
        set_flash(resp, "ok", "Reader suspended — locked out of the app, data kept.")
    elif action == "unsuspend":
        profile.suspended_at = None
        await db.commit()
        await record("reader.unsuspend")
        set_flash(resp, "ok", "Suspension lifted.")
    elif action == "hide-profile":
        # The gentler half of moderation, and the half that was missing: an
        # offensive display name or handle is public on kitabi.in the moment it
        # is typed, and suspending the whole account for it is the only tool a
        # moderator had. Clearing `profile_visible` takes the public page, the
        # shared library and every public review down together (the API gates
        # all three on it) while the reader keeps their own library — and it
        # touches nothing else, so putting it back restores exactly what was
        # there rather than a moderator's guess at it.
        profile.profile_visible = False
        profile.updated_at = datetime.now(UTC)
        await db.commit()
        await record("reader.hide_profile")
        set_flash(
            resp,
            "ok",
            "Profile hidden — their public page, shared library and public reviews are off "
            "the website. They keep full use of the app.",
        )
    elif action == "show-profile":
        profile.profile_visible = True
        profile.updated_at = datetime.now(UTC)
        await db.commit()
        await record("reader.show_profile")
        set_flash(resp, "ok", "Profile is public again, exactly as the reader had it.")
    else:
        set_flash(resp, "err", "Unknown action.")
    return resp
