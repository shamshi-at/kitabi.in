"""What readers just put into the shared catalog — the queue that did not exist.

Every other moderation screen waits for something to be *flagged*: a claim
filed, an edit suggested, a review reported. But the largest opening in Kitabi
is the one nobody has to flag — any signed-in reader can create a Work, an
Author, a Publisher and an Edition, and upload the cover art that goes with
them, and until now a nonsense title or an obscene cover would sit on the public
website until a reader happened to report something adjacent to it.

So this is a *review-by-default* feed rather than a queue of complaints: newest
reader contributions first, with who added them, and a "reviewed" mark so two
moderators don't re-read the same rows. Nothing here can be reported by a
reader, so nothing here would ever reach `/moderation/reports`.

The mark is deliberately the lightest thing that works — an audit-log row, which
the console already writes for every action and never deletes. A moderator's
"reviewed ✓" is therefore itself part of the trail, and no new table is needed.

One asymmetry to know before reading the queries: **only works and authors
record who created them.** `publishers` and `editions` have no
`created_by_user_id` column, so a publisher shows no contributor and an edition
borrows its parent work's. Rather than hide the two kinds that can't be
attributed — readers create them just the same, from the add-book form's
typeaheads — they are shown with an honest blank.
"""

import uuid
from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Query, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy import String, cast, select

from .. import cache, insights, queries, security
from ..deps import DbSession, RequireEditor, client_ip
from ..flash import pop_flash, set_flash
from ..models_ref import AdminAuditLog, Author, Edition, Publisher, Work
from ..templating import templates

router = APIRouter(prefix="/moderation")

# How far back the feed looks. Value is days.
WINDOWS = {"1": 1, "7": 7, "30": 30, "90": 90}
DEFAULT_WINDOW = "7"

# The audit action a "reviewed" tick writes. One action name for every kind, with
# the kind in target_type, so "has this been looked at?" is a single indexed read.
REVIEWED = "content.reviewed"

# kind -> (label, model, name column, adder column or None, detail-page prefix)
KINDS = {
    "work": ("Work", Work, Work.title, Work.created_by_user_id, "/catalog/works/"),
    "author": ("Author", Author, Author.name, Author.created_by_user_id, "/catalog/authors/"),
    "publisher": ("Publisher", Publisher, Publisher.name, None, "/catalog/publishers/"),
    "edition": ("Edition", Edition, None, None, "/catalog/works/"),
}


def _since(window: str) -> datetime:
    return datetime.now(UTC) - timedelta(days=WINDOWS.get(window, WINDOWS[DEFAULT_WINDOW]))


async def _reviewed_ids(db: DbSession, ids: list[str]) -> set[str]:
    """Which of `ids` an admin has already ticked. One query, not one per row."""
    if not ids:
        return set()
    rows = (
        await db.execute(
            select(AdminAuditLog.target_id).where(
                AdminAuditLog.action == REVIEWED, AdminAuditLog.target_id.in_(ids)
            )
        )
    ).all()
    return {str(r[0]) for r in rows}


async def _editions_since(db: DbSession, since: datetime, limit: int) -> list[dict]:
    """New editions, named and attributed through their parent work — the
    edition table records neither a title nor a contributor of its own."""
    rows = (
        await db.execute(
            select(
                Edition.id,
                Edition.work_id,
                Edition.isbn,
                Edition.created_at,
                Work.title,
                Work.created_by_user_id,
            )
            .join(Work, Work.id == Edition.work_id)
            .where(Edition.deleted_at.is_(None), Edition.created_at >= since)
            .order_by(Edition.created_at.desc())
            .limit(limit)
        )
    ).all()
    return [
        {
            "kind": "edition",
            "label": "Edition",
            "id": row_id,
            "name": title + (f" · ISBN {isbn}" if isbn else ""),
            "created_at": created,
            "adder_id": adder,
            "href": f"/catalog/works/{work_id}",
        }
        for row_id, work_id, isbn, created, title, adder in rows
    ]


async def _feed(db: DbSession, window: str, kind: str, unreviewed_only: bool) -> list[dict]:
    since = _since(window)
    limit = 200
    rows: list[dict] = []
    for key, (label, model, name_col, adder_col, href) in KINDS.items():
        if kind not in ("all", key):
            continue
        if key == "edition":
            rows.extend(await _editions_since(db, since, limit))
            continue
        conds = [model.deleted_at.is_(None), model.created_at >= since]
        if adder_col is not None:
            # Reader contributions only. A bulk-seeded row has no contributor
            # and is not what this screen is for. Publishers have no such
            # column, so every new one is shown.
            conds.append(adder_col.is_not(None))
        adder_select = adder_col if adder_col is not None else cast(None, String)
        found = (
            await db.execute(
                select(model.id, name_col, model.created_at, adder_select)
                .where(*conds)
                .order_by(model.created_at.desc())
                .limit(limit)
            )
        ).all()
        for row_id, name, created, adder in found:
            rows.append(
                {
                    "kind": key,
                    "label": label,
                    "id": row_id,
                    "name": name,
                    "created_at": created,
                    "adder_id": adder,
                    "href": f"{href}{row_id}",
                }
            )
    rows.sort(key=lambda r: r["created_at"], reverse=True)
    rows = rows[:limit]
    await insights.attach_adders(db, rows)
    reviewed = await _reviewed_ids(db, [str(r["id"]) for r in rows])
    for r in rows:
        r["reviewed"] = str(r["id"]) in reviewed
    if unreviewed_only:
        rows = [r for r in rows if not r["reviewed"]]
    return rows


@router.get("/incoming")
async def incoming(
    request: Request,
    admin: RequireEditor,
    db: DbSession,
    window: str = Query(default=DEFAULT_WINDOW),
    kind: str = Query(default="all"),
    show: str = Query(default="new"),
) -> HTMLResponse:
    window = window if window in WINDOWS else DEFAULT_WINDOW
    kind = kind if kind in KINDS else "all"
    rows = await _feed(db, window, kind, unreviewed_only=(show != "all"))
    badges = await queries.nav_badges(db)
    flash = pop_flash(request)
    resp = templates.TemplateResponse(
        request,
        "incoming.html",
        {
            "admin": admin,
            "active": "incoming",
            "badges": badges,
            "rows": rows,
            "windows": WINDOWS,
            "window": window,
            "kinds": {k: v[0] for k, v in KINDS.items()},
            "kind": kind,
            "show": show,
            "flash": flash,
        },
    )
    if flash:
        resp.delete_cookie("admin_flash", path="/")
    return resp


@router.post("/incoming/{kind}/{row_id}/reviewed")
async def mark_reviewed(
    request: Request, admin: RequireEditor, db: DbSession, kind: str, row_id: uuid.UUID
) -> RedirectResponse:
    """Tick a row as looked at. Ticking twice just writes a second audit row,
    which is honest — two people did check it."""
    back = request.headers.get("referer") or "/moderation/incoming"
    resp = RedirectResponse(back, status_code=303)
    if kind not in KINDS:
        set_flash(resp, "err", "Unknown kind.")
        return resp
    await security.audit(
        db,
        REVIEWED,
        admin_id=admin.id,
        target_type=kind,
        target_id=str(row_id),
        summary="marked reviewed",
        ip=client_ip(request),
    )
    set_flash(resp, "ok", "Marked reviewed.")
    return resp


# ---------------------------------------------------------------------------
# Reader-uploaded images.
#
# A cover photographed on a phone goes straight into the public `covers` bucket
# and onto the public website, with nothing between the reader and the world.
# This is the screen where a human looks at them. It shows only images WE host
# (the bucket prefix) — an OpenLibrary cover is not a reader's upload and is not
# this screen's problem.
# ---------------------------------------------------------------------------

# source -> (label, model, column)
IMAGE_SOURCES = {
    "cover": ("Edition cover", Edition, "cover_url"),
    "back_cover": ("Edition back cover", Edition, "back_cover_url"),
    "author": ("Author portrait", Author, "image_url"),
    "publisher": ("Publisher logo", Publisher, "logo_url"),
}

_IMAGE_HREF = {
    "cover": "/catalog/works/",
    "back_cover": "/catalog/works/",
    "author": "/catalog/authors/",
    "publisher": "/catalog/publishers/",
}


def bucket_prefix() -> str | None:
    """The public prefix of our own Storage bucket, or None when the API has no
    Supabase URL configured (a dev box) — in which case the screen honestly
    shows nothing rather than guessing at what is ours."""
    from app.core.config import get_settings  # noqa: PLC0415 — lazy, keeps the import cheap

    base = (get_settings().supabase_url or "").strip().rstrip("/")
    return f"{base}/storage/v1/object/public/covers/" if base else None


async def _images(db: DbSession, window: str) -> list[dict]:
    prefix = bucket_prefix()
    if not prefix:
        return []
    since = _since(window)
    out: list[dict] = []
    for source, (label, model, column) in IMAGE_SOURCES.items():
        col = getattr(model, column)
        if model is Edition:
            # An edition has no title and no contributor — both come from the
            # work it belongs to, which is also the page a moderator opens.
            stmt = select(
                Edition.id, col, Edition.updated_at, Work.title, Work.created_by_user_id, Work.id
            ).join(Work, Work.id == Edition.work_id)
        else:
            adder = model.created_by_user_id if model is Author else cast(None, String)
            stmt = select(model.id, col, model.updated_at, model.name, adder, model.id)
        rows = (
            await db.execute(
                stmt.where(
                    model.deleted_at.is_(None),
                    col.is_not(None),
                    col.like(f"{prefix}%"),
                    model.updated_at >= since,
                )
                .order_by(model.updated_at.desc())
                .limit(120)
            )
        ).all()
        for row_id, url, updated, name, adder_id, link_id in rows:
            out.append(
                {
                    "source": source,
                    "label": label,
                    "id": row_id,
                    "url": url,
                    "name": name or "Untitled",
                    "updated_at": updated,
                    "adder_id": adder_id,
                    "href": f"{_IMAGE_HREF[source]}{link_id}",
                }
            )
    out.sort(key=lambda r: r["updated_at"], reverse=True)
    out = out[:120]
    await insights.attach_adders(db, out)
    return out


@router.get("/images")
async def images(
    request: Request,
    admin: RequireEditor,
    db: DbSession,
    window: str = Query(default="30"),
) -> HTMLResponse:
    window = window if window in WINDOWS else "30"
    rows = await _images(db, window)
    badges = await queries.nav_badges(db)
    flash = pop_flash(request)
    resp = templates.TemplateResponse(
        request,
        "images.html",
        {
            "admin": admin,
            "active": "images",
            "badges": badges,
            "rows": rows,
            "windows": WINDOWS,
            "window": window,
            "configured": bucket_prefix() is not None,
            "flash": flash,
        },
    )
    if flash:
        resp.delete_cookie("admin_flash", path="/")
    return resp


@router.post("/images/{source}/{row_id}/remove")
async def remove_image(
    request: Request, admin: RequireEditor, db: DbSession, source: str, row_id: uuid.UUID
) -> RedirectResponse:
    """Take an image off a catalog row.

    The column is cleared; the stored object is left in the bucket and the URL
    goes into the audit summary, so a mistaken removal is undone by pasting the
    URL back rather than by hunting for a deleted file. Same reasoning as
    `catalog.remove_publisher_logo`, which this generalises to every image the
    catalog carries.
    """
    back = request.headers.get("referer") or "/moderation/images"
    resp = RedirectResponse(back, status_code=303)
    if source not in IMAGE_SOURCES:
        set_flash(resp, "err", "Unknown image kind.")
        return resp
    label, model, column = IMAGE_SOURCES[source]
    row = await db.get(model, row_id)
    if row is None:
        set_flash(resp, "err", "That record no longer exists.")
        return resp
    previous = getattr(row, column)
    if not previous:
        set_flash(resp, "err", "There was no image to remove.")
        return resp
    setattr(row, column, None)
    row.updated_at = datetime.now(UTC)
    await db.commit()
    cache.invalidate_catalog()
    await security.audit(
        db,
        f"image.remove.{source}",
        admin_id=admin.id,
        target_type=source,
        target_id=str(row_id),
        summary=f"{label} · was {previous}",
        ip=client_ip(request),
    )
    set_flash(resp, "ok", f"{label} removed. The URL is in the audit log if it was a mistake.")
    return resp
