"""Catalog operations — search (the same spelling-fold the app uses), a
quality-gap worklist, and the duplicate merge. Merge is the highest-risk action
in the console (it moves other readers' ratings/reviews and the editions their
library entries hang off), so it always previews what will move before it runs,
is editor+ only, and is audited. It reuses the API's merge_preview / merge_works.
"""

import uuid
from typing import Annotated

from app.services import catalog_service  # noqa: E402
from fastapi import APIRouter, Form, Query, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from sqlalchemy import func, select

from .. import queries, security
from ..deps import DbSession, RequireEditor, client_ip
from ..flash import pop_flash, set_flash
from ..models_ref import Author, Edition, LibraryEntry, Work
from ..templating import templates

router = APIRouter(prefix="/catalog")


async def _work_rows(db: DbSession, works: list) -> list[dict]:
    rows = []
    for w in works:
        editions = int(
            await db.scalar(
                select(func.count())
                .select_from(Edition)
                .where(Edition.work_id == w.id, Edition.deleted_at.is_(None))
            )
            or 0
        )
        shelved = int(
            await db.scalar(
                select(func.count())
                .select_from(LibraryEntry)
                .where(
                    LibraryEntry.edition_id.in_(select(Edition.id).where(Edition.work_id == w.id)),
                    LibraryEntry.deleted_at.is_(None),
                )
            )
            or 0
        )
        author = ", ".join(a.name for a in w.authors) if w.authors else "—"
        rows.append({"w": w, "author": author, "editions": editions, "shelved": shelved})
    return rows


@router.get("")
async def catalog(
    request: Request, admin: RequireEditor, db: DbSession, q: str = Query(default="")
) -> HTMLResponse:
    q = q.strip()
    works = await catalog_service.search_local(db, q) if q else []
    rows = await _work_rows(db, works)

    # Quality gaps — the columns a bulk seed leaves thin.
    async def count(model, *cond):  # noqa: ANN001
        return int(await db.scalar(select(func.count()).select_from(model).where(*cond)) or 0)

    gaps = {
        "no_cover": await count(Edition, Edition.deleted_at.is_(None), Edition.cover_url.is_(None)),
        "no_desc": await count(Work, Work.deleted_at.is_(None), Work.description.is_(None)),
        "no_isbn": await count(Edition, Edition.deleted_at.is_(None), Edition.isbn.is_(None)),
        "no_works_author": await count(
            Author,
            Author.deleted_at.is_(None),
            ~Author.id.in_(select(func.distinct(catalog_service.work_authors.c.author_id))),
        ),
    }
    badges = await queries.nav_badges(db)
    flash = pop_flash(request)
    resp = templates.TemplateResponse(
        request,
        "catalog.html",
        {
            "admin": admin,
            "active": "catalog",
            "badges": badges,
            "q": q,
            "rows": rows,
            "gaps": gaps,
            "flash": flash,
        },
    )
    if flash:
        resp.delete_cookie("admin_flash", path="/")
    return resp


@router.get("/merge")
async def merge_preview(
    request: Request,
    admin: RequireEditor,
    db: DbSession,
    keep: Annotated[uuid.UUID, Query()],
    absorb: Annotated[uuid.UUID, Query()],
) -> HTMLResponse:
    badges = await queries.nav_badges(db)
    try:
        preview = await catalog_service.merge_preview(db, keep, absorb)
    except Exception as exc:  # noqa: BLE001
        resp = RedirectResponse("/catalog", status_code=303)
        set_flash(
            resp, "err", (getattr(exc, "detail", {}) or {}).get("message", "Cannot merge those.")
        )
        return resp
    return templates.TemplateResponse(
        request,
        "merge.html",
        {
            "admin": admin,
            "active": "catalog",
            "badges": badges,
            "p": preview,
            "keep": keep,
            "absorb": absorb,
        },
    )


@router.post("/merge")
async def merge_execute(
    request: Request,
    admin: RequireEditor,
    db: DbSession,
    keep: Annotated[uuid.UUID, Form()],
    absorb: Annotated[uuid.UUID, Form()],
    confirm: Annotated[str, Form()] = "",
) -> RedirectResponse:
    resp = RedirectResponse("/catalog", status_code=303)
    if confirm != "MERGE":
        set_flash(resp, "err", "Merge not confirmed.")
        return resp
    try:
        result = await catalog_service.merge_works(db, keep, absorb)
    except Exception as exc:  # noqa: BLE001
        set_flash(resp, "err", (getattr(exc, "detail", {}) or {}).get("message", "Merge failed."))
        return resp
    await security.audit(
        db,
        "work.merge",
        admin_id=admin.id,
        target_type="work",
        target_id=str(keep),
        summary=f"{result['absorbed_title']} → {result['keep_title']}",
        ip=client_ip(request),
    )
    set_flash(resp, "ok", f"Merged “{result['absorbed_title']}” into “{result['keep_title']}”.")
    return resp
